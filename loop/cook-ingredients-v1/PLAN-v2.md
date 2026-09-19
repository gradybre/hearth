# Hearth cooking ingredients — plan v2

Status: approved by the user with font-size review feedback; see APPROVAL.md.
Plan ID: P-HEARTH-COOK-001. Mode: feature improvement to existing cook walkthrough.
Baseline: b88fd1069da786be54f8a0ca1f371085b7e1b7bf (clean working tree at inspection).
Repository: /Users/brendan/Developer/hearth; origin https://github.com/gradybre/hearth.git.

## Outcome and design

Make the ingredients for the active cooking step readable at arm's length and easy to scan. The existing focused step shows 26-point directions above a shared 12-point metadata strip with muted text and dot-separated ingredients.

Replace that strip in focused cook mode with a warm, full-width “For this step” panel immediately below the directions. Show each matched ingredient on its own left-aligned line, quantity first, using initially 22 logical pixel ingredient type (final 20–24 after visual review), 1.4 line height and primary text color. Use an 18-point heading, 16-point internal padding, 8-point row gaps, and 24 points between directions and panel. Use existing theme surface, outline and radius tokens. Panel and directions share the existing centered 560-point maximum reading width. Short content remains centered as a group; long content scrolls from its start. Ingredients wrap fully; never truncate or shrink to fit. Keep amount and name together in each row, avoiding a rigid amount column on a small phone.

Scope: the focused step cards reached via Recipes → recipe → Cook. The existing compact component remains the default for recipe details and the All steps view. Ingredients are not sticky above a long instruction: they remain adjacent to it in the same scroll area, avoiding competing scroll regions. The complete Ingredients sheet stays reachable through its existing control.

## Requirements and acceptance

| ID | Required result | Evidence |
|---|---|---|
| R1 / A1 | Focused cards use the panel and initially 22-point ingredient rows, final 20–24 after visual review; normal-scale heading 18 points; spacing as specified above. | Actual Flutter captures, widget geometry/type assertions, Astra visual review. |
| R2 / A2 | Every currently matched quantity/name is shown once, in the same order, using existing reader-friendly quantity formatting and the session's scaled recipe. | Existing cook_scaled and step_ingredients tests; multi-row widget case. |
| R3 / A3 | No panel, heading or reserved panel spacing for zero matched quantified ingredients. | Empty/unmatched case. Matching behavior including omission of unquantified ingredients remains unchanged. |
| R4 / A4 | Fully readable and scrollable at 320×568, 390×844 and 1280×800 logical pixels, text scales 1, 2 and 3; light/dark variants; long names and eight ingredients. No horizontal overflow or clipping; all content/actions reachable. | Widget overflow and scroll-to-content/action checks; actual Flutter captures at representative sizes. |
| R5 / A5 | Screen readers can reach the ingredient names and amounts; instruction and advance action remain understandable without duplicate announcements. Existing button actions remain reachable. | Semantics tests and native accessibility inspection where supported. |
| R6 / A6 | Tap advance, Back/Next, Mark done, session progress, timer controls, keep-awake, all-steps toggle and ingredient sheet keep working. Recipe details and all-steps retain compact presentation. | Existing focused suites, targeted gesture regression and compact rendering check, full suite. |

Exact: content/matching/scaling semantics, panel heading, heading size, public component default behavior, data boundaries.
Bounded: spacing may vary by at most 4 logical pixels after Astra visual review; reading width at most 560; row font 20–24 before accessibility scaling, selected through recorded visual review; no text-scale cap.
Delegated: private widget decomposition, test fixture names, choice of existing warm surface token and semantic node arrangement.
Prohibited: schema, persistence, auth, nutrition, matching algorithm, dependency or global typography changes; new paid services/assets; rewriting recipe directions; changes to unrelated screens.

## Architecture and data

Use StepAmounts with an explicit optional cook presentation (compact default), or a small dedicated cook renderer sharing the existing StepIngredients.forStep and QuantityFormat.format calls. Do not duplicate ingredient matching. _StepCard selects the cooking presentation. Ensure empty matching does not leave the panel gap. Existing Recipe → CookSession snapshot → step/section resolution remains intact. All code stays in the presentation layer; no server, database, storage or API contract changes.

_StepCard currently uses excludeSemantics: true around the entire step. Adjust its semantics as needed so the new ingredient information is actually exposed while preserving the advance action and child controls. Any fixed action height exposed as an overflow by A4 may become a minimum height within this screen; do not weaken the accessibility matrix.

## Discovery and decisions

- D1 confirmed by user: improve per-step ingredient size and placement; Astra owns ordinary design choices within this outcome.
- D2 proposed: dedicated panel below instructions, 22-point rows; no separate mobile/desktop interaction model.
- D3 confirmed by code: shared StepAmounts currently uses 12-point metadata and a 13-point ruler icon; used by recipe details, All steps and focused cards.
- D4 confirmed by code/tests: quantities come from matched ingredients in the scaled session snapshot, including unambiguous cross-section fallback. Preserve exactly.
- D5 scope interpretation: focused “tabs” means one-step-at-a-time cards; other recipe presentation remains compact. No material product question remains beyond initial plan approval.
- D6 source hierarchy: loop skill assigns Astra planning and Claude author/reviewer roles. Current CLAUDE.md and docs/ORCHESTRATION.md govern PR declaration/merge rules; the older ship skill's “never merges” text is superseded by that explicit current policy and newer loop defaults. Do not hide nonempty PR declarations to obtain auto-merge.

## Baseline and tools

Inspected AGENTS.md, CLAUDE.md, relevant HEARTH_SPEC sections 5.2, 6, 9, 10, ORCHESTRATION, ship workflow, cooking code and existing tests. No preexisting product loop plan found in listed project docs.

- Flutter 3.47.1 / Dart 3.13.1 installed, matches CI; no installation or spend needed.
- Baseline command: flutter test test/features/recipes/cook_along_test.dart test/features/recipes/cook_scaled_test.dart test/domain/recipes/step_ingredients_test.dart --reporter compact. Exit 0, 60 passed. Log retained alongside this plan.
- Existing test/render utilities can capture real Flutter widgets using bundled fonts. Capture capability for this cook screen must be configured and demonstrated during approved execution; static HTML controller capture does not prove native Flutter behavior.
- macOS target and a wireless iPhone are detected; Windows native runtime is unavailable on this Mac. Automated viewport coverage does not establish a Windows or iPhone device pass.
- GitHub CLI authenticated; origin configured. PR/CI via existing gh workflow, validate at delivery. No new connector required.
- loopctl doctor: development status, productionReady false, toolWorkersEnabled false. Controlled foreground structured Claude author/reviewer pipeline is available per installed controller documentation. No active Hearth controller has been established; do not launch bootstrap validation fixtures as this product.
- Configure the actual supported project service and bounded file-bundle/check paths after approval. Use subscription-backed Claude Sonnet for this routine implementation and an independent reviewer; record actual resolved IDs. No billed API fallback.

## Quality, reviews and release

Regression-first implementation: add a focused failing readability/layout test before changing the UI. Preserve the 60-test baseline. Run formatting check, flutter analyze, full flutter test and existing gallery rendering. Use synthetic recipe fixtures only for captures, never household data. No new network behavior or sensitive-data handling; independent code/security review verifies scope and unchanged boundaries. Independent visual reviewer must inspect actual candidate Flutter images, followed by Astra acceptance; summaries or HTML mockups are insufficient.

Review representative captures: 390×844 light and dark; 320×568 at 2× and 3×; 1280×800; a long multi-ingredient scroll case before and after scrolling. Include a native macOS runtime walkthrough after build, using fixtures where possible. Report actual native checks separately from widget rendering. Do not claim untested iPhone/Windows behavior.

Release destination: a reviewed GitHub PR against existing main; no new deployment infrastructure or automatic installation on Brendan's phone. Use a dedicated branch/worktree. The PR includes required DEVIATIONS, NEGATIVE_TESTS and BLOCKED fields, factual negative test evidence and CI results. Current repo auto-merge rule applies only when all three declarations are exactly none and every CI check is green; otherwise hand the PR to Brendan. This layout fix is expected to carry regression evidence, so a reviewable PR is an acceptable delivery endpoint under that rule. Native app distribution remains the existing project process; no App Store/TestFlight target is assumed.

Completion: requested visual behavior implemented; regressions and mandatory checks green; independent code/security and image-backed visual reviews resolved; Astra reviews actual evidence; PR delivered with merge status and native validation limits. Provide Brendan a short kitchen-use manual pass checklist. Rollback, if needed: revert this isolated UI change through a reviewed PR; no data rollback necessary.
