# Hearth quantity units — P-HEARTH-QUANTITY-001 v1

Status: proposed for human approval. Discovery and baseline only; no product implementation authorized or started. Mode: feature/bug remediation in the existing Hearth app.

## Outcome

Packaged ingredients retain useful ounce quantities across Food, Recipes, cook-along, Shopping and export review. Foods measured by weight still aggregate exactly and can display pounds. Quantity arithmetic and unit presentation become separate concerns.

| Input/context | Recipe total | Shopping, with confirmed pack size |
|---|---|---|
| 28 oz canned tomatoes, doubled | 56 oz | 2 × 28 oz |
| 12 oz frozen corn, doubled | 24 oz | 2 × 12 oz |
| 56 oz canned beans, 28 oz packs | 56 oz | 2 × 28 oz |
| 14.5 oz can, doubled | 29 oz | 2 × 14.5 oz |
| 1 lb beef + 8 oz beef | 1.5 lb | 1.5 lb when no fixed pack is recorded |
| Beef explicitly set to Weight, 12 oz + 12 oz | 1.5 lb | 1.5 lb when no fixed pack is recorded |
| Need 40 oz tomatoes; 28 oz packs | 40 oz | 2 × 28 oz, needs 40 oz |
| Unknown food, 12 oz + 12 oz | 24 oz | 24 oz; no invented pack count |

The user's optional presentation question remains unanswered at plan publication. Recommended behavior above is a proposal, not approval. All-ounce beef without a package or explicit Weight setting remains ounces under the conservative default. A quantity alone cannot establish how a food is sold; food names are not a reliable classifier.

## Exact requirements

R1 — Keep canonical arithmetic. Continue storing mass in grams, volume in ml and counts in existing count buckets. Sum and subtract before formatting. Never round canonical quantities, macros, source contributions or pantry amounts. Preserve density safeguards, ingredient identity, optional exclusions, frozen log history and household permissions.

R2 — Shared presentation policy. Add a pure domain resolver used by every affected surface. Separate a quantity's original/authored unit from its current presentation choice. Scaling must not replace a mass quantity's original unit with a promoted unit. Aggregation must inspect all source hints, choosing deterministically rather than inheriting whichever ingredient happened to occur first.

R3 — Imperial mass policy, in this precedence order:

1. Explicit food setting: Ounces pins mass to oz; Weight uses the existing oz/lb ladder. Automatic follows the rules below. Actual package-size labels and serving labels always retain their documented units, even with Weight selected.
2. A known mass pack with authored oz or lb uses that unit for ingredient totals. Metric-only package information must not invent an imperial package size; an imperial ingredient total uses source hints below, while the package label remains metric.
3. Explicit mass-package syntax in recipe raw text (recognized by the existing parser) preserves its unit in ingredient totals. Use this only as display evidence, without reparsing or replacing current canonical quantities. A recipe's mentioned package is not proof of the product the shopper buys; shopping counts require Food.packSize.
4. Otherwise, all source mass hints in oz retain oz. A pound source among mixed oz/lb sources permits the existing weight ladder. With no imperial source hints, use the user's current unit system and existing ladder. A mixed group containing explicit ounce-package evidence stays oz even if another source uses pounds. Pure volume behavior stays as today.

Automatic does not infer sold-by-weight from a word such as beef: beef jerky and canned beef are counterexamples. Beef already entered in pounds keeps combining into pounds; a reusable Weight override handles foods consistently entered in ounces that the user prefers to total in pounds. There is no AI call, network lookup or hardcoded food-name category list.

R4 — Food-level control. Add an optional household food setting, `mass_display_mode`, values `automatic`, `ounces`, `weight`; default `automatic`. Place an accessible select under the existing food quantity/package controls, labeled “Weight display”, options “Automatic”, “Ounces”, “Weight (oz/lb)”, with helper “Used for recipe and shopping totals. Package labels keep their own units.” This is a display preference, not a package-size or nutrition editor. Setting changes update matched rows on the next normal reactive rebuild, without rewriting recipes. Preserve it through draft recovery, duplicate/merge, local persistence, sync and server round trips. Source refreshes must not clear an explicit user override. Do not add a control to each recipe row.

R5 — All paths agree. Apply resolved context to recipe grouped and consolidated lists, scaling, cook ingredient overview and step amounts; food pack edit/review and serving fallback; shopping planned/wanted/on-hand/to-buy quantities, amount-sheet summaries, contributions, rebuilds and export preview/text. Human-input editors continue reflecting the entered unit. Resolve context through existing repositories/providers, never database calls from domain/UI formatters. Package display and export use the same shared result. Existing stored shopping totals can use matched food context immediately; rebuilding from contributions must retain available source hints.

R6 — Precision and safe editors. Preserve 14.5 oz, 15.25 oz, 28 oz and similar label values rather than rounding weights >=10 to integers. For ordinary oz/lb total text, use trimmed decimals to two decimal places (maximum absolute display error 0.005 of the selected unit); a nonzero smaller than 0.01 uses enough significant digits to stay nonzero. Package/serving labels retain meaningful authored precision. Do not serialize an editable value with a rounded display formatter. Opening and saving unchanged food/package or shopping quantity must preserve original canonical value and unit; keep the original quantity when the field is unmodified. Edited values use the existing validated parser, not the formatted total.

R7 — Purchase counts remain separate. Compute ceil(max(need - onHand, 0) / confirmed packSize) with existing numeric-tail safeguards, in canonical units. Recipe amounts never round up to packs. Show actual need whenever purchasing introduces a meaningful excess; companion quantities use a consistent unit. Zero need does not demand a pack. Missing, nonpositive or dimensionally incompatible pack size falls back to a quantity without guessed count. Package-count labels stay in actual package units for metric and imperial users.

R8 — Compatibility. No bulk rewriting of existing food/recipe amounts. Existing rounded/saved package corruption cannot be safely reversed by guessing; users can correct the package field. Existing records with unknown original hints use available pack/source evidence, then the conservative fallback. Metric recipe/need totals continue honoring metric preference; imperial override choices do not force metric readers to ounces. Export behavior remains local review before external handoff. No live cart mutation is part of this work.

## Data and migration contract

Add only `foods.mass_display_mode` with a non-null `automatic` default and three-value server constraint. Drift is currently version 28: the implementation must inspect the then-current version and add exactly the next migration, never assume 29 if another feature landed. Update Food constructors/copy/equality as applicable, food draft serialization, mappers, sync payloads, repository merge semantics and current upsert_food function in a NEW SQL migration. Preserve RLS/auth checks and all existing function behavior.

For older clients whose upsert payload omits this key, preserve the existing stored setting on update; default only on insert. An absent server key from an older environment reads as automatic. Unknown future enum values read as automatic in the client but are not silently written over known explicit settings during unrelated edits. Existing global-food edit permissions remain unchanged; use the existing household edit/copy path.

Generate Drift code and schema history using repository commands, replay every historical upgrade, and test a real local database plus hosted deployment verification before calling release complete. Deploy the additive server migration before the new client. A client rollback leaves the additive column; no destructive down migration. No new table or RLS trust boundary.

## UI and state coverage

Use existing theme, select, spacing and semantic patterns. No screen redesign. Wrap long package/need labels at current mobile and desktop widths; no clipping at 200% text scale. Test light/dark, edit cancellation, unchanged save, explicit override/reset-to-Automatic, offline edit/restart, normal sync refresh and stale/missing food lookup. A loading or missing food uses conservative source-unit fallback, then updates when metadata arrives; it must not hide quantity text. No new modal error for missing classification. No live announcements beyond existing semantics; spoken amounts must match visible units.

## Acceptance and milestones

A1 / R1–R3: table examples plus 16 oz boundary, half/double scaling, aggregate permutations, mixed oz/lb, mass+volume with/without density, incompatible count units, zero and signed quantities. Canonical equality within 1e-9 relative error (absolute floor 1e-9 g); no accumulated rounding. Triple tsp still promotes to tbsp.

A2 / R4,R8: override save/reopen, draft recovery, duplicate/merge, sync push/pull; absent/invalid setting fallback; old-client omitted-key upsert preserves explicit setting; all historical Drift migrations and RLS guards pass. Food source refresh preserves override.

A3 / R5–R7: widget fixtures on all three main areas plus cook-along and export review show the table results. Pack shortage/subtraction and contribution rebuild match canonical totals. 14.5 oz and unchanged 28 oz pack round-trip unchanged. Any rounded original value stays as stored until explicitly corrected. Export preview exactly matches the shopping decision.

A4 / R5,R8: actual Flutter captures of food control/package field, grouped/consolidated/scaled recipes, cook amounts and shopping primary/detail/export quantities; narrow phone and desktop, light/dark, 200% text. Independent code/security and image-backed UX review, then Astra acceptance. Native macOS synthetic-data walkthrough; simulator/device evidence when available. Mac tests alone do not prove Windows/iOS runtime correctness; record platform coverage precisely.

M1: domain policy and failing-then-passing regressions accepted. M2: schema/sync/editor compatibility accepted. M3: all surfaces, deterministic gates and independent reviews accepted. M4: reviewed green PR and deployment evidence only to the destinations approved below.

## Scope, tools and delivery

Use existing Flutter/Dart/Riverpod/Drift/Supabase/GitHub tooling. Astra plans/integrates; subscription-backed Claude implements and independently reviews through the installed controller's supported foreground workflow. No new paid tools, dependency, background supervisor or remote model API. See EXECUTION.md for capabilities and task gates.

Proposed implementation delivery is a feature branch and reviewed green PR to gradybre/hearth, with an additive linked Supabase migration after local verification under repository rules. No device reinstall, app distribution change or data deletion. App merge/install is not included in this planning-only request; any subsequent approval may extend release authority. Repo PR declarations remain truthful. Before execution, revalidate linked target, existing ship/merge instructions and any explicit human release authorization; do not inherit a different feature's approval.

This plan also amends spec §4/§5.2/§5.5/§5.7 to describe the accepted unit policy and reconcile §5.7's stale recipe-units-only/purchase-mapping-deferred sentence with the existing package-display feature. It does not expand purchase integration capabilities.

Definition of done for this turn: reproducible findings, a concrete versioned proposal and execution package ready for approval. Definition of done for implementation: all A1–A4 satisfied, full static/test gates pass, schema applied/verified, independent reviews resolved and PR CI green; report any unfulfilled release/platform gate explicitly.
