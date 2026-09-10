import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';

import {
  BilledFailure,
  Budget,
  costOf,
  ICON_CEILING_FRACTION,
  type Mode,
  RESERVATION_TTL_SECONDS,
  reserveUsd,
  type Rpc,
  WARN_AT,
} from './budget.ts';

/// Deciding whether a call may spend, without spending anything (B02).
///
/// Every test here runs without a database and without a dollar. The ledger
/// below stands in for the SQL: same three functions, same contract, same
/// arithmetic. What it cannot stand in for is the row lock that makes the real
/// one atomic — so it is deliberately single-threaded, which is that
/// guarantee by other means. The thing worth proving in TypeScript is the
/// shape of the conversation: that the reservation is taken *before* the model
/// is called, that what is outstanding counts against the ceiling, and that a
/// counter nobody can read stops the spending instead of waving it through.

/// A stand-in for `ai_reservations` and `ai_usage`.
class FakeLedger {
  spent = 0;
  calls: { name: string; args: Record<string, unknown> }[] = [];
  /// Seconds since the epoch, moved by hand so expiry can be watched.
  clock = 1_000;
  /// What the next RPC should do instead of answering.
  breaks: 'never' | 'throws' | 'nonsense' = 'never';

  private reservations = new Map<string, { amount: number; expires: number }>();
  private nextId = 1;

  /// Everything outstanding and not yet expired, as the SQL would sum it.
  get reserved(): number {
    this.sweep();
    let total = 0;
    for (const r of this.reservations.values()) total += r.amount;
    return total;
  }

  get outstanding(): number {
    this.sweep();
    return this.reservations.size;
  }

  private sweep(): void {
    for (const [id, r] of this.reservations) {
      if (r.expires <= this.clock) this.reservations.delete(id);
    }
  }

  rpc: Rpc = (name, args) => {
    this.calls.push({ name, args });
    if (this.breaks === 'throws') {
      return Promise.reject(new Error('the ledger is unreachable'));
    }
    if (this.breaks === 'nonsense') return Promise.resolve([{}]);

    switch (name) {
      case 'reserve_ai_spend': {
        const ceiling = Number(args.p_ceiling_usd);
        const reserved = this.reserved;
        if (!(ceiling > 0) || this.spent + reserved >= ceiling) {
          return Promise.resolve([{
            reservation_id: null,
            spent_usd: this.spent,
            reserved_usd: reserved,
            allowed: false,
          }]);
        }
        const id = `r${this.nextId++}`;
        this.reservations.set(id, {
          amount: Number(args.p_amount_usd),
          expires: this.clock + Number(args.p_ttl_seconds),
        });
        return Promise.resolve([{
          reservation_id: id,
          spent_usd: this.spent,
          reserved_usd: reserved,
          allowed: true,
        }]);
      }
      case 'settle_ai_spend': {
        this.spent += Number(args.p_cost_usd);
        this.reservations.delete(String(args.p_reservation_id));
        return Promise.resolve({ cost_usd: this.spent });
      }
      case 'release_ai_spend': {
        this.reservations.delete(String(args.p_reservation_id));
        return Promise.resolve(null);
      }
    }
    throw new Error(`no such function: ${name}`);
  };
}

const CEILING = 25;

Deno.test('a counter nobody can read stops the spending', async () => {
  // The defect: `callRpc` answered null for a missing env var, a non-OK
  // response and any throw alike, so an unreadable counter read as a month
  // that had cost nothing — and every paid mode carried on.
  const ledger = new FakeLedger();
  ledger.breaks = 'throws';
  const decision = await new Budget(ledger.rpc, CEILING).reserve('extract');

  assertEquals(decision.allowed, false);
  assert(!decision.allowed && decision.status === 503);
});

Deno.test('and an answer it cannot make sense of stops it too', async () => {
  // A row with no `allowed` in it is not permission. Reading it as one is the
  // same failure wearing a 200.
  const ledger = new FakeLedger();
  ledger.breaks = 'nonsense';
  const decision = await new Budget(ledger.rpc, CEILING).reserve('extract');

  assertEquals(decision.allowed, false);
});

Deno.test('a ceiling nobody can parse stops it as well', async () => {
  // AI_MONTHLY_CEILING_USD=twenty is NaN, and NaN >= 1 is false, so the old
  // arithmetic let everything through on a typo.
  const ledger = new FakeLedger();
  for (const ceiling of [Number('twenty'), 0, -5]) {
    const decision = await new Budget(ledger.rpc, ceiling).reserve('extract');
    assertEquals(decision.allowed, false, `${ceiling} was allowed`);
    assert(
      !decision.allowed &&
        decision.error.includes('AI_MONTHLY_CEILING_USD'),
      'the message does not name the variable to fix',
    );
  }
});

Deno.test('"used up" and "cannot tell" are different sentences', async () => {
  // They are different facts. One is fixed by raising a number and the other
  // by the database coming back, and a single message would send somebody to
  // the wrong one of the two.
  const spentOut = new FakeLedger();
  spentOut.spent = CEILING;
  const exhausted = await new Budget(spentOut.rpc, CEILING).reserve('extract');

  const unreadable = new FakeLedger();
  unreadable.breaks = 'throws';
  const unknown = await new Budget(unreadable.rpc, CEILING).reserve('extract');

  assert(!exhausted.allowed && !unknown.allowed);
  assertEquals(exhausted.status, 429, 'an exhausted budget is not retryable');
  assertEquals(unknown.status, 503, 'an unreadable one is worth retrying');
  assertStringIncludes(exhausted.error, 'used up');
  assert(
    exhausted.error !== unknown.error,
    'both refusals said the same thing',
  );
  // Whoever reads this is mid-import and wondering what else just broke.
  assertStringIncludes(unknown.error.toLowerCase(), 'logging');
});

Deno.test('what is already reserved counts against the ceiling', async () => {
  // The concurrency hole: `checkBudget` was a pure read, so twenty requests
  // arriving together all saw the same pre-call total and all proceeded. The
  // ledger is the only thing that can serialise them.
  const ledger = new FakeLedger();
  ledger.spent = 24;
  const budget = new Budget(ledger.rpc, CEILING);

  const decisions = await Promise.all(
    Array.from({ length: 20 }, () => budget.reserve('extract')),
  );
  const allowed = decisions.filter((d) => d.allowed).length;

  assert(allowed < 20, 'all twenty were let through on one stale read');
  // Six, exactly: $1 of headroom at $0.1694 a call, and the seventh is the
  // one that finds the ceiling already committed.
  assertEquals(allowed, Math.ceil(1 / reserveUsd('extract')));
  assert(
    ledger.spent + ledger.reserved >= CEILING,
    'the reservations were not what stopped it',
  );
});

Deno.test('a reservation nobody settles expires rather than blocking', async () => {
  // An isolate that dies mid-call takes its reservation with it. Without an
  // expiry that money is committed until the month turns over, and the
  // guardrail becomes the outage.
  const ledger = new FakeLedger();
  ledger.spent = 24;
  const budget = new Budget(ledger.rpc, CEILING);

  while ((await budget.reserve('extract')).allowed) { /* fill the ceiling */ }
  assertEquals(ledger.outstanding > 0, true);

  ledger.clock += RESERVATION_TTL_SECONDS + 1;
  assertEquals(ledger.outstanding, 0, 'nothing expired');
  assertEquals((await budget.reserve('extract')).allowed, true);
});

Deno.test('the expiry is longer than a call can possibly take', () => {
  // `ask` abandons its request at 90 seconds, so anything older than that is
  // an isolate that is not coming back. Five minutes leaves room for the URL
  // fetch in front of it and is still short enough to forgive itself.
  assert(
    RESERVATION_TTL_SECONDS >= 300,
    'a reservation that expires under load reserves nothing',
  );
});

Deno.test('settling clears the reservation and counts what it cost', async () => {
  const ledger = new FakeLedger();
  const budget = new Budget(ledger.rpc, CEILING);

  const decision = await budget.reserve('menu');
  assert(decision.allowed);
  assertEquals(ledger.outstanding, 1);

  const usage = { input_tokens: 100_000, output_tokens: 8_000 };
  const report = await budget.settle(decision.ticket, usage);

  assertEquals(ledger.outstanding, 0, 'the reservation outlived the call');
  assertEquals(ledger.spent, costOf(usage));
  assertEquals(report?.spent_usd, Number(costOf(usage).toFixed(4)));
});

Deno.test('a billed answer nobody could read is still counted', async () => {
  // The third hole: `ask` throws at "nothing readable" and at max_tokens,
  // both of which are *after* a 200 that carried a usage block. Everything
  // downstream of the throw — including the recording — never ran, so the
  // most expensive shape of call was the one that went unbilled.
  const ledger = new FakeLedger();
  const budget = new Budget(ledger.rpc, CEILING);

  const decision = await budget.reserve('menu');
  assert(decision.allowed);

  const usage = { input_tokens: 200_000, output_tokens: 16_000 };
  await budget.settleOrRelease(
    decision.ticket,
    new BilledFailure('That was too long to read in one go.', usage),
  );

  assertEquals(ledger.spent, costOf(usage));
  assertEquals(ledger.outstanding, 0);
});

Deno.test('and a call that never reached the model is released', async () => {
  // A 429 from Anthropic costs nothing. Holding its reservation for five
  // minutes would make somebody else's import wait for money that was never
  // spent.
  const ledger = new FakeLedger();
  const budget = new Budget(ledger.rpc, CEILING);

  const decision = await budget.reserve('extract');
  assert(decision.allowed);
  await budget.settleOrRelease(decision.ticket, new Error('Claude returned 429'));

  assertEquals(ledger.spent, 0);
  assertEquals(ledger.outstanding, 0, 'the reservation was left standing');
});

Deno.test('a ledger that fails on the way out does not lose the recipe', async () => {
  // By the time the answer is in hand the money is spent whatever the ledger
  // says. Failing the request here would throw away a recipe the user has
  // already paid for, and the reservation expires on its own.
  const ledger = new FakeLedger();
  const budget = new Budget(ledger.rpc, CEILING);
  const decision = await budget.reserve('extract');
  assert(decision.allowed);

  ledger.breaks = 'throws';
  const report = await budget.settle(decision.ticket, { input_tokens: 10 });

  assertEquals(report, null);
});

Deno.test('an icon still yields at half the ceiling', async () => {
  // Unchanged, and pinned so it stays that way: a decorative call stops at
  // half, and the import it might otherwise have starved carries on.
  const ledger = new FakeLedger();
  ledger.spent = CEILING * ICON_CEILING_FRACTION;
  const budget = new Budget(ledger.rpc, CEILING);

  const icon = await budget.reserve('icon');
  assertEquals(icon.allowed, false);
  assert(!icon.allowed && icon.status === 429);
  assertStringIncludes(icon.error, 'Recipe icons are paused');
  assertStringIncludes(icon.error, '50%');

  assertEquals((await budget.reserve('extract')).allowed, true);
});

Deno.test('and below half it is drawn', async () => {
  const ledger = new FakeLedger();
  ledger.spent = CEILING * ICON_CEILING_FRACTION - 0.01;
  assertEquals(
    (await new Budget(ledger.rpc, CEILING).reserve('icon')).allowed,
    true,
  );
});

Deno.test('an icon past the whole ceiling says the budget is used up', async () => {
  // The order the old code checked in, kept: past 100% the honest sentence is
  // that there is no budget left, not that pictures are paused until next
  // month.
  const ledger = new FakeLedger();
  ledger.spent = CEILING;
  const icon = await new Budget(ledger.rpc, CEILING).reserve('icon');

  assert(!icon.allowed);
  assertStringIncludes(icon.error, 'used up');
});

Deno.test('the warning still starts at three quarters', async () => {
  // Same threshold, same quiet line in the app.
  const ledger = new FakeLedger();
  const budget = new Budget(ledger.rpc, CEILING);
  const decision = await budget.reserve('extract');
  assert(decision.allowed);
  assertEquals(decision.report.warn, false);

  ledger.spent = CEILING * WARN_AT;
  const report = await budget.settle(decision.ticket, null);
  assertEquals(report?.warn, true);
  assertEquals(report?.fraction, WARN_AT);
});

Deno.test('every mode reserves something, and no more than it could spend', async (t) => {
  // A reservation of nothing is a read-then-call with extra steps; one the
  // size of the ceiling would refuse the second concurrent import of the
  // month. Both ends are worth pinning.
  const modes: Mode[] = [
    'extract',
    'generate',
    'label',
    'shopping',
    'menu',
    'icon',
  ];
  for (const mode of modes) {
    await t.step(mode, () => {
      const reserved = reserveUsd(mode);
      assert(reserved > 0, `${mode} reserves nothing`);
      assert(reserved < CEILING / 10, `${mode} reserves ${reserved}, too much`);
    });
  }
});

Deno.test('the reservation is taken before the model is called', async () => {
  // Not an implementation detail: it is the whole fix. `reserve` must have
  // written to the ledger by the time it answers, or two requests can still
  // pass the same total.
  const ledger = new FakeLedger();
  const decision = await new Budget(ledger.rpc, CEILING).reserve('extract');

  assert(decision.allowed);
  assertEquals(ledger.calls[0].name, 'reserve_ai_spend');
  assertEquals(ledger.reserved, reserveUsd('extract'));
  assertEquals(ledger.calls[0].args.p_ttl_seconds, RESERVATION_TTL_SECONDS);
});
