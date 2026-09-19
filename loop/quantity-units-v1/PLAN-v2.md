# Hearth quantity units — P-HEARTH-QUANTITY-001 v2

Status: revised proposal for human approval. Supersedes PLAN.md (v1); preserve v1 as history. User requested the package/nutrition extension; this is scope steering, not approval to implement the whole plan. Discovery and baseline only; no product implementation authorized or started. Mode: feature/bug remediation in the existing Hearth app.

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

R1 — Keep canonical arithmetic. Continue storing mass in grams, volume in ml and counts in existing count buckets. Sum and subtract before formatting. Never round canonical quantities, macros, source contributions or pantry amounts. R9–R13 add a reviewed conversion basis for previously unconvertible amounts; they preserve existing correctly resolved nutrition calculations. Preserve density safeguards, ingredient identity, optional exclusions, frozen log history and household permissions.

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

Add `foods.mass_display_mode` with a non-null `automatic` default and three-value server constraint. Drift is currently version 28: the implementation must inspect the then-current version and add exactly the next migration, never assume 29 if another feature landed. Update Food constructors/copy/equality as applicable, food draft serialization, mappers, sync payloads, repository merge semantics and current upsert_food function in a NEW SQL migration. Preserve RLS/auth checks and all existing function behavior.

For older clients whose upsert payload omits this key, preserve the existing stored setting on update; default only on insert. An absent server key from an older environment reads as automatic. Unknown future enum values read as automatic in the client but are not silently written over known explicit settings during unrelated edits. Existing global-food edit permissions remain unchanged; use the existing household edit/copy path.

Generate Drift code and schema history using repository commands, replay every historical upgrade, and test a real local database plus hosted deployment verification before calling release complete. Deploy the additive server migration before the new client. A client rollback leaves the additive column; no destructive down migration. No new table or RLS trust boundary. Revision 2 additionally persists the reviewed package/nutrition relationship described in R9–R13 below.

## UI and state coverage

Use existing theme, select, spacing and semantic patterns. No screen redesign. Wrap long package/need labels at current mobile and desktop widths; no clipping at 200% text scale. Test light/dark, edit cancellation, unchanged save, explicit override/reset-to-Automatic, offline edit/restart, normal sync refresh and stale/missing food lookup. A loading or missing food uses conservative source-unit fallback, then updates when metadata arrives; it must not hide quantity text. No new modal error for missing classification. No live announcements beyond existing semantics; spoken amounts must match visible units.

## Acceptance and milestones

A1 / R1–R3: table examples plus 16 oz boundary, half/double scaling, aggregate permutations, mixed oz/lb, mass+volume with/without density, incompatible count units, zero and signed quantities. Canonical equality within 1e-9 relative error (absolute floor 1e-9 g); no accumulated rounding. Triple tsp still promotes to tbsp.

A2 / R4,R8: override save/reopen, draft recovery, duplicate/merge, sync push/pull; absent/invalid setting fallback; old-client omitted-key upsert preserves explicit setting; all historical Drift migrations and RLS guards pass. Food source refresh preserves override.

A3 / R5–R7: widget fixtures on all three main areas plus cook-along and export review show the table results. Pack shortage/subtraction and contribution rebuild match canonical totals. 14.5 oz and unchanged 28 oz pack round-trip unchanged. Any rounded original value stays as stored until explicitly corrected. Export preview exactly matches the shopping decision.

A4 / R5,R8: actual Flutter captures of food control/package field, grouped/consolidated/scaled recipes, cook amounts and shopping primary/detail/export quantities; narrow phone and desktop, light/dark, 200% text. Independent code/security and image-backed UX review, then Astra acceptance. Native macOS synthetic-data walkthrough; simulator/device evidence when available. Mac tests alone do not prove Windows/iOS runtime correctness; record platform coverage precisely.

M1: domain policy and failing-then-passing regressions accepted. M2: schema/sync/editor compatibility accepted. M3: all surfaces, deterministic gates and independent reviews accepted. M4: reviewed green PR and deployment evidence only to the destinations approved below.

## Scope, tools and delivery

Use existing Flutter/Dart/Riverpod/Drift/Supabase/GitHub tooling. Astra plans/integrates; subscription-backed Claude implements and independently reviews through the installed controller's supported foreground workflow. No new paid tools, dependency, background supervisor or development model API. The user-requested photo flow reuses Hearth’s existing server-side label AI and its existing cost/rate limits; do not increase a spending ceiling. Development Claude sessions remain subscription-backed. See EXECUTION.md for capabilities and task gates.

Proposed implementation delivery is a feature branch and reviewed green PR to gradybre/hearth, with an additive linked Supabase migration after local verification under repository rules. No device reinstall, app distribution change or data deletion. App merge/install is not included in this planning-only request; any subsequent approval may extend release authority. Repo PR declarations remain truthful. Before execution, revalidate linked target, existing ship/merge instructions and any explicit human release authorization; do not inherit a different feature's approval.

This plan also amends spec §4/§5.2/§5.5/§5.7 to describe the accepted unit policy and reconcile §5.7's stale recipe-units-only/purchase-mapping-deferred sentence with the existing package-display feature. It does not expand purchase integration capabilities.

Definition of done for this turn: reproducible findings, a concrete versioned proposal and execution package ready for approval. Definition of done for implementation: all A1–A7 satisfied, full static/test gates pass, schema applied/verified, independent reviews resolved and PR CI green; report any unfulfilled release/platform gate explicitly.


## Revision 2 — package size connects recipe amounts to nutrition

User steering: allow manual entry of package amount plus servings per package, and capture both through the existing label-photo feature using the back nutrition panel and front package size. This extends the original unit-display fix into nutrition conversion, without removing any v1 requirement. Original R1's preservation of macro math means preserve correct existing results, not prohibit the new missing-data conversion.

### R9 — Store a food-specific package-to-serving relationship

A food may state:

- Package amount: 10 oz (mass, not fluid ounces).
- Nutrition serving: the selected existing serving row, 1 cup.
- Servings per package: 2.

Then one package contains 2 × 1 cup = 2 cups, one cup corresponds to 5 oz of this food, and 30 oz is 3 packages = 6 cups = 6 nutrition servings. With an illustrative label of 100 kcal per cup, the recipe contribution is 600 kcal. Scale every known nutrient by 6; unknown optional nutrients stay unknown. No rounded intermediate step or fabricated per-100g reference is stored. Multiplying recipe servings later uses normal recipe scaling; it does not count packages or nutrition servings twice.

General rule: for package mass P, N servings per package, and serving volume V, gramsPerMillilitre = P.canonicalAmount / (N × V.canonicalAmount). For an ingredient mass Q, serving count = (Q/P) × N; equivalent volume = serving count × V. Reverse conversion uses the same relation. N is a count of the selected serving, not a cup count: 4 servings of ½ cup is also 2 cups. Fractional serving counts such as 2.5 are valid. oz and fl oz remain different dimensions. Never assume a cup weighs eight ounces, or reuse this relationship for another food/product or dry/cooked state.

Only activate a mass↔volume relationship when the package amount and selected nutrition serving describe the same contents in the same state. Net weight including liquid cannot establish drained cup weight; a dry package cannot establish cooked/as-prepared cup weight. The review must distinguish these when shown by a label and allow manual correction or leaving the link unset. No generalized preparation-yield or multipack model is introduced. If scanning a multipack, ask the user in the editor to identify the one package and corresponding serving count; do not guess whether the count applies to an inner bag or the outer box.

### R10 — Manual entry and review

Move the existing pack-size field out of the Walmart-specific area into a shared “Package & nutrition” section near servings. Reuse the same Food.packSize value for nutrition and shopping; no two independently editable copies. Walmart retains its product link field.

Fields:

1. “Package amount” — amount and unit, e.g. 10 oz.
2. “Nutrition serving” — pick an existing nutrition row, e.g. 1 cup. Preselect only when there is one unambiguous eligible row; otherwise require a choice.
3. “Servings per package” — positive number/fraction, e.g. 2; optional “About” qualifier for approximate printed counts.

Show a live review sentence: “1 package = 2 servings = 2 cups” and “1 cup = 5 oz”. This is a local calculation on entered data, not an AI claim. Edits update the preview immediately. Saving the reviewed food confirms the complete relation; no extra permission dialog. Leaving serving count blank retains the existing package-only behavior. Incomplete or invalid input does not invent a relation; show a field explanation and allow saving the food without that link. Explicitly entered invalid data must be corrected or cleared, not silently discarded on Save. Cancel preserves the original food.

The relation is bound to the selected serving row and amount, not whichever serving happens to be first later. Changing only macros updates future calculations normally. Changing package amount, serving amount, or selected serving asks the user to review/reconfirm the displayed relation in the editor; deleting that serving disables it. Automatic imports, product-size updates or merges that change its basis must mark it stale instead of silently applying the old serving count to a different package. Show “Check package servings” and preserve original facts for correction. Prior logged snapshots remain frozen.

If a panel explicitly says “about 2 servings”, preserve that qualifier and show “Approximate conversion from package label” beside the derived relation. The arithmetic uses 2 after review, but do not present the physical relationship as an exact measurement. Blurred/ambiguous digits require correction or explicit acceptance in review before activation. A valid approximate link is usable; unresolved uncertainty is not a zero or a valid density.

### R11 — One label workflow, two optional photo slots

Extend the existing read-label sheet with named slots: “Nutrition label” (back) and “Package size” (front), each offering camera/library as available, preview, replace and remove. The user may add the second photo to a back-label draft without losing prior edits. Both photos are optional as a pair: preserve label-only scanning, front-photo plus manual nutrition, and entirely manual entry. When both facts appear in one clear photo, one is sufficient. Never require a second capture for already readable information.

Use a deliberate “Read photos” action after selection so two-photo entry is one extraction request through the existing label mode. Extend its structured response with optional net package amount/unit, servings-per-container number, approximate qualifier, source field provenance and preparation/basis uncertainty. Existing readPack remains supported for the package-fill flow. Add explicit image roles to the request metadata if needed; roles are hints, never proof of product identity. The model transcribes printed facts and uncertainties only; deterministic domain code performs conversions. Remove the existing instruction to ignore servings per container. Do not manufacture a serving or infer missing net weight by multiplying nutrition values.

Bring nutrition rows, package amount and serving count into one editable food review. When applying to an existing food, preserve edited nutrition, package, Walmart, mass-display and unrelated fields. A conflicting scan value is a proposal shown alongside the existing value, not an automatic replacement. If two photos visibly identify different products or sizes, leave the relation inactive and explain what needs correction. Do not claim automatic identity verification when only a cropped panel is visible; the user reviews the pair as the same package.

State coverage: empty slots; one/both photos selected; camera/library canceled; replace/remove; reading; successful full/partial read; unreadable package text; unreadable serving count; unavailable server/offline; oversize image; retryable failure; nonretryable quota/auth failure; cancel/reset/reopen; stale response after edit/dismissal. Cancellation never clears the other slot or manual fields. A failed read retains selected images for retry; a successful extraction drops raw images under existing privacy rules and preserves extracted review facts. Do not persist photos or base64 in food rows, logs, sync or evidence. Guard mounted/disposed generations so old responses cannot overwrite a newer selection/review.

Keep current 5 MiB per-image limit and server aggregate limits (currently 18 MiB, 10 images); the new UI needs only two slots. Do not change model, AI budget ceiling or rate-limit policy. Each explicit combined read is one normal label call; retry is explicit. Capture metadata records field origin (manual/nutrition photo/package photo), without storing original image content. Desktop uses library selection; actual camera capture is verified on a supported mobile device.

### R12 — One conversion service across nutrition and aggregation

Implement a pure, food-scoped conversion result including the quantity/serving ratio, source and approximate qualifier. Food.effectiveGramsPerMillilitre may expose the numeric value for compatible existing callers, but callers presenting nutrition must also be able to retain its source/qualifier. Do not write the derived number into the existing explicit density field: it would outlive its inputs and lose provenance.

Preserve this precedence: usable direct same-kind nutrition serving; explicit food density or established own-serving equivalence; confirmed package relationship; existing generic-density fallback. A package relation fills a missing link; it does not silently override a directly stated mass serving. Surface conflicting package/serving data in review. For a deterministic conflict indicator, compare implied mass per serving to an existing usable direct mass/volume equivalence and flag a relative difference greater than 5%; this is a UI warning threshold, not permission to alter either value. Below that threshold still preserve the printed facts and precedence. Approximate counts remain marked approximate at any difference.

For linked package-derived nutrition, calculate from the selected serving’s macros, not an arbitrary volume row. Zero-calorie foods can still have valid package equivalence: deriving it must not depend on nonzero energy. Missing required quantities cannot become zero-calorie success. Retain existing data-gap behavior if no permitted conversion resolves the amount.

Use the shared conversion in recipe ingredient/whole/per-serving nutrition, scaled recipes, food portion entry and planned/logged food calculations where raw mass units are offered, and matched-food shopping mass/volume consolidation. Audit the existing portion selector’s same-kind-only assumption; offer raw mass/volume units only when this food can actually convert them. Do not teach Quantity or global unit constants a universal cup-to-ounce factor. Reuse food identity/lookup in shopping so two products with different densities never share the relation just because their names resemble one another.

Show a concise “Nutrition uses approximate package servings” note on recipe/food nutrition when this qualifier contributes to the result. Newly logged snapshots retain the qualifier through their existing extensible snapshot payload; old snapshots omit it and remain unchanged. Do not replace missing-nutrient or incomplete-data notices with this note. Recipe text and shopping keep their display-unit policy from R1–R8; deriving cup equivalents does not turn 30 oz in the recipe into 6 cups on screen unless the user explicitly chooses that measure.

### R13 — Additive persistence and scan contracts

In addition to mass_display_mode, add nullable Food/foods `package_nutrition` as one atomic versioned record (server JSONB, local nullable JSON text) so the count, selected serving and evidence cannot drift independently in sync. Version-1 record:

- `version: 1`.
- `servings_per_package`: positive finite number.
- `serving_option_id`: stable selected serving ID.
- `serving_amount`: snapshot `{canonical_amount, kind, unit}`.
- `package_amount`: snapshot with the same shape.
- `is_approximate`: boolean.
- `source`: `manual`, `photos`, or `mixed`.
- `basis`: `as_packaged`; unverified/prepared/drained interpretations never activate automatically.

Only reviewed complete records are saved as active candidates. Validity is derived by comparing referenced current package/serving facts with snapshots; numeric equality uses existing same-kind tolerance, ID and dimension must agree. Reordering rows is harmless. Deleted/missing/changed rows are stale. Unknown record versions do not activate; preserve opaque values on unrelated writes for forward compatibility. Distinguish an omitted key (old-client upsert preserves stored relation) from explicit null (user removes it). Enforce shape, finite positive values, allowed enum values and payload bound on server and client; cap this compact record at 4 KiB. Validate selected serving membership atomically in the food upsert transaction, preserving old-client updates even when they make an existing relation stale. No new client secret or permission scope.

Extend mappers, draft recovery, sync payloads, food reconstruction paths, merge/duplicate, tests and generated schema history. Duplicate can remap a serving ID only when it copies the exact basis. Merge preserves the survivor’s relationship; adopting the retiring food’s relationship requires identical package and selected-serving facts with a safe ID remap, otherwise keep it unlinked for review. A source refresh cannot replace a human-confirmed record. Apply server additive migration and compatible label-function response extension before releasing clients. Old clients ignore extra response keys; old servers omit them and the client still supports manual completion. A failed/partial scan never erases existing fields. Deploy through existing linked function configuration, preserving auth/rate limits/secrets. Do not start a new external service.

## Additional acceptance and delivery gates

A5 / R9,R12: 10 oz, 1 cup, 2 servings/package gives 5 oz/cup; a 30 oz ingredient gives 6 servings and 600 kcal when the fixture label says 100 kcal/serving. Verify every macro and nullable minor nutrient, both conversion directions, half/double recipe scales, ½-cup serving with 4 servings/package, fractional counts, zero-calorie food, oz versus fl oz, missing/zero/negative/nonfinite values, prepared/drained basis, count-unit rejection, density precedence/conflict, linked shopping consolidation and different-food isolation. “About” remains visible; no intermediate rounding. Canonical relative error <=1e-9 with 1e-9 absolute floor. No global density table modification.

A6 / R10,R13: manual save/reopen and photo-to-review persistence, existing draft/package/link/mass-display preservation, deterministic serving selection, reordering/remapping, package/serving edits/removal and stale relationships, explicit clear versus omitted-key old-client update, remote sync/restart/merge and every historical local DB upgrade. New qualifier round-trips in new log snapshots; editing the food cannot change old logs. Unsupported metadata does not silently activate. Test concurrency: a late scan cannot replace fields changed since the request started.

A7 / R11: two-photo request produces one structured read/review; single-photo/back-only/front-only/manual paths remain valid. Test partial/unreadable/contradictory reads, approximate serving counts, unknown units, per-serving versus per-container nutrient columns, different-product evidence, existing-value conflicts, all cancellation/retry/disposal/generation cases, both size guards and auth/rate/budget guards. Schema/adapter tests alone do not establish photo extraction: use synthetic nutrition/front images through the real configured label function within existing authorized app budget. If live function access or existing budget authorization is unavailable, record that live gate as pending and still complete deterministic checks. No API billing fallback for development workers.

Capture actual updated food editor and two-slot photo flow/review, including narrow phone/desktop, light/dark, 200% text and partial/error states. Independent code/security review covers conversion precedence, atomic upsert, stale evidence and photo handling. Independent image-backed UX review covers clarity of “servings” versus “cups”, photo roles and derived preview. Extend M1 with A5, M2 with A6, M3 with A7, and M4 with compatible migration/function deployment evidence. All original A1–A4 remain required.
