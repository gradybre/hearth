# Hearth readable cooking directions — plan v1

Plan: P-HEARTH-COOK-002. Status: proposed, awaiting approval of this concrete design.
Baseline: 0ad6d3a5d2119771198d7632d67de15df9c8be5a, clean main at discovery.
User request: the top of the cooking screen is a single poorly formatted paragraph; create a cleaner, readable design applying to every recipe.
Reference: user-supplied chili screenshot in this conversation. No household recipe query required.

## Design and behavior

R1: Replace centered focused-step prose with a left-aligned reading column, max width 560 logical pixels. Align directions and the existing ingredient panel. Anchor short content to the top instead of vertically centering it. Keep 16-point side padding; review within 16–24 points.
R2: Use one compact progress label (Step X of Y, preserving done count), aligned with the content. Remove the large duplicate step numeral from focused cards. Retain recipe title and existing toolbar actions. Do not add guessed step titles.
R3: Display the stored directions as spaced reading blocks, preserving words, punctuation and order. Start at 24-point body type, line height 1.4–1.45, paragraph gap 16–20; review against 26-point alternative and retain within 24–26 after actual Flutter visual review. Keep full accessibility scaling. Existing ingredient rows remain 22 points.
R4: Apply a shared deterministic presentation formatter to every focused recipe step, including saved and imported recipes, without writing altered directions to storage. Respect authored paragraph/list breaks. Conservatively split prose at clear sentence-ending punctuation; avoid unit abbreviations (tsp., tbsp., oz., lb., min., hr.), approx., e.g., i.e., initials/acronyms, decimals, ratios, ranges, ellipses and quoted punctuation errors. Prefer a longer block where a boundary is uncertain. Keep a single sentence as a single block. Never split at commas, rewrite/summarize, invent labels such as Note, hide content, or introduce extra cooking steps. This formatter is not a complete linguistic parser; alignment and wrapping improve even an unsplit sentence.
R5: Preserve session snapshot, matching/scaling, timers, Mark done, Back/Next, tap advance and keep-awake. Keep existing recipe details and compact All steps presentation. No DB/API/schema/dependency changes. Empty recipe behavior unchanged; whitespace-only text must not crash or create phantom steps.
R6: Screen readers receive the full original instruction once with the existing advance action. Ingredients and cooking controls remain separately reachable. Scrolling never advances. At small sizes/large text, all instructions, ingredients and actions remain reachable; navigation stays usable. Step changes start the new content at its top.

## Example

The screenshot's first step becomes three left-aligned paragraphs, unchanged in wording: Heat 1 tbsp…medium-high heat. / Add 2 lb…about 6-8 minutes. / There's very little fat…rendering fat. These remain one step, with the existing six-minute timer and one Mark done action. The explanation stays full-size instead of being classified or demoted automatically.

## Acceptance and evidence

A1/R1–R3: Actual Flutter images of the supplied chili wording, a short instruction, a long unpunctuated sentence and eight-ingredient recipe. Check 390×844 light/dark, 320×568 at 1×/2×/3×, 1280×800, before/after scrolling. Independently compare 24/26 type and record the size decision against 22-point ingredients. No cutoff, shrinking or horizontal overflow.
A2/R4: Regression-first pure formatting tests with exact non-whitespace character preservation, ordered full text, existing multiline/bullets, CRLF, units, temperatures, decimals, fractions, ratios, abbreviations, ellipses, quotations, mixed punctuation, Unicode, empty input. Assert the screenshot splits into three blocks. Uncertain prose falls back without loss. Linear scan or bounded regex only, no network/model call.
A3/R5–R6: Existing cook, scaled-quantity and ingredient layout suites; tests for instruction advance, timer start staying on current step, completion advancing once, step scroll reset, original semantics and reachability at large type with a running timer.
A4: Formatting, analysis, full Flutter suite and render gallery exit zero. Independent Claude code/security review and separate image-backed visual review; Astra disposition and actual native walkthrough. Prior completed feature's tests remain mandatory regressions.
A5: PR checks green, merged under the user's established review/merge authority, signed iOS release updated in place on the same connected iPhone and launch confirmed. Record install versus visual device verification accurately. No backend deploy needed. Rollback through reviewed revert and previous signed build, without uninstalling/data deletion.

## Tools, authority and risk

Use existing Flutter 3.47.1/Dart 3.13.1, local config (never print values), gh, subscription-backed Claude through the supported loop controller, existing render fixtures and CUA for native inspection. iOS signing/device installation were proven in the prior release via flutter build ios and devicectl. Recheck availability at execution. No new purchases, connector, API spend or infrastructure. New product changes await this plan approval; ordinary bounded visual choices are delegated to Astra thereafter. Existing explicit merge/direct-iPhone deployment instruction carries forward for this improvement once gates pass.

Prototype: cook-directions-preview.html in the current Codex task workspace; illustrative HTML, not Flutter validation. Desktop preview does not establish Windows or iPhone visual correctness. The device screenshot establishes the defect; synthetic copies of its text suffice for tests. Primary risks are incorrect sentence boundaries and vertical growth; preserve text, conservative fallback and scrolling are required mitigations.
