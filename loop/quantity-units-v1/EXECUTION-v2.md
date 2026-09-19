# Execution package — P-HEARTH-QUANTITY-001 v2

Normative contract: PLAN-v2.md. This package supersedes EXECUTION.md; original v1 remains historical. Manifest hashes freeze the approval candidate. No source development before actual initial-plan approval. Astra remains the only planning/acceptance owner; Claude returns ambiguity for a versioned decision and must acknowledge it before resuming affected work.

## Scheduling and evidence contract

One source writer, at most four total model sessions including Astra, one heavy job. Serial integration is preferred because domain, persistence and surfaces share contracts. Every dispatch packet records task/revision, approved plan hash, baseline/candidate SHA, exact inputs, requirement/acceptance IDs, resolved actual provider/model/session, source/worktree/evidence locations, writer lease, start/progress/deadline, attempts and stop disposition. Evidence directories/controller secrets remain outside product source; only scrubbed durable results enter this loop directory.

All author packets: max 18k output tokens, 15-minute deadline, 4-minute no-progress bound, two bounded repair attempts. Use subscription-backed Sonnet for routine work; Opus for the compatibility/persistence contract and high-risk review. Resolve actual account model IDs, never assume availability or substitute a billed API. Independent review packets: read-only, 8k output tokens, 10-minute deadline, 4-minute no-progress bound, at most two repair/re-review cycles. Poll commands within 60 seconds. Record exit code directly. A full test job has a 30-minute deadline and exclusive heavy lease; terminate only proven owned processes.

Exact tolerances: R1–R13 semantics, choice labels, data/permission/old-client behavior, no automatic data rewriting. Bounded: numeric tolerances A1/R6, 200% text layout, job/time/output limits. Delegated: helper names, internal pure types, equivalent existing widgets and file splitting within allowed modules. Prohibited: new dependencies/paid tools, change to food identity or correctly resolved existing nutrition math outside R9–R13, guessing pack counts, schema-history edits, unapproved network handoff, weakening failed acceptance, overlapping writers, hidden background execution.

## D0 — Astra readiness and approval capture

Record actual user approval and any D3/D6/D9 changes; publish a new version when material behavior changes. Reconcile git status and live owned jobs before any retry. Re-read repository/controller instructions and capability state. Do not start a competing controller. Branch/worktree from current main; compare every affected baseline file and revise plan for concurrent source changes. Check Flutter/Dart, controller pinned Claude executable/auth, account model IDs, capture availability, GitHub authentication, Supabase target and migration history. Configure supported public real-project controller contracts only after approval; never run bootstrap fixtures as the project.

Freeze domain resolver interface and precedence as a recorded contract before D1. Proposed shape: context carries food setting, pack quantity, system and source mass-unit/package evidence; result selects display unit without changing Quantity. Do not persist a resolved unit as the authored unit. Audit every Food reconstruction and Quantity normalise caller with rg. Exact file inventory in the final dispatch packet may narrow the module roots below but cannot broaden scope without Astra review.

## D1 — Claude Sonnet: domain policy and regression tests

Requires D0. Covers R1–R3,R6–R7 / A1. Allowed: lib/domain/units, lib/domain/format, lib/domain/parsing/ingredient_parser.dart, lib/domain/recipes/{recipe_scaler,ingredient_consolidator}.dart, lib/domain/shopping/{shopping_contribution,pack_display}.dart and corresponding domain tests. No persistence, adapters, feature screens or generated code in D1; later packets own the added nutrition contract.

First return tests reproducing F1/F2/F4, verify baseline failures, then implement. Keep canonical sums and counts unchanged. Carry all source hints through combine/settle, retain original mass hints through scaling, make selection permutation-invariant, separate raw package-evidence extraction from quantity parsing. Generic volume normalization remains tested. Safe exact editable serialization must be separate from label rounding. Include boundaries, mixed kinds, missing units, negative amounts, all-oz unknown, mixed lb/oz beef, explicit Weight/Ounces contexts and misleading names such as beef jerky. Astra checks actual diff and reruns tests before M1 acceptance.

## D2 — Claude Opus: food preference and compatibility

Requires D1 and D1N domain contracts/M1. Covers R4,R6,R8 / A2. Allowed: lib/domain/models/food.dart; food draft/editor; food mapper/sync payload/store/repository/merge paths identified by D0; Drift source tables/database plus generated outputs; a NEW Supabase migration; drift_schemas and generated migration tests; corresponding tests. No historical SQL edits, private data, unrelated server functions or unrelated screens.

Add enum/default and preserve across every copy/serialization boundary. Reuse existing permissions and food editing patterns. Preserve old-client omitted-key updates server-side. Fix pack editing via lossless value serialization plus unchanged-field preservation; simply replacing format with formatAsAuthored is inadequate. Add failing tests for 28 oz/14.5 oz unchanged saves. Test unknown enum, missing field, refresh, duplicate/merge, offline/restart and sync. Generate code/schema records, replay upgrades from every historical version and run local SQL guards. Astra independently verifies a real local old/new payload round-trip and M2 before any hosted migration.

## D3 — Claude Sonnet: surface integration

Requires M1/M2. Covers R5–R8 / A3. Allowed: food list/picker/pack review paths needing shared formatting; recipe detail/cook-along/step_amounts and associated provider context; shopping screen/amount sheet/export sheet; lib/data/adapters/walmart_export.dart; relevant tests/render fixtures. No independent unit heuristics, macro changes beyond R9–R13, ingredient identity changes or external actions.

Feed matched food context once per existing provider snapshot; avoid per-row remote fetch. Use source context for unmatched rows. Audit all QuantityFormat.format/formatAsAuthored and normalise call sites, including companion labels and rebuilds. Both purchase preview and export text derive from the same decision. Inputs/edits retain their own units; unchanged amount saves retain original quantity. Tests must cover complete journeys, not only formatter calls, and prove source contribution rebuild stays correct after unit changes.

## D4 — Astra checks and independent Claude reviews

Requires D3 and D3N candidates. Run focused domain/data/widget tests, formatter check, flutter analyze and full flutter test, reading real exit codes. Run migration history/no-secrets/architecture checks; do not interpret local SQL success as hosted migration success. Capture actual Flutter fixture screens for A4 with no production user data. Conduct native Mac synthetic walkthrough. Produce candidate digest, per-acceptance coverage, command/version/time/exit evidence and capture manifest.

Independent Opus code/security review examines the exact candidate diff and compatibility/rounding/aggregation evidence, including omitted-key server semantics and permission invariants. Independent vision-capable Sonnet/Opus examines actual captures for label agreement, wrapping, semantics and control placement. A source summary cannot establish visual quality. Astra disposition: accept, bounded repair or versioned scope change; rerun affected evidence after repairs. Missing reviews/captures hold M3.

## D5 — Astra reviewed delivery

Requires M3 and approved target verification. Update relevant spec and plan/result records. Follow the repository ship workflow, preserving accurate DEVIATIONS, NEGATIVE_TESTS and BLOCKED declarations. Create one draft PR for the coherent feature; review/repair and wait for all actual CI checks to finish, then mark ready. Additive linked Supabase migration and backward-compatible recipe-ai label response extension are applied only after local checks and target confirmation, using existing authorized account; verify migration list and live compatible round-trip without modifying user foods. If hosted access is unavailable, report migration gate as incomplete.

Current proposed endpoint: reviewed green PR, no app install or merge inferred from another feature's approval. Record PR, SHA, actual models/review sessions, schema version, deployment status and any untested platforms. No external export/cart is invoked. Rollback client changes if needed; retain additive schema and user data. Subsequent explicit release authorization can update this stage without repeating settled approvals.


## Revision 2 execution additions and overrides

This is a scope extension requested by the user, not an approved production run. User intent and new acceptance are in PLAN-v2.md R9–R13/A5–A7. Do not dispatch v1 packets after approval of v2; re-hash/rebase the single combined feature. Original numeric/unit behavior requirements stay in force. Baseline remains unchanged. No author/reviewer sessions have been started during discovery.

DAG: D0 → D1 → D1N → M1 → D2 → M2 → D3 → D3N → D4 → M3 → D5. No concurrent source writers. D1N defines the relation contract before D2 persists it; D3N includes final combined capture/interaction candidate. Slots/time/retry bounds from the common contract apply. Split oversized task output into bounded packets; do not omit tests or silently relax scope.

### D0 additions — Astra

Freeze the versioned package_nutrition record and pure conversion/provenance interface from R13/R12. Inspect current food upsert and servings transaction, mutable draft merging, source refresh and all Food reconstruction paths. Map effectiveGramsPerMillilitre, MacroCalculator, PortionUnit/default-serving translation and shopping density lookups before author dispatch. Identify existing snapshot JSON extension points for approximate qualifier without rewriting prior entries. Verify actual linked function target and authorized existing image-call budget before live extraction; do not issue a charged probe simply to discover billing permission. Synthetic image fixtures are local test assets, not user images.

### D1N — Claude Sonnet author; Opus review at D4

Requirements R9,R12; acceptance A5. Allowed: lib/domain/models/food.dart; new bounded pure domain package/nutrition helper; lib/domain/recipes/macro_calculator.dart; lib/domain/planning/portion_unit.dart and related portion-conversion helpers; matched-food consolidation contract and corresponding tests. No SQL/mappers/feature widgets/global density edits.

First reproduce a food with only 1 cup nutrition and 10 oz package being unconvertible for a 30 oz ingredient. Then add confirmed relationship calculation with source/approximation result, validate same-product/basis snapshots, and implement stated precedence. Route only the missing conversion through package metadata and selected-serving macros; preserve direct nutrition. Define new qualifier properties as backward-compatible default values. Tests must assert exact recipe macro contribution and inverse quantity, not just the derived density scalar. Keep the provisional record pure and explicit so D2 can persist without inventing semantics. Any conflict with legacy direct mass/cup equivalence is a decision to return to Astra, not permission to replace accurate existing data.

### D2 additions — Claude Opus persistence/editor

Requirements R10,R13; acceptance A6. Extend existing D2 allowed paths to snapshot qualifier serialization, log/portion data mappers when required, food relation model, package-fill update paths and related tests. Add mass_display_mode and nullable package_nutrition in the same new forward migration; leave the original v1 proposal unimplemented. Detect stale relation when an old client updates package/serving facts without sending metadata; the upsert must preserve the metadata and client validity logic must reject its mismatched basis. Unknown-version payload is preserved but not activated.

Move pack amount to Package & nutrition without duplicate fields. Implement serving selection, count, About qualifier, local preview and confirmation through Save. Prevent FoodDraft.withLabel from reconstructing a draft that loses its existing pack/Walmart/override fields. Merge proposals into the latest draft, not the request snapshot. Test missing, invalid, stale and cleared metadata; counts are servings of the selected measure, never assumed cup counts. Verify derived metadata is not cached into explicit density or fabricated editable serving rows. Preserve signed modifiers and old snapshots.

### D3 additions — Claude Sonnet surfaces

Requirements R12; acceptance A5/A6. Extend D3 allowed paths to recipe nutrition notes, food logging portion selector and snapshot qualifier presentation. Shared conversion enables valid raw-weight input for a cup-only food with confirmed package metadata. UI must not offer units that fallback to a mislabeled unchanged count. Recipe total still reads 30 oz while its nutrition derives from 6 one-cup servings. Shopping count remains 3 × 10 oz; known food-specific cup↔mass consolidation shares the relation rather than guessing from a name. Manual override and conflict notes must agree across fresh/reopened screens. Historic log text must not be recomputed from current food metadata.

### D3N — Claude Sonnet scan workflow, server contract and tests

Requirements R11,R13; acceptance A7. Allowed: lib/data/adapters/{label_reader,edge_function_label_reader}.dart; lib/features/foods/{read_label_sheet,label_scan_controller,food_draft,food_editor_screen}.dart; existing callers only for signature propagation; supabase/functions/recipe-ai/index.ts and new bounded label shaping/test helper if required; adapter/controller/widget/Edge Function tests and synthetic capture fixtures. No auth/budget ceiling/key/provider changes. Shared files are leased only after earlier tasks release them.

Replace the one-photo auto-read UI with two named selectable slots plus Read photos; one/back-only read stays supported. Preserve existing readPack. Extend label tool schema, prompt, response narrowing and Dart decoder together; add serving count/approximate, package quantity, basis/uncertainty provenance as optional fields. Keep model output transcription-only. Prefer one request with both images through current label mode, preserving all caps and server rate/cost accounting. Never accept a count taken from per-container calories or package mass mistaken for serving mass. Do not coerce malformed values to 0. Old clients/old responses must continue working.

Use per-slot/request generations and cancel checks. Failure retains photos; success drops originals and yields review facts. Retry is explicit, replacement invalidates obsolete results, and sheet reopen starts fresh. Partial success gives editable facts without an active relation until all required reviewed inputs exist. Existing manual values win unless the user accepts a visible replacement proposal. Add race tests for manual edits during request and dismissal/reopen; add adapter/server tests for two-image inputs, empty/malformed count/unit, About counts, serving-versus-container columns, role ambiguity, caps and budget denial.

### D4 additions — evidence and reviews

Run the additional baseline suite plus new focused domain/portion/snapshot/scan tests, adapter/server contract tests and existing Deno budget/security checks. Determine reproducible Deno command from current repository CI rather than inventing flags. Full Flutter/analyze/schema gates still required. Run an actual synthetic two-photo extraction through the configured deployed label function only within existing authorized app budget and inspect reviewed output; mocked JSON is not live extraction evidence. Otherwise report that live gate as pending. Actual camera workflow requires supported device; desktop file selection cannot claim it.

Screenshots show initial two-slot flow, both selected, partial-read review, manual Package & nutrition inputs, 10 oz / 1 cup / 2 example relation, approximate/conflict states, resulting 30 oz recipe calories and shopping packages. Capture narrow/desktop, light/dark and 200% text. Opus independently reviews persisted evidence lifecycle, upsert omissions/nulls, macro/density precedence, image privacy, stale requests and zero-calorie behavior. Vision reviewer checks labels distinguish servings from cups and food package from purchase links. Astra verifies every A1–A7, recording limitations precisely.

### D5 additions — compatible deployment

Amend spec §§4,5.2,5.3,5.5,5.6,5.7 for the confirmed food-specific relation and reviewed image workflow. Publish additive DB change first, compatible Edge Function second, then release client through the approved PR boundary. Verify migration parity and real label adapter compatibility; no production food edits for testing. Function rollback retains old label-only behavior and manual completion; client rollback retains additive metadata for future restoration. Preserve existing keys/configuration. A passing mock does not satisfy deployment verification. Complete one coherent feature PR with all relevant gates, not separate partially functioning schema/photo releases described as complete.
