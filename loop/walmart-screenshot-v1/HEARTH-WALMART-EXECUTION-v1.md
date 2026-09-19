# Execution package — P-HEARTH-WALMART-001 v1

Status: awaiting human approval. Canonical package intended for `hearth/loop/walmart-screenshot-v1/`; user-facing copies in this task's outputs. Preserve approved versions and publish new revisions for material changes.

## Discovery and baseline

- User requested screenshot-based Walmart link autofill through Astra loop engineering, from package/nutrition or a separate screenshot containing the link.
- D1, proposed: visible-link transcription only. The optional clarification remains unanswered. Approval of PLAN v1 adopts this bounded scope; a request for matching requires further discovery.
- D2, proposed: independent screenshot action next to Walmart field; reuse the combined two-photo flow for incidental links. No third photo slot required.
- D3, proposed: auto-fill only empty fields, explicit replacement for differing existing values, review before Save.
- D4, verified: main is `4be6bc8292db5b4038ce4ebf5341878911e382d3`; existing PR #110 candidate is `75c9bb25a72210e00cdcd6b7855b544455483437`. Candidate worktree is clean. Main's untracked quantity planning files are unrelated and must remain untouched.
- D5, verified: #110 is open/draft, Analyze and test / Edge functions / Migrations and guards all SUCCESS. Its own RESULTS records pending native, hosted deployment and live photo checks. Do not inherit its authority or claim those gates passed.
- D6, verified: extracted candidates need a new strict parser. Existing `WalmartProduct.idFrom` takes numeric URL path segments without hostname validation; keep manual compatibility separate from extracted-link acceptance.
- D7, verified: pre-#110 `FoodDraft.withLabel` reconstructs a draft and omits purchase metadata; #110's preservation changes must be retained. Link-only parsing must extend its existing isEmpty semantics without activating or invalidating package nutrition review.
- D8, verified: label adapter and Edge function already share image plumbing, authenticated application AI and budget safeguards. New response fields can be additive; existing food persistence already stores the item ID.
- D9, verified: controller doctor returns Node v26.0.0, protocol 1, development, productionReady false, toolWorkersEnabled false. Foreground supported setup is required; no supervisor started and no worker dispatched during planning.

Baseline check on #110 candidate: 59 tests passed, exit 0, using:

```sh
flutter test --no-pub test/domain/shopping/walmart_product_test.dart test/data/adapters/edge_function_label_reader_test.dart test/data/adapters/pack_reading_test.dart test/features/foods/label_scan_test.dart test/features/foods/walmart_product_field_test.dart
```

An initial invocation named nonexistent `label_reader_test.dart` and exited 1; the corrected invocation above passed. This was a command selection error, not a product failure. Complete feature checks have not been run because implementation has not started. Baseline log is retained alongside the package.

## Tools and cost register

| Tool | Use / observed availability | Execution gate / fallback |
|---|---|---|
| Existing Flutter/Dart/Riverpod | Domain, UI, tests; local focused suite runs | Record exact versions before dispatch; preserve lockfile and current dependencies. |
| Existing Supabase function + Deno | Image extraction and server checks; source/CLI present | Verify linked target, auth and existing ceiling without printing secrets; no new provider. Manual entry remains usable. |
| Existing gh/GitHub | gradybre/hearth, #110 read and CI verified | Branch/PR write access verified at delivery; no account changes. |
| Installed loopctl 0.1.1 release | Subscription Claude author/review controller | Use documented real-project service setup; no fixture/bootstrap product runs or competing controller. Resolve actual available model IDs per attempt. |
| Existing Flutter gallery/native macOS | Real component images and walkthrough | Capture and interaction capability verified before acceptance; locked device becomes an explicit gate, not synthetic success. |

No new expense, dependency, asset service, scheduler or model API is proposed. Synthetic test fixtures use invented readable labels and known item-ID strings; no household photos or credentials are embedded in records. Development workers use the existing Claude subscription. The application continues using its already approved server AI budget.

## Shared dispatch contract

Each packet identifies task and revision, plan revision/hash, requirement and acceptance IDs, milestone, exact base/candidate SHA, input file hashes, current decisions, allowed paths, forbidden paths, model/session, resource lease, output format and resume context. Fill all values from the approved manifest/current repository before dispatch; a template is not a ready packet.

One source writer at a time. Maximum four model sessions aggregate including Astra and other project runs; reserve available capacity based on live ownership, not this task alone. One heavy build/test/capture job. Keep worker sessions grouped under the canonical Hearth source while changes occur in a separate worktree. Canonical controller state, evidence and workspaces must use separate directories as installed runtime requires. Do not alter private application databases or resume unrelated workers.

Authors use account-verified Sonnet for bounded routine implementation/tests, Opus for difficult security/lifecycle repairs. Code/security review uses a fresh independent Opus session; image-backed UX review uses a fresh validated vision-capable Sonnet/Opus session. Astra adjudicates actual diff/checks/images. Each worker: 15-minute total bound, 4-minute no-progress bound, at most 18k output tokens for implementation or 8k for review, at most two bounded repair attempts. A full deterministic suite has a 30-minute bound. Poll/update within 60 seconds; reconcile owned processes and partial results before retry. Terminate only known-owned jobs. No paid API fallback.

Tolerance classes: exact = PLAN behavior, host/path validator, merge/review semantics, data/security boundaries and copy. Bounded = 2,048 candidate characters, 10 candidates, 3–20 ID digits, 5 MiB image cap, one standalone or existing two combined images, 1,000 standalone output tokens, viewport/text-scale tests. Delegated = internal helper/component organization and names. Prohibited = guessed links, extra calls for combined images, automatic cart actions, schema changes, dependency broadening, increased spending or silent gate waiver.

## Task DAG

### T0 v1 — readiness and contract freeze (Astra)

Requires actual initial approval. Re-read source and controller instructions/status; reconcile existing jobs and #110. Create isolated feature worktree, versioned approved manifest and private service configuration via supported APIs. Resolve model IDs; record actual executable, account posture and session grouping. Freeze response types and validator fixtures before writers start. Verify native capture/test fixture path and resource availability. No source implementation in T0. Escalate unsupported runtime configuration rather than invoking a disposable probe as a product run.

### T1 v1 — extraction and strict validation (Sonnet, with Astra contract review)

Requires T0. R1–R3,R6 / A1,A2,A4; M1. Allowed paths: `lib/domain/shopping/walmart_product.dart`, `lib/data/adapters/label_reader.dart`, `lib/data/adapters/edge_function_label_reader.dart`, `supabase/functions/recipe-ai/index.ts`, `budget.ts`, a focused sibling validator module if needed, corresponding domain/adapter/Edge tests and adapter fakes. No UI/persistence or unrelated functions.

Implement strict canonicalizer separately from legacy manual parser. Share corpus examples between Dart and server tests. Extend label schema/prompt/shaper with optional candidates and per-field uncertainty. Add standalone mode with exact image bounds and complete budget routing. Shape an unambiguous safe result or null; old response remains readable. Keep original label/package facts intact and accept a link-only reading. Return validated structured file changes plus tests and actual session/model identity; do not claim tests not executed.

### T2 v1 — editor merge and screenshot flow (Sonnet)

Requires accepted T1 contracts. R3–R7 / A2,A3,A5; M1/M2. Allowed paths: `lib/features/foods/food_draft.dart`, `food_editor_screen.dart`, `label_scan_controller.dart`, `read_label_sheet.dart`, dedicated Walmart controller/sheet under the same directory, `lib/app/providers.dart` only if necessary, corresponding feature tests/fakes and gallery fixtures. Preserve #110's complete package review behavior. Bulk pack-fill is unchanged: its quantity-only batch save must not silently start saving Walmart links.

Use a pure merge decision for empty/equivalent/different fields and explicit replace action; ensure result-time comparison with current draft. Dedicated read changes only Walmart metadata. Combined read performs existing merge plus safe link merge. Handle pending/dismissal/generation tokens and photo memory cleanup. Keep no-backend/manual flows working. Add tests for every state and regression before repairing any discovered bug. Render actual candidate widgets for A5; supply capture hashes/sizes/theme/text scale and exact SHA.

### T3 v1 — integrated verification (Astra deterministic checks)

Requires T1/T2. All A1–A6. Review diff and execute actual format/analysis/full Flutter tests, relevant gallery, Deno type/lint/test commands from current CI, existing Walmart export tests and targeted lifecycle tests. Capture exit codes directly. Record skip counts and scope. Schema CI remains required; this feature must not create or modify migration history. Any local database checks use owned disposable state, never reset a household database.

### T4 v1 — independent reviews (Opus security; vision Sonnet/Opus UX)

Requires exact candidate and T3 evidence. Read-only role. Review prompt explicitly includes authorship independence, SHA, contract version and limits. Security: link confusion, prompt injection, forged/malformed AI output, budget/auth routing, transient image lifecycle and late-result corruption. UX: view actual rendered captures and native flow evidence for success, conflict, no-link, error/retry, small/large text and dark mode. Findings cite reproducible locations/behavior, severity and acceptance impact. Astra requires failing regression then bounded repair and affected re-review. No review summary substitutes for visual inspection or passing checks.

### T5 v1 — delivery and live extraction (Astra)

Requires M2 and real dependency/authority clearance. Amend relevant HEARTH_SPEC sections and durable result records. Follow repository branch/draft PR/review/CI flow; apply the explicit qualified merge rule described in PLAN. Stack against #110 while pending and retarget only after dependency merge. Before deployment, verify linked Supabase identity and predecessor function. Deploy backward-compatible server first only when authorized dependency gates pass, then run the bounded A7 synthetic read matrix. Inspect exact IDs, output preservation, timing and budget results. Observe errors; rollback only the owned function release to previous accepted source if required. No database/down migration or device reinstall.

Evidence names actual provider/session, command timestamps/exits, candidate SHA, input/output hashes, tests/captures/review dispositions, PR/CI/deployment identifiers, coverage and remaining gates. Definition of done requires A1–A7 plus permitted delivery; pending native/live/dependency work is reported as unfinished. Initial plan approval is the only approval requested for this feature's defined execution scope; do not repeat it for routine implementation/review actions.
