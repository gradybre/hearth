# Execution results — P-HEARTH-WALMART-001 v1

Approved by the user, including explicit relevant source/test sharing with subscription Claude. Isolated branch feat/walmart-screenshot is based on PR110 at75c9bb25a72210e00cdcd6b7855b544455483437. No household database was opened, no application AI call was made, no deployment or merge is claimed.

## Runtime and authorship

Astra owns integration and verification. The installed no-tools first-party subscription adapter runs in the foreground; its earlier service run stopped after invalid output. No supervisor is running. Every accepted bundle was confined to allowed paths and checked against base hashes. Development uses Claude subscription authentication; adapter usage estimates are not claims of API billing.

- Validators repair:3aa6a8e5-a67f-46eb-aab6-e44ee35afba9. Regression author:c7497a99-dc42-42df-b8e2-9b9523af8448.
- Backend module:3533416a-370e-46ba-996a-571fc2ef5bd5. Oversized earlier backend packet cancelled, stopped and replaced with smaller packet; no partial source applied.
- Adapter:5c5cde35-41c1-41b3-a5fd-27dcd45a7231.
- Screenshot controller/sheet:f182150c-4e4f-4f55-9709-5a4e46abd987.
- Editor actions:ed1a9938-3a50-449a-a385-80dc419c00bf.
- Independent Opus code/security:390cb296-567f-498a-b098-e09394165d9a.
- Independent image-backed Sonnet UX:57445031-6df7-484e-a08a-b4a395ecc389. Four-image input limit respected; one rejected oversized local packet started no model. Two bounded output-format repairs recovered the review.

Astra provided route/request integration, editor/draft glue, synthetic fixtures, regression/gallery/native harnesses, and verified repairs. Reviews and their dispositions are separate records.

## Evidence

Server121 tests/84steps pass, Deno type check and lint pass. Dart validator51 tests pass. Targeted editor/draft/lifecycle tests pass including link-only preservation/recovery, existing value and manual edit, explicit save, duplicate calls, stale responses, transient image cleanup and size/type guards. Final full Flutter suite:3818 passed,86 opt-in skipped, exit0. Full opt-in gallery:64passed, exit0. Format check579files unchanged; flutter analyze clean. Tracked-file architecture/secret/surface guards24passed. All Deno function entrypoints type-check; lint passes. CI remains to be checked at the PR head.

Actual Flutter gallery covers phone light/dark, desktop1280, 320px at200%/300%, with all controls reached through scrolling. Synthetic screenshots are generated test fixtures. Preview decoding was awaited before capture. All five layouts were recaptured after the UX repairs, and the final follow-up visual review is recorded separately.

Native UI fixture: tool/fixtures/walmart_native.dart uses an in-memory database, no backend, fixed extraction and the actual native photo picker. Missing ignored xcconfig includes were copied from the canonical checkout. Xcode compilation succeeded but signing in Documents failed on inherited Finder metadata. The compiled test bundle was copied with --norsrc to /private/tmp, metadata cleared and ad-hoc signed successfully. The subsequent CUA launch attempt stalled then reported a locked Mac. This does NOT establish native runtime verification. Current edits after that build require a refreshed fixture build before a walkthrough. No iOS/Windows runtime verification is claimed.

## Release gates

PR110 remains OPEN/DRAFT with its three CI checks successful, but its deployment/native/live gates remain separate and unfulfilled. This feature cannot merge or deploy ahead of it. Native macOS walkthrough, dependency clearance and bounded live extraction remain outstanding. No device installation is authorized by this plan.
