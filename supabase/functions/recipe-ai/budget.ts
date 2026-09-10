/// What this month's AI calls have cost, and whether another one may be made
/// (spec §3, §8.1).
///
/// Its own file for the same reason `url_guard.ts` is: the interesting half is
/// a decision — may this call go ahead, and what does the app tell somebody
/// when it may not — and a decision can be exercised without a database, a
/// network, or a single real dollar. The half that has to reach the ledger
/// takes its caller as an argument.
///
/// The shape is reserve-then-settle rather than read-then-call, and that is
/// the whole point of the rewrite. A read is a fact about the past: N requests
/// arriving together all read the same total, all find room under the ceiling,
/// and all spend it. A reservation is a fact the next request can see, so the
/// second of twenty concurrent imports is refused by the first one's money
/// rather than by hindsight.
///
/// And a ledger that cannot be read now refuses instead of waving the call
/// through. It used not to: `callRpc` answered null for a missing env var, a
/// non-OK response and any throw alike, so an unreadable counter became a
/// month that had cost nothing and every paid mode carried on. A guardrail
/// that disappears exactly when the database is unwell is not a guardrail —
/// and the thing it is guarding against, a dev-time retry loop, is at its most
/// expensive precisely then. Import, generation, menu and label reading are
/// refused while the counter is unreadable; logging, cooking and everything
/// manual never reach this function and are untouched.

/// USD per million tokens for the model `index.ts` calls. Change both together
/// with MODEL.
///
/// Approximate on purpose: the ceiling is a guardrail, not an invoice, and
/// Anthropic's own billing limit is the number that actually binds. Being a
/// little pessimistic here is the safe direction to be wrong in.
export const INPUT_USD_PER_MTOK = 3;
export const OUTPUT_USD_PER_MTOK = 15;

/// Above this share of the ceiling, answers carry a warning; at or above 1,
/// they are refused (spec §3, §8.1).
export const WARN_AT = 0.75;

/// Where a *decorative* call stops, well before the useful ones do.
///
/// A recipe icon is the only thing this function produces that nobody needs.
/// Giving it the same ceiling as import would mean a month of pictures could
/// be the reason a recipe import is refused at 90% of the budget — the
/// picture having spent the money the import needed. So it yields first, and
/// by a wide margin: half the ceiling still buys hundreds of sketches, and it
/// leaves the other half for the features the app is actually for.
export const ICON_CEILING_FRACTION = 0.5;

/// The default when AI_MONTHLY_CEILING_USD is unset.
///
/// A number rather than "unlimited", deliberately. §8 names a dev-time retry
/// loop as the real risk, and a loop that runs into an unset variable is a
/// loop with no ceiling at all — which is the failure this exists to stop.
export const DEFAULT_CEILING_USD = 25;

/// How long a reservation holds money it has not spent.
///
/// A reservation is settled or released by the same request that took it, so
/// the only ones that reach this age belong to an isolate that died mid-call
/// — a deploy, an eviction, a hard timeout. Without an expiry that money is
/// committed until the month turns over, and one crash would quietly halve
/// the budget for four weeks.
///
/// Five minutes, because `ask` abandons its request to Claude at 90 seconds
/// and the page fetch in front of it has its own deadline, so nothing honest
/// is still running at three. Nothing sweeps on a timer: the next
/// `reserve_ai_spend` deletes what has expired before it counts, which is one
/// statement in a function that already holds the lock and needs no cron, no
/// scheduler and nothing to notice it has stopped.
export const RESERVATION_TTL_SECONDS = 300;

/// The modes that spend money. One name per branch in `index.ts`.
export type Mode =
  | 'extract'
  | 'generate'
  | 'label'
  | 'shopping'
  | 'menu'
  | 'icon';

/// The most a mode may write, and so the most its output can cost.
///
/// A menu is the one mode whose answer is as long as its input: a six-page
/// guide is 150 rows, and at 4,096 tokens the transcription stops around row
/// 60 — a short list that looks complete. The others answer with one recipe,
/// one label, one basket. An icon is a few hundred bytes of markup, so a small
/// ceiling is the cheapest guard against a model that decides to trace a
/// photograph.
///
/// Here rather than at the call site because the reservation is computed from
/// it: two copies of this number would drift, and the copy that drifted would
/// be the one holding the ceiling up.
export function maxOutputTokens(mode: Mode): number {
  return mode === 'menu' ? 16_000 : mode === 'icon' ? 1500 : 4096;
}

/// The model's context window, and so the most any one call can be billed for
/// however much the caller sends it.
///
/// The real bound on `extract`. Past this Anthropic answers 400 and charges
/// nothing, so reserving against the raw slice below would hold four times
/// what a month could actually lose.
const MAX_CONTEXT_TOKENS = 200_000;

/// What a mode's input could weigh, in tokens.
///
/// Pessimistic where it can be. An image costs about 1,600 tokens whatever its
/// size, because anything larger is downscaled before it is counted, so ten
/// images have a real ceiling. Text is counted at three characters per token
/// rather than the usual four, against the caps `index.ts` already slices to:
/// 60,000 characters of fetched page, 20,000 of recipe, 20,000 of list — and,
/// on the extract path, `MAX_URL_BYTES` of shared text.
///
/// That last one is why extract is capped rather than summed. A recipe shared
/// as words — the Instagram creator who answers "recipe" with a DM — is sliced
/// to two megabytes, some 700,000 tokens, and this function used to return
/// 36,000 for that mode: seventeen cents claimed against a call that could
/// bill most of a dollar. The context window is the honest bound, because it
/// is where the charging stops.
///
/// Generation and shopping are the honest exceptions: their conversations are
/// capped in number of turns and not in length, so those two figures are a
/// working estimate rather than a bound. Under-reserving costs at most one
/// call's overshoot — the next request sees the settled total — while
/// over-reserving would refuse a second concurrent import for money nobody
/// was going to spend.
function maxInputTokens(mode: Mode): number {
  const perImage = 1600;
  const maxImages = 10;
  const perChar = 1 / 3;
  // `MAX_URL_BYTES` in index.ts, which slices `body.text` by character.
  const maxSharedTextChars = 2 * 1024 * 1024;
  switch (mode) {
    case 'extract':
      return Math.min(
        maxImages * perImage + (60_000 + maxSharedTextChars) * perChar,
        MAX_CONTEXT_TOKENS,
      );
    case 'menu':
    case 'label':
      return maxImages * perImage;
    case 'generate':
    case 'shopping':
      return 60_000 * perChar;
    case 'icon':
      // A title sliced to 200 characters, and the prompt around it.
      return 1000;
  }
}

/// What to hold against the ceiling while a call of this mode is in flight.
export function reserveUsd(mode: Mode): number {
  return Number(
    ((maxInputTokens(mode) / 1e6) * INPUT_USD_PER_MTOK +
      (maxOutputTokens(mode) / 1e6) * OUTPUT_USD_PER_MTOK).toFixed(6),
  );
}

/// Calls a Postgres function, and throws when it cannot.
///
/// Throwing is the contract, not an accident of the implementation: null is an
/// answer about money and an unreachable database is not. Conflating the two
/// is the defect this file was rewritten for.
export type Rpc = (
  name: string,
  args: Record<string, unknown>,
  // deno-lint-ignore no-explicit-any
) => Promise<any>;

/// What a call's tokens came to, as Anthropic reports them.
export interface TokenUsage {
  input_tokens?: number;
  output_tokens?: number;
}

/// The month's standing, as the app shows it.
///
/// Committed spending only — what reservations are holding is the guard's
/// business and would read, on a screen, as money the household has not
/// actually spent.
export interface UsageReport {
  spent_usd: number;
  ceiling_usd: number;
  fraction: number;
  warn: boolean;
}

/// A claim on the budget, held until the call it paid for is done.
export interface Ticket {
  readonly id: string;
}

/// Whether this call may go ahead, and what to say if not.
export type Decision =
  | { allowed: true; ticket: Ticket; report: UsageReport }
  | {
    allowed: false;
    /// 429 for a budget that is spent — asking again cannot help. 503 for one
    /// that cannot be read, which is transient and worth a retry; the app
    /// offers one above 500 and not below it.
    status: 429 | 503;
    error: string;
    report: UsageReport | null;
  };

/// A Claude call that was billed and still produced nothing the app can use.
///
/// Its own error because it needs its own settlement. A 200 from Anthropic is
/// charged for whether or not the tool call inside it could be parsed, and the
/// two branches that throw on one — "nothing readable" and a `max_tokens`
/// truncation — sit *after* the usage block arrives. Everything downstream of
/// the throw used never to run, so the most expensive shape of call in the
/// whole function was the one that went uncounted.
export class BilledFailure extends Error {
  constructor(message: string, readonly usage: TokenUsage | null) {
    super(message);
    this.name = 'BilledFailure';
  }
}

/// The ceiling in force, from the environment.
export function ceilingUsd(env: (name: string) => string | undefined): number {
  return Number(env('AI_MONTHLY_CEILING_USD') ?? DEFAULT_CEILING_USD);
}

/// What a call's tokens cost, in dollars.
export function costOf(usage: TokenUsage | null): number {
  const input = usage?.input_tokens ?? 0;
  const output = usage?.output_tokens ?? 0;
  return (input / 1e6) * INPUT_USD_PER_MTOK +
    (output / 1e6) * OUTPUT_USD_PER_MTOK;
}

/// Said when the ledger cannot be read.
///
/// Deliberately not the "used up" sentence: they are different facts, fixed in
/// different places, and one message for both would send somebody to raise a
/// ceiling that was never the problem. It names what still works, because
/// whoever reads this is mid-import and wondering what else has broken.
const UNKNOWN_MESSAGE =
  "Hearth can't check this month's AI spending at the moment, so it won't " +
  'spend any more until it can. Logging, cooking and everything you type ' +
  'yourself are unaffected. Try the import again in a few minutes.';

/// The ledger, and the decisions taken against it.
export class Budget {
  constructor(private readonly rpc: Rpc, private readonly ceiling: number) {}

  /// Claims room for one call, before the call is made.
  ///
  /// The claim is what makes this safe under concurrency: it is written inside
  /// the same statement that checks the ceiling, under the month's row lock,
  /// so the next request counts it whether or not the first has finished.
  async reserve(mode: Mode): Promise<Decision> {
    if (!Number.isFinite(this.ceiling) || this.ceiling <= 0) {
      // A ceiling of NaN — AI_MONTHLY_CEILING_USD=twenty — used to permit
      // everything, because NaN >= 1 is false. A typo is not a budget.
      return {
        allowed: false,
        status: 503,
        error:
          'The AI budget is not set to a number Hearth can use, so nothing ' +
          'will be spent. Set AI_MONTHLY_CEILING_USD to a dollar amount.',
        report: null,
      };
    }

    // An icon is stopped by the same arithmetic as everything else, one
    // ceiling lower. Passing the lower ceiling down rather than checking the
    // fraction up here keeps the decorative limit inside the lock too — two
    // concurrent sketches at 49% would otherwise both pass.
    const effective = mode === 'icon'
      ? this.ceiling * ICON_CEILING_FRACTION
      : this.ceiling;

    let row: Record<string, unknown> | null;
    try {
      row = first(
        await this.rpc('reserve_ai_spend', {
          p_amount_usd: reserveUsd(mode),
          p_mode: mode,
          p_ceiling_usd: effective,
          p_ttl_seconds: RESERVATION_TTL_SECONDS,
        }),
      );
    } catch {
      return unreadable();
    }

    const allowed = row?.allowed;
    const spent = Number(row?.spent_usd);
    const reserved = Number(row?.reserved_usd);
    if (
      typeof allowed !== 'boolean' || !Number.isFinite(spent) ||
      !Number.isFinite(reserved)
    ) {
      // A row that does not say yes or no is not a yes. Reading it as one is
      // the same failure wearing a 200.
      return unreadable();
    }

    const report = this.reportFor(spent);

    if (allowed) {
      const id = row?.reservation_id;
      // Permission without a ticket cannot be settled or released, so the
      // money would be held until it expired. Refuse rather than spend
      // something nothing can account for.
      if (typeof id !== 'string' && typeof id !== 'number') return unreadable();
      return { allowed: true, ticket: { id: String(id) }, report };
    }

    // Committed plus outstanding, which is what the ledger just refused on.
    // The displayed spend stays committed-only; this is the guard's own view.
    const fraction = (spent + reserved) / this.ceiling;
    return {
      allowed: false,
      status: 429,
      error: fraction >= 1
        // Not toFixed(2) on the ceiling: a small one rounds to "$0.00",
        // which reads as a bug rather than as a limit.
        ? `This month's AI budget is used up ($${spent.toFixed(2)} of $${
          this.ceiling
        }). Raise AI_MONTHLY_CEILING_USD to carry on.`
        : 'Recipe icons are paused until next month: they stop at ' +
          `${Math.round(ICON_CEILING_FRACTION * 100)}% of the AI budget so ` +
          'they can never be the reason an import is refused.',
      report,
    };
  }

  /// Records what a call actually cost and gives up its reservation.
  ///
  /// Never throws. By the time this runs the money is spent whatever the
  /// ledger says, and failing here would throw away a recipe the household has
  /// already paid for. A settlement that does not land leaves its reservation
  /// standing, which errs towards refusing the next call rather than towards
  /// spending — and it expires on its own within the TTL.
  async settle(
    ticket: Ticket | null,
    usage: TokenUsage | null,
  ): Promise<UsageReport | null> {
    try {
      const row = await this.rpc('settle_ai_spend', {
        p_reservation_id: ticket?.id ?? null,
        p_input_tokens: usage?.input_tokens ?? 0,
        p_output_tokens: usage?.output_tokens ?? 0,
        p_cost_usd: Number(costOf(usage).toFixed(6)),
      });
      const settled = first(row);
      const spent = Number(settled?.cost_usd);
      // The app treats a missing usage block as "no figure to show" rather
      // than as zero, so saying nothing is better than saying zero.
      return Number.isFinite(spent) ? this.reportFor(spent) : null;
    } catch {
      return null;
    }
  }

  /// Gives back money that was never spent.
  ///
  /// A 429 from Anthropic, a refused link, a photo that was too large: none of
  /// them reached the model. Holding their reservation for five minutes would
  /// make somebody else's import wait for money nobody spent.
  async release(ticket: Ticket | null): Promise<void> {
    if (!ticket) return;
    try {
      await this.rpc('release_ai_spend', { p_reservation_id: ticket.id });
    } catch {
      // It expires by itself. Failing the request over the bookkeeping would
      // replace a message about the real problem with one about this.
    }
  }

  /// What to do with a reservation when the work threw.
  ///
  /// The distinction is whether Anthropic charged for it. A 200 that carried a
  /// usage block was billed even when nothing readable came back out of it,
  /// and that is the call worth counting: it is the longest input and the
  /// fullest output the month will see.
  async settleOrRelease(ticket: Ticket | null, error: unknown): Promise<void> {
    if (error instanceof BilledFailure) {
      await this.settle(ticket, error.usage);
    } else {
      await this.release(ticket);
    }
  }

  private reportFor(spent: number): UsageReport {
    const fraction = this.ceiling > 0 ? spent / this.ceiling : 0;
    return {
      spent_usd: Number(spent.toFixed(4)),
      ceiling_usd: this.ceiling,
      fraction: Number(fraction.toFixed(4)),
      // The app shows a quiet line at 75% rather than a dialog: a warning
      // that interrupts every import is one nobody reads by the third time.
      warn: fraction >= WARN_AT,
    };
  }
}

function unreadable(): Decision {
  return { allowed: false, status: 503, error: UNKNOWN_MESSAGE, report: null };
}

/// PostgREST answers a set-returning function with an array and a scalar one
/// with the value itself. Both spellings arrive here.
function first(row: unknown): Record<string, unknown> | null {
  const value = Array.isArray(row) ? row[0] : row;
  return value && typeof value === 'object'
    ? value as Record<string, unknown>
    : null;
}
