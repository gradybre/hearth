# Package quantities and nutrition — implementation checkpoint

Approved plan v2. Branch: `fix/package-quantity-nutrition`. Client merge/install is outside the approved delivery boundary.

Implemented package-aware ounce display, a per-food Weight display choice, lossless unchanged quantity editing, reviewed package-to-nutrition conversion, manual and combined two-photo input, stale-evidence handling, compatible food sync, and frozen nutrition qualifiers. A planned/repeated portion now retains the selected serving so 30 oz remains six label servings instead of changing to six default servings.

## Acceptance evidence

| Acceptance | Evidence and current limit |
|---|---|
| A1 — units/precision | Red/green domain regressions; unchanged canonical math, permutation-stable hints, oz/lb overrides and metric controls. |
| A2 — preference persistence | Food mapper/draft/merge/sync tests; real SQLite round trips; new v29 schema. Historical snapshots v25–v28 and interrupted-upgrade fixtures v1–v28 are distinct tests. |
| A3 — surfaces/shopping | Recipe/cook step tests, source-contribution rebuild and export adapter tests, real shopping amount-sheet tests including untouched null override and cross-kind on-hand. |
| A4 — visual/native | 59 gallery scenes pass, including light/dark, phone/desktop, 320 px at 200% text. Independent image review passes within its stated scope. Native macOS fixture builds/launches, but interaction is blocked by the locked Mac. iOS/Windows and physical camera runtime not verified. |
| A5 — conversion | 10 oz / two 1-cup servings => 5 oz/cup; 30 oz => six servings. Selected-row macros and nullable nutrients, direct-density precedence, malformed/stale/approximate relationships, plan/reopen/log/repeat and frozen-history tests. |
| A6 — lifecycle | Manual confirm/save/reopen, partial draft, explicit clear/omission, source/provenance, Unicode/size bounds and selected-serving persistence. Disposable SQL replay validates additive schema and old/new-client semantics. |
| A7 — photos | Both slots, one request, roles, previews, partial/manual/retry/cancel/disposal and adapter/server guards tested. Synthetic fixture photos are committed. Live deployed two-photo extraction is pending deployment; mocked extraction is not counted as live evidence. |

## Gate status

- Domain, editor, persistence, shopping, logging and scan focused checks pass.
- All 45 SQL migrations replayed in an owned disposable database; existing schema guards plus package/selected-serving tests pass. Existing household data was not reset.
- TypeScript type checks, lint and 78 Deno tests (76 steps) pass.
- Flutter analysis: clean. Full Flutter suite: **3,717 passed, 81 skipped**, exit 0 (89.58 seconds). Independent final Opus review reports no blocking regression in the repaired scope. Native macOS synthetic fixture rebuilt successfully against the final source; interaction remains blocked.
- Native walkthrough: blocked by Mac lock. Unlock request is pending; no waiver inferred.
- Hosted migrations/function and real two-photo read: **not deployed/not run**. Required release order and native gate remain in force.
- Draft PR: [#110](https://github.com/gradybre/hearth/pull/110). GitHub CI was started on the pushed candidate; its current checks are authoritative. The PR stays draft while native/deployment/live-photo gates are pending.

M1/M2 implementation checks are accepted locally. M3/M4 remain incomplete until the native and delivery gates are satisfied. A draft PR is a review checkpoint, not a release.

## Evidence records

[Review dispositions](REVIEW-DISPOSITION.md), individual independent reports, [session identities](evidence/sessions.json), [capture manifest](evidence/captures.json), and synthetic screenshots in `evidence/screens/`. Private command logs and full frozen worker packets remain under the owned run directory; no credentials or household data are included here.
