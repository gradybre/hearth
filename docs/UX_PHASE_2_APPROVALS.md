# Phase 2 UX decisions

This is the decision queue for [the UX review](../HEARTH_UX_REVIEW.md), separate
from the [implementation record](UX_PHASE_2_PROGRESS.md). Recommendations describe
the review baseline; completed work must be reconciled before asking again.

## How to keep the approval conversation moving

- Every proposed group gets a self-contained `request_user_input_async` card:
  the user benefit, concrete behavior/defaults, material tradeoffs, approximate
  size, AI cost, and whether it can run concurrently or must queue.
- Always include **Approve Group N / Modify Group N / Skip Group N** buttons.
  Saying that a decision is pending in chat is not a substitute for the card.
- As answers arrive, record them, start approved work when ownership permits,
  and present the next prepared cards in the same turn. Do not wait for builds,
  review, CI or merging before offering independent decisions.
- Work through the entire remaining queue. Use small batches to keep the
  decision burden manageable; Groups 11–16 were re-presented/presented together
  to repair the missing-card problem. Thereafter refill to roughly three
  unanswered cards at a time. After an answer, keep the next undecided group
  visible as an actual card (re-present the next pending card if needed),
  rather than mentioning it only in a progress message.
- Approval covers the exact card, not every recommendation in its feature
  area. A requested modification needs a revised concrete proposal; a skip is
  a recorded answer, not a deletion from the review. Silence is not approval.
- Separate **decision** (unasked / awaiting answer / approved / modified /
  skipped / future-only) from **delivery** (not started / queued / building /
  review / merged). File conflicts affect delivery order, not whether the user
  can decide now. Future-only approval does not authorize present implementation.
- Shared specification, providers, schema, migrations, export integration and
  test registries remain coordinator-owned under ORCHESTRATION.md.

## Already decided and delivered

Groups 1–10 are approved and merged. Do not ask for them again. Their bounded
scope is recorded in UX_PHASE_2_PROGRESS.md. In particular:

- Group 9: [PR #124](https://github.com/gradybre/hearth/pull/124), merged
  2026-10-01 as `57cd417`; all CI passed on reviewed candidate `460e85e`.
- Group 10: [PR #125](https://github.com/gradybre/hearth/pull/125), merged
  2026-10-01 as `f478498`; all CI passed on reviewed candidate `af6843e`.
  The final main source exactly matches that combined candidate. Combined
  checks: 4,655 UTC tests, 116 New York checks, 157 render checks. Native device
  acceptance has not been performed.

## Presented decisions

| Group | Review coverage | Decision | Delivery / sequence |
|---|---|---|---|
| 11 — Exact log/unlog Undo | UX-051 remainder | Approved 2026-10-01: “Approve Group 11” | Building in `codex/exact-log-undo`; dedicated data/UI owner |
| 12 — Readable Today and Week | UX-087 | Awaiting answer; card re-presented after Group 11 approval | Queue shared Day/Week edits after Group 11 if both approved |
| 13 — Readable food-data archive | UX-084 | Awaiting answer; card sent 2026-10-01 | Can run alongside Plan work; coordinator integrates shared export/provider changes |
| 14 — Recipe nutrition calculation receipt | UX-015; remaining UX-010 wording | Awaiting answer; card sent 2026-10-01 | Receipt can start independently; shared editor/logging changes sequenced |
| 15 — Repeat and customize restaurant orders | UX-029, UX-033 | Awaiting answer; card sent 2026-10-01 | Restaurant work independent; logging integration sequenced |
| 16 — Resolve missing ingredient matches in place | UX-014; narrow UX-028 search context | Awaiting answer; card sent 2026-10-01 | Match-review work independent; food picker/editor ownership sequenced |

### Group 11 — Exact log/unlog Undo

Keep the one-tap check, followed by Undo. Restore the prior logged state and
its exact original portion, name and nutrition. If the meal has changed again,
explain why the earlier action cannot be undone instead of overwriting newer
work. Uses the now-merged frozen-portion model. No AI cost. An exact restoration
and stale-change guard are required; simply toggling again is not equivalent.

### Group 12 — Readable Today and Week

On narrow screens or at large type, place the date on its own line, remove
redundant headings and use a compact Day/Week selector. Retain full-size text
and date actions while bringing a meaningful meal or nutrition summary into
the first viewport. Small change; no AI. This is layout, not a new meal-week
view or household plan.

### Group 13 — Readable food-data archive

Add a ZIP with the existing versioned JSON, spreadsheet-friendly logs, targets
and foods, readable recipes and a contents guide. Offer optional recipe photos
and explicitly report missing/unavailable files. Preserve frozen nutrition and
portions, authored units and date/time context. Include the current person's
private data and the shared household data; exclude the partner's private diary.
Retain a review of exactly what will be shared and keep standalone JSON export.
Medium-to-large change; no AI. Import/restore is a separate decision.

### Group 14 — Recipe nutrition calculation receipt

Open a readable breakdown from recipe nutrition: ingredient amount, matched
food and serving basis, contribution, and explicit missing or excluded facts.
Reuse Per serving / Whole dish language in the editor and logging review.
Group 3's existing detail toggle remains completed scope. This receipt does
not silently change matches or old logs. Medium change; no AI.

### Group 15 — Repeat and customize restaurant orders

Saved usual orders offer Log this, Customize and Details. Preserve the selected
day/meal, review the portion, then log. Show base order, additions/removals and
their nutrition changes; Reset returns to the base. The saved usual remains
unchanged unless the person explicitly saves a new variation. Unavailable
components require review. Medium change; no AI.

### Group 16 — Resolve missing ingredient matches in place

Keep the authored ingredient and amount visible while searching, scanning,
entering nutrition or skipping. Return to the same review with earlier choices
intact, then apply the reviewed matches together. Making a match the household
usual remains explicit. Medium change. No new AI behavior: the existing Read
label action retains its normal cost when deliberately selected.

## Remaining coverage

The complete preparation ledger covers UX-001–UX-097 and FUT-001–FUT-007.
Candidate packets are preparation only, not approval or implementation.
Final group numbers are assigned when the coordinator presents each packet.
The following packet files retain concrete flows, defaults, effort, AI cost,
prerequisites, scope boundaries, and current-source references:

- [Recipes, cooking, foods, restaurants and AI](ux_approval_packets/recipes_foods.md):
  all 38 IDs UX-001–UX-038, including remaining parts of already-delivered groups.
- [Planning, logging, shopping and first use](ux_approval_packets/planning_shopping.md):
  all 36 IDs UX-039–UX-074, with completed work excluded from new decisions.
- [Accounts, navigation, ownership, House and future modules](ux_approval_packets/account_data_house.md):
  UX-075–UX-097 and FUT-001–FUT-007.

Next after presented Groups 12–16: meal-readable Week (`week-meals`), reviewed
Walmart package counts (`walmart-quantities`), and nutrient contributors
(`nutrient-receipt`), unless a user modification changes ordering. Present each
with its own numbered decision card. Later packets may be grouped where the
user-facing decision is truly one coherent change; keep every residual scope
mapped and do not silently authorize deferred features.
