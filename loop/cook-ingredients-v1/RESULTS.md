# Cooking ingredient readability — result

Implemented on `cook-ingredient-readability`, [PR #108](https://github.com/gradybre/hearth/pull/108). Final ingredient size: **22 logical pixels**, retained after two independent reviews of actual Flutter captures and Astra inspection. Ingredients read clearly beneath the 26-point directions without competing with them; the 18-point heading and action labels maintain hierarchy. This fulfills Brendan's approval condition to evaluate the proposed size during implementation.

## Delivered behavior

Each matched ingredient gets a wrapping quantity-first row in a warm “For this step” panel below the directions. The panel shares the existing 560-point reading width, with 16-point padding, 8-point row gaps and 24 points between instructions and panel. No matches means no panel or extra gap. Compact ingredient strips remain unchanged in recipe details and All steps. The existing matching and scaled quantity logic remains the only source of displayed amounts.

Short content stays centered, with actions below. On short screens or at large text settings, the ingredients and cooking actions share a scroll area. Timer controls grow and wrap; Back/Next move their icons above the labels when necessary so words remain whole. Ingredient semantics are exposed separately from the instruction/advance node.

## Evidence

- Formatting: 531 files checked, unchanged; analysis: no issues.
- Full suite: 3,440 passed, 62 opt-in tests skipped, exit 0. The final additional interaction test was subsequently checked in the 20-test focused layout suite; production source is unchanged from the full-suite run.
- Existing cooking/matching/scaling and new layout suite: 79 passed; final layout suite: 20 passed.
- Gallery rendering: 40 passed, including all seven new cooking scenes.
- Regression evidence: panel assertion fails against old UI; old timer controls overflow at 2×/3×; whole-word navigation check fails before the Wrap repair. Each is green after repair.
- Matrix: 320×568, 390×844 and 1280×800 at 1×, 2× and 3×; last ingredient reached, timer started and Mark done tapped without overflow. Synthetic recipes only.
- Native macOS build and fixture process startup succeeded. Interactive native walkthrough remains pending because Computer Use reported the Mac locked. No iPhone/Windows device pass or installed phone update is claimed.
- CI results are attached to the PR; consult the current head's checks rather than inferring CI from local success.

Before and final screenshots are in [images](images/); [capture-manifest.json](capture-manifest.json) binds them to the reviewed production candidate. [verification.json](verification.json) records commands/outcomes, exact provider/session identities and recovery. [reviews.json](reviews.json) retains the independent review reports.

## Review dispositions

Both image-backed UX reviews accepted 22-point rows. Astra also reviewed light/dark, desktop, 2×/3× and long-list captures. The initial 3× navigation image exposed split words despite passing overflow checks; a failing whole-word regression and Wrap repair addressed it before final visual review.

Code/security review found no changes to trust boundaries, storage, network, matching or scaling. Findings were dispositioned as follows:

1. The reviewer questioned whether static ingredient semantics should also offer tap-to-advance. Accepted as deliberate: ingredients are readable information nodes; the explicitly labeled instruction action and persistent Next control provide advance to assistive technology. Adding advance actions to every quantity would increase accidental navigation and repeated control announcements. No accessibility action is removed from the existing labeled step/Next controls.
2. The reviewer requested a three-step case proving nested timer/Mark done taps never skip a step. Added and passed: start timer stays on step 1; Mark done lands on step 2 with its own garlic amount and two-minute timer, never step 3.
3. Existing full-width action controls outside the reading-width limit are preserved. The limit applies to directions/panel, not the controls.
4. The adaptive layout thresholds are implementation choices; required screen/text-size behavior is tested rather than pinning a heuristic.

## Delivery and manual handoff

No backend or dependency changes, migration, paid service or new deployment target. Controller/model processes are stopped; no unattended schedule was created. The native preview uses in-memory synthetic data and should be closed when its pending walkthrough is complete.

Repository policy (`docs/ORCHESTRATION.md`, declaration blocks) leaves this PR for Brendan's merge decision because its `NEGATIVE_TESTS` field truthfully lists regression evidence. No merge or native-device distribution is inferred.

Manual kitchen pass: open a recipe, choose Cook, read the ingredient amounts at normal counter distance, advance through several steps, then try a recipe scaled to 2×. On a small screen with larger text, scroll through the ingredients and start/complete a timer step. Confirm that the final 22-point size feels comfortable on the device actually used for cooking.
