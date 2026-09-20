# Execution package — P-HEARTH-QUANTITY-001 v1

Normative contract: PLAN.md. Manifest hashes freeze the approval candidate. No source development before actual initial-plan approval. Astra remains the only planning/acceptance owner; Claude returns ambiguity for a versioned decision and must acknowledge it before resuming affected work.

## Scheduling and evidence contract

One source writer, at most four total model sessions including Astra, one heavy job. Serial integration is preferred because domain, persistence and surfaces share contracts. Every dispatch packet records task/revision, approved plan hash, baseline/candidate SHA, exact inputs, requirement/acceptance IDs, resolved actual provider/model/session, source/worktree/evidence locations, writer lease, start/progress/deadline, attempts and stop disposition. Evidence directories/controller secrets remain outside product source; only scrubbed durable results enter this loop directory.

All author packets: max 18k output tokens, 15-minute deadline, 4-minute no-progress bound, two bounded repair attempts. Use subscription-backed Sonnet for routine work; Opus for the compatibility/persistence contract and high-risk review. Resolve actual account model IDs, never assume availability or substitute a billed API. Independent review packets: read-only, 8k output tokens, 10-minute deadline, 4-minute no-progress bound, at most two repair/re-review cycles. Poll commands within 60 seconds. Record exit code directly. A full test job has a 30-minute deadline and exclusive heavy lease; terminate only proven owned processes.

Exact tolerances: R1–R8 semantics, choice labels, data/permission/old-client behavior, no automatic data rewriting. Bounded: numeric tolerances A1/R6, 200% text layout, job/time/output limits. Delegated: helper names, internal pure types, equivalent existing widgets and file splitting within allowed modules. Prohibited: new dependencies/paid tools, change to food identity or nutrition math, guessing pack counts, schema-history edits, unapproved network handoff, weakening failed acceptance, overlapping writers, hidden background execution.

## D0 — Astra readiness and approval capture

Record actual user approval and any D3/D6/D9 changes; publish a new version when material behavior changes. Reconcile git status and live owned jobs before any retry. Re-read repository/controller instructions and capability state. Do not start a competing controller. Branch/worktree from current main; compare every affected baseline file and revise plan for concurrent source changes. Check Flutter/Dart, controller pinned Claude executable/auth, account model IDs, capture availability, GitHub authentication, Supabase target and migration history. Configure supported public real-project controller contracts only after approval; never run bootstrap fixtures as the project.

Freeze domain resolver interface and precedence as a recorded contract before D1. Proposed shape: context carries food setting, pack quantity, system and source mass-unit/package evidence; result selects display unit without changing Quantity. Do not persist a resolved unit as the authored unit. Audit every Food reconstruction and Quantity normalise caller with rg. Exact file inventory in the final dispatch packet may narrow the module roots below but cannot broaden scope without Astra review.

## D1 — Claude Sonnet: domain policy and regression tests

Requires D0. Covers R1–R3,R6–R7 / A1. Allowed: lib/domain/units, lib/domain/format, lib/domain/parsing/ingredient_parser.dart, lib/domain/recipes/{recipe_scaler,ingredient_consolidator}.dart, lib/domain/shopping/{shopping_contribution,pack_display}.dart and corresponding domain tests. No persistence, adapters, feature screens or generated code.

First return tests reproducing F1/F2/F4, verify baseline failures, then implement. Keep canonical sums and counts unchanged. Carry all source hints through combine/settle, retain original mass hints through scaling, make selection permutation-invariant, separate raw package-evidence extraction from quantity parsing. Generic volume normalization remains tested. Safe exact editable serialization must be separate from label rounding. Include boundaries, mixed kinds, missing units, negative amounts, all-oz unknown, mixed lb/oz beef, explicit Weight/Ounces contexts and misleading names such as beef jerky. Astra checks actual diff and reruns tests before M1 acceptance.

## D2 — Claude Opus: food preference and compatibility

Requires D1 contract/M1. Covers R4,R6,R8 / A2. Allowed: lib/domain/models/food.dart; food draft/editor; food mapper/sync payload/store/repository/merge paths identified by D0; Drift source tables/database plus generated outputs; a NEW Supabase migration; drift_schemas and generated migration tests; corresponding tests. No historical SQL edits, private data, unrelated server functions or unrelated screens.

Add enum/default and preserve across every copy/serialization boundary. Reuse existing permissions and food editing patterns. Preserve old-client omitted-key updates server-side. Fix pack editing via lossless value serialization plus unchanged-field preservation; simply replacing format with formatAsAuthored is inadequate. Add failing tests for 28 oz/14.5 oz unchanged saves. Test unknown enum, missing field, refresh, duplicate/merge, offline/restart and sync. Generate code/schema records, replay upgrades from every historical version and run local SQL guards. Astra independently verifies a real local old/new payload round-trip and M2 before any hosted migration.

## D3 — Claude Sonnet: surface integration

Requires M1/M2. Covers R5–R8 / A3. Allowed: food list/picker/pack review paths needing shared formatting; recipe detail/cook-along/step_amounts and associated provider context; shopping screen/amount sheet/export sheet; lib/data/adapters/walmart_export.dart; relevant tests/render fixtures. No independent unit heuristics, macro changes, ingredient identity changes or external actions.

Feed matched food context once per existing provider snapshot; avoid per-row remote fetch. Use source context for unmatched rows. Audit all QuantityFormat.format/formatAsAuthored and normalise call sites, including companion labels and rebuilds. Both purchase preview and export text derive from the same decision. Inputs/edits retain their own units; unchanged amount saves retain original quantity. Tests must cover complete journeys, not only formatter calls, and prove source contribution rebuild stays correct after unit changes.

## D4 — Astra checks and independent Claude reviews

Requires D3 candidate. Run focused domain/data/widget tests, formatter check, flutter analyze and full flutter test, reading real exit codes. Run migration history/no-secrets/architecture checks; do not interpret local SQL success as hosted migration success. Capture actual Flutter fixture screens for A4 with no production user data. Conduct native Mac synthetic walkthrough. Produce candidate digest, per-acceptance coverage, command/version/time/exit evidence and capture manifest.

Independent Opus code/security review examines the exact candidate diff and compatibility/rounding/aggregation evidence, including omitted-key server semantics and permission invariants. Independent vision-capable Sonnet/Opus examines actual captures for label agreement, wrapping, semantics and control placement. A source summary cannot establish visual quality. Astra disposition: accept, bounded repair or versioned scope change; rerun affected evidence after repairs. Missing reviews/captures hold M3.

## D5 — Astra reviewed delivery

Requires M3 and approved target verification. Update relevant spec and plan/result records. Follow the repository ship workflow, preserving accurate DEVIATIONS, NEGATIVE_TESTS and BLOCKED declarations. Create one draft PR for the coherent feature; review/repair and wait for all actual CI checks to finish, then mark ready. Additive linked Supabase migration is applied only after local checks and target confirmation, using existing authorized account; verify migration list and live compatible round-trip without modifying user foods. If hosted access is unavailable, report migration gate as incomplete.

Current proposed endpoint: reviewed green PR, no app install or merge inferred from another feature's approval. Record PR, SHA, actual models/review sessions, schema version, deployment status and any untested platforms. No external export/cart is invoked. Rollback client changes if needed; retain additive schema and user data. Subsequent explicit release authorization can update this stage without repeating settled approvals.
