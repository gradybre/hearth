/// What this month's AI calls have cost, and whether another one may be made
/// (spec §3, §8.1).
///
/// Its own file for the same reason `url_guard.ts` is: the interesting half is
/// a decision — may this call go ahead, and what does the app tell somebody
/// when it may not — and a decision can be exercised without a database, a
/// network, or a single real dollar. The half that has to reach the ledger
/// takes its caller as an argument.

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

/// Calls a Postgres function. Answers null when it cannot.
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
export interface UsageReport {
  spent_usd: number;
  ceiling_usd: number;
  fraction: number;
  warn: boolean;
}

/// The ceiling in force, from the environment.
export function ceilingUsd(env: (name: string) => string | undefined): number {
  return Number(env('AI_MONTHLY_CEILING_USD') ?? DEFAULT_CEILING_USD);
}

/// What the month has cost, and whether that is already too much.
///
/// A failure to read the counter is treated as "carry on": the ceiling is a
/// guardrail, and a database hiccup that silently disabled recipe import
/// would be a worse outcome than a call that should not have been made.
/// Anthropic's own billing limit is still underneath this.
export async function checkBudget(
  rpc: Rpc,
  ceiling: number,
): Promise<
  {
    exhausted: boolean;
    fraction: number;
    spent: number;
    ceiling: number;
    report: UsageReport;
  }
> {
  const spent = await rpc('ai_usage_this_month', {}) ?? 0;
  const fraction = ceiling > 0 ? Number(spent) / ceiling : 0;

  return {
    exhausted: fraction >= 1,
    // Carried out rather than left inside `report`: a caller deciding whether
    // *this* mode may spend needs the number, not a display object.
    fraction,
    spent: Number(spent),
    ceiling,
    report: {
      spent_usd: Number(Number(spent).toFixed(4)),
      ceiling_usd: ceiling,
      fraction: Number(fraction.toFixed(4)),
      // The app shows a quiet line at 75% rather than a dialog: a warning
      // that interrupts every import is one nobody reads by the third time.
      warn: fraction >= WARN_AT,
    },
  };
}

/// What a call's tokens cost, in dollars.
export function costOf(usage: TokenUsage | null): number {
  const input = usage?.input_tokens ?? 0;
  const output = usage?.output_tokens ?? 0;
  return (input / 1e6) * INPUT_USD_PER_MTOK +
    (output / 1e6) * OUTPUT_USD_PER_MTOK;
}

/// Adds what a call cost and returns the month's totals for the app to show.
export async function recordUsage(
  rpc: Rpc,
  ceiling: number,
  usage: TokenUsage | null,
): Promise<UsageReport> {
  const input = usage?.input_tokens ?? 0;
  const output = usage?.output_tokens ?? 0;

  const row = await rpc('record_ai_usage', {
    p_input_tokens: input,
    p_output_tokens: output,
    p_cost_usd: Number(costOf(usage).toFixed(6)),
  });

  const spent = Number(row?.cost_usd ?? 0);
  const fraction = ceiling > 0 ? spent / ceiling : 0;

  return {
    spent_usd: Number(spent.toFixed(4)),
    ceiling_usd: ceiling,
    fraction: Number(fraction.toFixed(4)),
    warn: fraction >= WARN_AT,
  };
}
