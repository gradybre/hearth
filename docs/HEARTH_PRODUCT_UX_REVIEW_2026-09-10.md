# Hearth — Product, UI, and UX Review and Improvement Plan

**Date:** September 10, 2026  
**Code reviewed:** `ae57f62` (main, through PR #47)  
**Status:** Review and proposed plan. No application changes, migrations, deployment, or installation performed.  
**Visual evidence:** [Rendered screen gallery](reviews/2026-09-10/index.html)  
**Earlier technical plan:** [Stabilization handoff](HEARTH_STABILIZATION_HANDOFF.md)

## 1. Recommendation

Hearth now has most of the capabilities needed for a serious household nutrition app. The strongest next investment is **a more coherent daily workflow and protection against lost work**, followed by a few targeted additions. It does not need another broad redesign or a larger collection of AI features.

The current cream/cocoa palette, Fraunces titles, Source Sans body text, restrained accent, and dark theme form a recognizable visual identity. It does **not** look like a generic gradient-heavy AI dashboard. It does sometimes look like separately implemented features assembled into one application: too many equally weighted cards, verbose helper copy, inconsistent action placement, and phone layouts stretched onto desktop. These are fixable through editing and hierarchy rather than added decoration.

### Recommended order

1. Protect edits, correct the remaining shopping/import failure paths, and finish the operational safeguards already planned.
2. Make logging, restaurant selection, and shopping faster and easier to understand.
3. Consolidate visual patterns, simplify Settings, and give desktop a deliberate layout.
4. Add a small number of practical features: single-entry move/copy, draft recovery, restaurant shortcuts, and food-data maintenance.
5. Validate the result with a two-week household replacement trial before expanding beyond Nutrition.

This document proposes behavior and acceptance criteria. It is not blanket approval to implement every feature below. Items marked **new scope** or **previously deferred** require Brendan's approval before implementation and corresponding spec amendments. Existing features should be preserved unless an explicitly approved design change replaces their presentation.

## 2. What was examined and what the evidence means

- Read the current application/spec and changes since the previous review, including the planner, recipe/food editors and lists, restaurant builder, import, shopping, Settings, recovery, synchronization, theme, and CI.
- Rendered the actual Flutter widgets with synthetic data at 390×844, with top/bottom safe-area insets, bundled text and icon fonts, and normal shadows. Examined light and dark Today and a 1280×900 recipe library as well as representative phone screens. These are test renders, not photographs of the installed app.
- Inspected 16 saved screen states across 14 render scenarios, including the logging picker and selected-food confirmation. The selected-food capture was separately rerun after correcting an off-screen test tap. Layouts use real widgets; test fixtures and backend-disabled states are explicitly not production data.
- `flutter analyze`: exit 0, no issues.
- Full existing suite: **2,424 passed, 22 skipped**, exit 0. These results supersede the previous review's test count. No live-service tests were forced on.
- Two separate regression probes failed at the intended assertions: recipe Cancel loses modified work without a choice; shopping Undo resets an unrelated checked item. Those failures were outside the normal suite and did not change application code.
- Render harness setup errors (font/shadow bookkeeping, fixture constructor requirements, and an attempted duplicate provider override) were corrected and are not application defects.

**Limits:** no production data was read or changed; no live paid AI calls, real cart writes, real password-reset emails, two-phone convergence test, VoiceOver session, or Windows native interaction was performed. The gallery's Week uses an intentionally empty weekly fixture; its zero totals must not be interpreted as a day/week calculation defect. The restaurant fixture tests layout only, not official menu ordering/nutrition. Recipe rows without nutrition are intentional incomplete examples. AI icons and real recipe photography were not supplied in the render fixture, so icon-generation quality needs a separate real-library sample.

## 3. Progress since the earlier review

Do not implement the previous plan again without checking what is already present. Commit history and current code show substantial progress:

| Area from the earlier review | Current assessment |
|---|---|
| Fractional nutrient editing | Parser round-trip repair implemented in #13; existing suite passes |
| Frozen-log Undo and portion correction | Exact restore in #14 and frozen-basis correction in #31 are present |
| Minor-nutrient completeness | Coverage model and propagation implemented in #15; keep them during UI changes |
| Paginated sync, scoped checkpoints, remote deletions, stale writes | Implementations in #16–22 and follow-up #37/#39; do not infer two-device production verification from this alone |
| Shopping dates and saved range | Implemented in #23 |
| AI shopping edits | Safer application in #24; ordinary swipe-delete Undo still restores a whole list and needs a separate fix |
| Large-text logging | Scrollable confirmation and broader sweeps in #25–27/#35/#40 |
| Compact Today, serving selection, visible portion edit | Implemented in #28–30; further polish proposed below, not a reimplementation |
| Today startup, restaurant logging context, Add recipe menu, Home state | Implemented in #32–36 |
| PDF page coverage | Implemented in #41, but page-success bookkeeping and multi-batch uncertainty need hardening |
| Export contents/manifest | Improved in #42; do not continue describing the old export as unchanged or assume a restore feature exists |
| URL fetching and Edge validation | Guard and Deno checks/tests added in #43; this pass did not redo a complete network-security audit |
| Password recovery | In-app screen/session gate in #44; hosted activation and Windows handler remain outstanding in setup documentation |
| Secret scanning, sync diagnostics, replayable upgrades | Added in #45–47; native release coverage and operator verification remain separate |
| AI budget guarantee | Still best-effort/fails open on unavailable accounting; earlier B02 is not complete |
| Reconnect retry | In-flight rerun is handled by `SyncGate`; automatic foreground reconnect/backoff is still absent |
| Main spec consistency | Still carries stale pre-build text and contradictions; reconcile as part of delivery |

## 4. Current feature assessment

| Product area | What is already useful | Main remaining gap or improvement |
|---|---|---|
| Home and navigation | Built-section registry, Home exit, Today launch choice, returning to last section tab | Home is mostly a gateway while only Nutrition exists; Settings entry is inconsistent; additional chrome consumes phone space |
| Daily logging | Plan/eaten states, recent logging, saved-serving choices, frozen nutrition, portion edit, backdating | Amount entry remains a multiplier of a serving, frequent foods compete with the recipe list, meal actions lack Move/Copy |
| Week planning | Day selection strip, selected-day detail, aggregate totals, copy-day, assignment across days, templates | Week's first screen is primarily another large day dashboard, not an efficient seven-day comparison |
| Recipes | Sections, live matching, scaling, collections, favourites, duplicate, photos/icons, cook-along | Unsaved edits can be lost; editor repeats raw input and parsed output; nutrition gaps deserve a repair workflow |
| Food library | Search, lookup/barcode, label capture, manual foods, default matches, restaurant foods, attention filter | Global restaurant catalog crowds personal foods; stacked FABs remain; duplicate warning offers no merge/reuse path |
| Restaurants | Seeded/imported menus, section grouping, multi-pick, published modifiers and component removal, recipes usable in plans | No menu search/jump control; no immediate selected-items summary; existing saved orders not surfaced in the builder |
| Imports | URL/images/PDF/text through review; later PDF batches and coverage disclosure | Durable drafts, per-batch uncertainty, successful-extraction tracking, and atomic/retry-safe batch save are incomplete |
| Shopping | Date range, recipe aggregation, manual lines, seasoning toggle, wanted/on-hand quantities, store grouping/order, export, AI edits | Whole-list Undo can overwrite work; setup dominates the trip; checked-item management and trip progress need refinement |
| Settings/account | Theme/launch preferences, profile, household joining, recovery screen, sync diagnostics, export | A long page exposes every option at once; units and household lifecycle are incomplete; production recovery requires verification |
| Offline/data trust | Local database/outbox, sync pagination/deletions/checkpoints, history protection, export manifest | Reconnect behavior, pending-save communication, complete recovery/release checks, and backup restoration remain important |
| Accessibility | Tokens, semantics tests, large-text sweeps, operable controls, dark mode | Full real-device keyboard/screen-reader journeys and restrained error/status announcements still need manual evidence |

The food-profile form exists; it is not the full adaptive questionnaire described in the old spec. Do not label it as a completed learning system. Likewise, local structured export is not a tested full backup-and-restore service.

## 5. Current defects and reliability gaps

### F01 — Modified drafts can be discarded without warning

**Priority:** P1 for lost work. **Evidence:** recipe Cancel reproduced; food Cancel has the same inspected path.  
**Files:** `lib/features/recipes/recipe_editor_screen.dart:769`, `lib/features/foods/food_editor_screen.dart:266`.

Open a recipe, change its title, and tap Cancel: the route closes without a discard choice. Both editors keep their work in widget/controller state and there is no equivalent dirty-state navigation guard in these screens. A local recipe-generation conversation is also explicitly session-only; terminating the app loses it.

**Plan:** first add a dirty-state guard for Cancel, Back, system back, and desktop navigation. Offer Keep editing / Discard; a clean editor exits immediately. Then introduce a separate local draft record for crash/restart recovery, scoped to the signed-in user and originating recipe/version. Draft recovery must never silently write a reviewed recipe into the shared library. Prevent a draft restored after a partner edit from overwriting that newer recipe without a comparison/decision.

**Acceptance:** recipe and food modifications survive cancellation of the discard dialog; deliberate discard removes only that draft; restart offers Restore/Discard; failed save retains fields; successful save clears the draft only after local commit. Imported/AI-generated content stays uncommitted until the user saves. Test rapid field changes, in-flight save, account switch, and source-version changes.

### F02 — Shopping Undo reverses unrelated later actions

**Priority:** P1 for losing shopping changes. **Evidence:** reproduced.  
**Files:** `lib/features/shopping/shopping_screen.dart:159`, `:245`.

Delete beef, tick rice, then Undo the beef deletion. Rice becomes unchecked. `_restore` writes the whole previous list rather than restoring only the deleted line. The more recent AI-operation fix did not eliminate this ordinary deletion path.

**Plan:** make delete Undo a targeted repository operation carrying stable list/item identity and position anchors. Restore only the deleted item; preserve subsequent checks, quantities, new items, reorders, and partner changes. Avoid whole-list replacement for delayed actions. If the same item was recreated or edited, reconcile explicitly instead of duplicating it.

**Acceptance:** Delete A → edit/check B → Undo restores A and leaves B intact; order restored relative to surviving neighbours; rebuilt/new list is not overwritten by an old Undo; repeated Undo is idempotent. Cover deletion from swipe and amount sheet, plus delayed remote updates.

### F03 — PDF coverage marks rendered pages as read before extraction succeeds

**Priority:** P2. **Evidence:** source-confirmed sequence, not a live provider test.  
**File:** `lib/features/foods/menu_import_screen.dart:200–231` and `_read`.

`_pagesRead` is updated after rendering, before `reader.read(images)` succeeds. If the model/network call then fails, subsequent batch selection can step past pages whose rows were never extracted. The UI's “read” claim is stronger than the work completed.

**Plan:** distinguish selected, rendered, extracted, and accepted states. Advance extracted-page coverage only after a valid result has been appended to the review. Failed extraction leaves that batch retryable; cancellation does not consume pages or clear prior work. Retain a request identity to avoid duplicate appends.

**Acceptance:** render succeeds → extraction fails → same pages remain next/retryable and no successful-coverage label appears; successful retry appends once; later batches remain reachable; partial render names failed pages independently.

### F04 — Multi-batch import drops earlier uncertainty and saves rows individually

**Priority:** P2. **Evidence:** source inspection.  
**File:** `lib/features/foods/menu_import_screen.dart:110–133`, `:242–279`.

The next extraction appends rows but replaces the uncertainty list with only the newest batch's doubts. The final save loops through rows with fresh IDs and independent repository transactions. A mid-save failure can leave some rows saved and a retry can create duplicates.

**Plan:** model review batches with persistent local row IDs, source pages, and per-row uncertainty. Resolve or retain each warning explicitly. Add transactional batch save/outbox enqueue with stable IDs; if a batch is too large for one local operation, implement resumable idempotent commit with a progress manifest. Do not treat “all extracted rows parsed” as proof all uncertain cells were resolved.

**Acceptance:** a page-one warning remains visible after reading page two; manual corrections survive the next batch; failure at row N leaves either zero committed rows or an exact retry-safe partial manifest; retry creates no duplicate foods. All writes remain after human review.

### F05 — Historical day header contains a misleading “Today” card label

**Priority:** P2 for clarity. **Evidence:** source inspection.  
**File:** `lib/features/plan/day_screen.dart`, `_RemainingCard` uses a constant `Today`.

The page date changes, but the nutrition card still says Today. `_DayHeader` also derives relative labels with elapsed `difference(...).inDays`, which is not reliable across 23-hour calendar days.

**Plan:** label the card “Daily totals” or omit its duplicate title; derive Today/Yesterday/Tomorrow from calendar dates. Always keep the selected date/slot visible in logging confirmation, especially when backdating.

**Acceptance:** yesterday, tomorrow, DST transitions, month/year boundaries, and midnight resume never imply a different date from the actual destination. No blanket reset of a deliberately selected historical date when the app resumes.

### F06 — Portions are improved but still ask users to do unnecessary arithmetic

**Priority:** P2 usability. **Evidence:** rendered confirmation and current conversion code.  
**File:** `lib/features/plan/log_sheet.dart`, `_displayCount`, `_enterableServings`, `_PortionStepper`.

A food defined as a 170 g serving presents “Serving: 170 g” and “Portion: 1.” Alternate stored servings can be selected, but eating 125 g still requires entering a fraction of a serving unless that precise basis is provided. This is a partial implementation of the earlier actual-unit goal, not a missing serving selector.

**Plan:** support `Amount [125] [g]` as well as `Servings [1] [170 g serving]`. Convert against known same-kind units and explicit serving equivalences; never infer density or package mass. Show the resolved portion in the logged row and frozen snapshot. Recipe portions stay servings-based until a measured yield exists.

**Acceptance:** a 170 g/100 kcal serving logged as 85 g freezes 50 kcal; switching g/oz/serving retains equivalent quantity; unknown conversions are unavailable with explanation; invalid/zero/negative consumption is rejected; correction of a past log uses its frozen basis.

### F07 — Operational follow-through remains incomplete

**Priority:** P2 before a dependable household trial. **Evidence:** current source and setup docs, not new production tests.

- `lib/app/sync_controller.dart` now handles a nudge during an active pass, but still has no connectivity-triggered retry or bounded transient-failure backoff. Keep that distinction; the old dropped-nudge defect was addressed.
- `recipe-ai/index.ts:1184` still turns an unavailable spending counter into zero. Atomic budget reservation/settlement from the earlier plan is not implemented.
- `docs/SUPABASE_SETUP.md:218–288` explicitly identifies production recovery activation/email verification as unfinished and Windows protocol registration as absent. An implemented recovery screen does not prove a working delivered email journey.
- CI now includes Edge Function checks and secret tests. It still does not establish native builds, signed installation, real notifications, real screen-reader behavior, or actual multi-device convergence.

**Plan:** finish the existing WP2/WP6/WP7/WP8 release gates from the prior handoff, scoped to remaining work. Add visible, quiet pending-save/retry feedback near daily tasks. Show “Synced” only when relevant work is acknowledged; do not turn every background retry into a snackbar. Do not require an AI connection to log manually.

## 6. UI assessment: keep the identity, reduce competing elements

The following are design judgments informed by the rendered screens, not objective claims that one aesthetic is mandatory.

### 6.1 What works

- The palette has a clear warm identity. Dark mode belongs to the same design system rather than being an inverted afterthought.
- Fraunces provides character; Source Sans keeps forms and figures readable. Retain both and bundled offline fonts.
- The recipe reader gives ingredients and directions priority, without a large decorative hero when no photograph exists.
- The new labelled Add recipe control is clearer than the old stack of creation buttons.
- The compact day view now exposes meal rows on a normal phone. Keep the existing expanded rings and minor bars available.
- The home screen avoids pretending unbuilt sections work. Keep that honesty.

### 6.2 What makes it feel assembled rather than fully designed

1. **Too many headings of similar strength.** In Plan there is Home/Nutrition, Day/Week, Today/date, Today again, then Breakfast/Lunch. Remove duplicated identity and give one clear title per view. Keep the route out of Nutrition without making every title feel like a new screen.
2. **A card for nearly everything.** The same bordered rounded container is used for summaries, items, options, and explanations. Group related content once, use dividers for rows, and reserve elevated cards for meaningful summaries/selections. Preserve legible contrast rather than flattening every affordance.
3. **Long horizontal chip rails.** Recipes has sort, favourites, restaurant, time, nutrient thresholds, tags, and collections competing in one strip. Keep 2–3 common controls visible, add `Filters (n)`, and show removable applied filters below. Keep existing filtering capabilities.
4. **Too much instructional prose.** Settings explains every theme and startup choice; routine rows repeat “tap to log / tap to undo”; Shopping ends with “Nothing leaves the app until you tap that.” Keep important privacy/consent information at the relevant action, but remove repeated narration once the interface is self-explanatory.
5. **Everyday tools and occasional setup have similar prominence.** Shopping's large date/setup card and Build button precede the actual shopping task. Put current range in a compact header; settings and rebuild live behind Manage list once a list exists.
6. **Different conventions across sibling screens.** Recipes has one Add menu; Foods still has several floating buttons, including an obscure seasoning icon. Standardize creation patterns and move maintenance to labelled menus.
7. **Desktop is underused.** The recipe list stretches a short title and a few numbers across roughly a thousand pixels; the sidebar floats around the vertical center. Anchor navigation near the top and use a bounded reading width or intentional list/detail layout.

### 6.3 Visual specification for the refinement

**Surfaces:** retain the approved cream background, lighter grouped surfaces, cocoa text, and terracotta action color. Use one border treatment and modest radius per component family; avoid nested bordered cards unless the inner region is independently interactive. No new gradients, glass effects, large decorative blobs, or extra accent palette.

**Typography:** keep serif for page titles and recipe names. Trial a quieter sans treatment for utilitarian labels such as meal slots/settings categories while keeping meaningful hierarchy. Body remains around the existing 16-point scale; do not obtain density by shrinking nutrition metadata further. Use tabular figures for aligned quantities. Prefer `Protein 17 / 150 g` over compressed `Protein 17/150g`.

**Actions:** one primary action per task state. Filled terracotta for Save/Log/Review order; secondary actions use text or outline. Danger styling only for destructive actions. Essential functions need visible labels or conventional accessible icons; tooltips alone are not discoverability on touch.

**Spacing:** retain the existing 4-point family, typically 16-point phone gutters, 8–12-point related spacing, and 24-point section spacing. Adjust individual layouts to content instead of adding blank space to meet an arbitrary “premium” look. Do not compromise 44-point iOS touch targets or existing stricter checks.

**Icons/photos:** keep sketches small, monochrome, and decorative. Use a consistent canvas, inset, stroke range, and optical size; a photograph takes precedence where already specified. Validate a sample of actual generated icons for coherence before changing the generator. Do not add AI art to every empty state or action.

**Copy:** warm but literal. Suggested changes: `Household` icon leading to the whole Settings page → `Settings`; `Paste another menu` → `Add restaurant`; `Ate out` navigation → `Eat out` or `Restaurant meal`; `Take it shopping` → `Share or export list` if the destination really opens export choices. `Build (6)` → `Review meal · 6 items`. Final labels depend on actual destination behavior, not visual preference alone.

## 7. Screen-by-screen UX plan

### 7.1 Today: prioritize the next meal action

**Proposed structure**

```text
Today · Thu 10 Sep                    [Calendar] [More]
[Day | Week]
2,100 kcal left                       100 / 2,200 kcal
Protein …       Carbs …       Fat …
Fibre …         Sodium …      Cholesterol …    [Details]

Breakfast                                  [+ Add]
Greek yogurt · 170 g                  100 kcal  [⋯]
Logged ✓

Lunch                                      [+ Add]
Overnight oats · 1 serving            250 kcal [Log]
```

- Preserve planned/eaten distinction; do not make planned calories look eaten. Keep a compact projected/remaining treatment and disclose incomplete values.
- Put Copy day and target editing in labelled secondary actions; tapping a nutrition card should not be the only way to discover target editing.
- Keep one-tap logging of an unchanged planned item. Make reversal deliberate enough to avoid accidental toggles while scrolling; preserve an accessible action and Undo for actual changes.
- Row overflow adds Move, Copy, Edit portion, and Remove with correct semantics described below.
- If there are no targets, logging remains the primary task; show Set targets as an optional setup action rather than a blocking dashboard.
- Acceptance: at 390×844/1×, summary and first meal content are visible; at large text all controls remain reachable through scrolling; selected date/slot appears in confirmation; a missing food source is labelled unavailable rather than silently presented as a trustworthy zero.

### 7.2 Week: make comparison the primary view

Current Week shows a date strip followed by large selected-day rings and only later aggregate totals. It works as a day selector, but comparing seven days takes repeated selection and scrolling.

- Use seven compact rows on phone: weekday/date, eaten calories vs target, planned projection, protein, and an explicit incomplete/unlogged state. Expand a row or open Day for details; existing rings/minors move into that expansion.
- Distinguish a day with no logs from a day deliberately logged as zero. Week-to-date averages use the correct denominator and disclose missing days; future days are not automatic failures.
- Desktop may use a seven-column meal-planning board beside a concise summary. Do not force seven unreadable columns onto a phone.
- Keep copy-day, multi-day assignment, and week templates; make their actions labelled and contextual.
- This is a presentation refinement. Water, weight, exercise, streaks, and moralized adherence scores stay out.

### 7.3 Logging picker: find familiar food first

- Surface existing Recents/Favourites when available; do not create a second duplicate favourites mechanism. Keep the current search and saved library.
- Offer clear `Recent / Foods / Recipes / Restaurants` modes or equivalent scoped choices without requiring mode changes for a simple search.
- Rank matching personal/household food ahead of the global restaurant catalog on ordinary food logging. Restaurant mode scopes to that restaurant. Do not hide catalog entries completely.
- Keep Scan, Read label, and Manual entry reachable from a miss, with the day/slot retained after creating a food.
- Implement direct amount entry from F06. For multiple additions, consider an optional review basket after the simpler flow is measured; never silently log all checked search results.
- Acceptance: a recent food can be logged with its usual portion without editing; a 125 g portion requires no division; a miss returns to the same meal after save; cancelled lookup loses no logging context.

### 7.4 Recipes: reduce browsing noise and protect editing

- Keep search, favourites, collections, and restaurant recipes. Consolidate optional filters; make active filters obvious and provide Clear filters for a zero-result state.
- Offer comfortable and compact list density only if real-library testing shows a benefit. Avoid adding a toggle purely as another setting.
- Add a `Needs nutrition review` filter reusing existing missing-match/unit/coverage state. Distinguish “no nutrition available” from a known low-calorie result.
- In the editor, trial `Ingredients / Directions / Details` progressive sections with one persistent Save. Raw pasted text remains supported; show parsed nutrition issues as an expandable review area, not an always-duplicated second copy of every ingredient.
- Keep live totals and an actionable “2 items need matching” summary visible near the ingredients section. An error must link to the field, not be cut off in a one-line warning with no way to read it.
- Add F01 guards/drafts before reorganizing the editor. Never autosave AI nutrition directly into the shared recipe.
- On desktop, constrain recipe reading to approximately 680–800 logical pixels; consider list/detail browsing at wider widths only after simple bounded layout is validated.

### 7.5 Foods: personal library first, maintenance explicit

- Use a labelled Add food menu for Scan barcode, Read label, and Enter manually. Put seasoning rules/default-match maintenance in a labelled overflow or settings subpage.
- Add a clear My foods / Restaurant menus scope or equivalent filter with remembered choice. Keep the ordinary food library useful when hundreds of restaurant rows are seeded.
- Use consistent portion labels, nutrient abbreviations, and source badges. Show source detail on demand rather than every available metadata field in every row.
- Provide `Use existing` from the duplicate warning before attempting full merge. A true merge is a separate data operation with serving equivalence and reference tests; see N05.
- Surface unit-display preference in Settings. Proposed choices: As written where available / Metric / Imperial. Store canonical values unchanged; never invent density. The current reviewed Settings/profile do not expose this choice, despite conversion primitives existing.

### 7.6 Restaurants: turn a long list into an ordering tool

- Add search within the selected restaurant and section jump controls. Retain source ordering and groups; the fixture's arbitrary category ordering is not evidence that the real Chipotle seed is wrong.
- Add a sticky, accessible summary: selected count, known nutrition total/partial state, and Review meal. A selected-items view should be reachable without scrolling the full menu again.
- Show the user's existing restaurant recipes as `Your usual orders`, with Favourite/Recent ordering. Reuse existing recipe IDs and frozen-log rules; no parallel order-storage system is needed.
- Simplify row controls: select/add normally; put `Remove from meal` into a clear selected-item action or an explicit Add/Remove direction choice. Preserve published modifiers, per-column signs, portion limits, and the guard against totals below zero.
- Use `Add restaurant` for the PDF/photo/paste import entry; it is no longer paste-only.
- Before saving, show the meal's selected additions/deductions and portion basis. Continuing from a planned lunch must preserve that date/slot and offer Save and add/log as already implemented.
- Acceptance: finding guacamole does not require traversing 100 Chopt entries; filtering never clears picks; a saved usual order can be reused and adjusted without recreating it; deductions remain visible and reversible.

### 7.7 Shopping: separate preparation from the trip

- Empty/new list: range, Build from plan, Add item are appropriate primary controls.
- Existing list: compact range header, item counts/progress, Add item, and Manage list. Move seasonings/rebuild/range changes into Manage list with a preview of meaningful changes.
- Provide optional “Hide checked” and a collapsed Completed group. Keep checked items recoverable. Show explicit need/have/buy when edited; retain the fast single quantity when unambiguous.
- Clarify check meaning: a checked shopping item can mean acquired/handled, while on-hand is a quantity calculation. Do not secretly change one to the other.
- Preserve user store order and grouping; do not introduce AI-guessed aisle organization, which was previously declined.
- Put export choices behind a precise label and review: copy/share, Walmart search, or cart handoff. A primary button should describe what tapping it actually does.
- Keep optional chat available, but do not let it dominate the shopping list or bypass F02/F04 concurrency guarantees.
- Acceptance: on a populated list at 390×844, useful shopping rows lead the screen; progress updates after a check; pending offline changes remain clear; rebuilding and Undo preserve unrelated edits.

### 7.8 Settings and Home: organize by task

Replace the long expanded Settings form with a concise index:

```text
Settings
Account                 Email · Password
Household               Members · Sharing
Nutrition               Targets · Units · Food profile
Appearance              System
Start screen            Today
Data & sync             Last synced … · Pending …
About                   Version
Sign out
```

- Use subpages or sheets for actual changes; do not display every theme/startup alternative continuously.
- Put a conventional Settings entry on Home and consistently within Nutrition. Keep the old route as an alias; no link migration is necessary just to rename the UI.
- Preserve per-device theme/startup and per-user nutrition privacy. Don't move partner-private information into a household panel.
- Home should stay a simple launcher until another section exists. Offer the existing “Open on Today” preference during a small optional setup step instead of filling Home with invented dashboard metrics or dead feature cards.
- Keep the app-wide timer reachable from Home and all relevant routes. Avoid more metaphorical text explaining rooms/household concepts once navigation is clear.

## 8. Missing features worth considering

Rankings below are recommendations, not authorization. Estimate size as Small / Medium / Large relative to Hearth; they are not promised durations.

| ID | Addition | Value and implementation boundary | Priority / size / scope |
|---|---|---|---|
| N01 | Recoverable local drafts | Protect recipe/food/import work through interruption; separate from published shared data; includes explicit Restore/Discard | Highest / Medium / completes fail-soft intent |
| N02 | Move/copy a single meal entry | Correct a meal logged to the wrong slot/day and reuse one item without copying the whole day | High / Medium / new interaction using existing records |
| N03 | Usual restaurant orders | Surface existing restaurant recipes/favourites from the builder; no new order model | High / Small–Medium / refinement |
| N04 | Recipe nutrition repair queue | Show unresolved matches, incompatible units, and missing coverage with direct fixes; reuses Foods attention concepts | High / Medium / refinement |
| N05 | Food reuse and reviewed merge | Start with Use existing on duplicate warning; later choose surviving food/servings and remap current references while preserving historical snapshots | High / Medium–Large / specified merge gap |
| N06 | Quick add for a one-off meal | Enter a name and known macros directly into a reviewed personal log without cluttering the shared food library; explicit estimated/source label | Medium / Medium / new scope, schema/privacy review |
| N07 | Optional multi-item logging | Select several familiar foods, edit amounts in a review basket, commit together; only after baseline logging is measured | Medium / Medium / new scope |
| N08 | Menu maintenance/provenance | Source URL/document date, import batch, item count, last update; review changes on reimport rather than duplicate a restaurant | Medium / Medium–Large / extends current imports |
| N09 | Full backup/restore | Versioned archive with referenced food definitions and optional private photos; preview, conflict rules, tested rollback; current export stays available | Medium / Large / separate expansion |
| N10 | Household unlink | Complete existing spec: copy shared library and required private storage into solo households, preserve personal history; preview and tests | Important completeness / Large / already specified, not a cosmetic toggle |
| N11 | Optional device app lock | OS biometric/passcode integration consistent with the existing spec, manual fallback and recovery; does not replace server authorization | Context-dependent / Medium / specified but not observed implemented |
| N12 | Lightweight first-use checklist | Add first food/recipe, choose targets, choose start screen; skippable, disappears when complete; no compulsory questionnaire | Medium / Small–Medium / refine onboarding |

**N02 snapshot semantics:** moving an existing eaten entry preserves its snapshot and portion; correct logged timestamp/date attribution deliberately. Copying for a future plan creates a planned entry; repeating a past log must state whether it reuses the frozen eaten portion or current food nutrition. Do not silently choose different meanings in different menus.

**N05 safety:** two foods with similar names may have different servings or macros. A merge must show the difference, preserve or convert compatible serving references explicitly, protect pending writes, and never recalculate old logs. Soft-delete superseded definitions only after their live references are safely handled.

**Do not add now:** whole-week AI generation, sub-recipes, leftovers/batch inventory, ratings, weight/water/exercise dashboards, social features, or new pillars merely to fill Home. These are explicitly deferred or separate product decisions. In particular, “what is left in this batch?” could be useful later but changes the data model and should not slip into a shopping cleanup.

## 9. Implementation packages and acceptance gates

Use small coherent PRs with regression-first changes and the repository's review workflow. Package order is dependency-based; parallel agents are an option only if Brendan requests them.

| Package | Scope | Dependencies | Required proof |
|---|---|---|---|
| P0: Verify remaining scope | Reconcile #13–47, current spec, open work, F01–F07; record intended UI defaults | None | Current baseline and per-finding disposition; no duplicate rebuild of completed features |
| P1: Protect work | F01 dirty guards and draft recovery; F02 targeted shopping Undo | P0 | Reproduced tests now pass; restart/failure/account-switch cases; no silent shared save |
| P2: Import reliability | F03/F04 page states, persistent doubts, transactional/idempotent batch commit | P0; draft interface from P1 | Failed read retries same pages; batch warnings survive; row-N failure/retry creates no duplicates |
| P3: Operational completion | Remaining F07 reconnect/accounting/recovery/native gates | P0 | Local contracts plus documented actual hosted/device verification; no paid calls in routine tests |
| P4: Daily logging and navigation | F05/F06, Today cleanup, picker scopes, N02; consistent Settings access | P1; preserve history contracts | Direct grams conversion; move/copy semantics; wrong-day/DST tests; measured common-meal flow |
| P5: Restaurant ordering | Search/jump, selected-items summary, usual orders, clearer deduction actions, Add restaurant copy | P2/P4 contexts | Large menu, retained picks, reused recipe, signed nutrition and review tests |
| P6: Lists and visual consolidation | Recipe filters, Foods creation menu/scope, shopping trip hierarchy, Settings index; bounded desktop layouts | P4/P5 interfaces | Actual populated/light/dark/large-text/desktop screenshots and operable semantics |
| P7: Data maintenance | N04/N05; N08 if approved | P2/P6; sync contracts | Missing-data repair and reviewed reference-safe reuse/merge/reimport |
| P8: Optional additions | N06/N07/N09/N10/N11/N12 individually approved | Depends on addition | Separate specs where needed; no large mixed-feature PR |
| P9: Household trial | Representative installed build and both users' daily logging | P1–P6 and operational readiness | Two weeks, no lost work, no silent nutrition changes, logging time at least competitive with current tool |

### 9.1 Visual deliverables required before large UI implementation

Prepare populated before/after screen designs for Today, Week, Foods, Restaurants, Shopping, and Settings. Use Hearth's actual fonts/tokens and realistic long labels. Include light/dark, a 390×844 phone, a small phone at enlarged text, and a 1280-wide desktop treatment. A loading screen or empty-state mockup alone is insufficient.

Approval should settle hierarchy/action placement, not each routine padding choice. Keep the existing cream palette by default. Do not change nutritional semantics to make a mockup look simpler.

### 9.2 Engineering gates

- Each reproduced or subsequently confirmed bug gets a failing durable test before its fix. Tests assert preserved data, correct action destination, and recoverability, not just a string or icon.
- Run focused tests and formatting/analyze during a package; full relevant suite and CI at PR boundaries. Don't repeat complete suites without new changes or unresolved evidence.
- Explicitly cover 0/known/unknown/partial nutrients, all serving bases, signed restaurant deductions, frozen logs, scope changes, and pending outbox work across any new data operation.
- Preserve old payload compatibility. If changing schema/RPCs, use additive migrations, historical upgrade tests, RLS policies, hosted push/parity checks under the implementing session's authorization, and a data-preserving rollout.
- New UI error states offer recovery without raw exception dumps. Keep diagnostic details separate from user-facing copy and exclude secrets/health text from unnecessary logs.
- A passed CI job is not a passed real email, cart, camera, notification, keyboard, or two-device test. Record these separately.

### 9.3 Usability measurement

Use the same five meals before and after: a recent food, a weighed food, a planned recipe, a customized restaurant order, and an unplanned meal. Measure completion time, taps, portion corrections, wrong-day/slot errors, and assistance needed. Compare median/p90 task times, not an invented “UX score.”

Proposed acceptance targets for Brendan's approval:

- Recent food: no required search when it is already in recents; no new taps introduced by the redesign.
- Weighed food: direct amount entry with no arithmetic outside the app.
- Planned meal: one deliberate action to log unchanged portion.
- Restaurant: find an item through search/category navigation without scanning the whole menu; usual order reusable.
- Shopping: first useful rows visible on a populated list at ordinary phone text; no unrelated state change from Undo.
- Editing: zero lost work in cancel/restart/save-failure scenarios.
- Accessibility: no blocked primary action at tested enlarged sizes; meaningful focus/VoiceOver output for logging, corrections, and warnings.
- Native performance: inspect profile/release behavior with 500 recipes, 1,000 foods, and a year of logs. Widget-test speed is not a device-performance result.

## 10. Scope choices to approve together

Recommended defaults, rather than repeated implementation questions:

1. Keep the current warm visual identity; reduce repeated cards/headings and helper copy.
2. Keep compact Today and optional expanded nutrient detail; make Week a real seven-day comparison.
3. Introduce direct gram/ounce entry and Move/Copy single meal actions.
4. Make restaurant search, selected-item review, and existing usual orders the next restaurant improvements.
5. Turn Settings into a concise index and separate shopping preparation from in-store use.
6. Complete protection against lost edits and unsafe Undo before visual reorganization.
7. Address import failure bookkeeping and remaining operational gates before declaring the app trial-ready.
8. Approve optional new features individually; do not quietly expand Nutrition or build future pillars.

No visual preference in this review overrides the household's established floor/ceiling nutrient choices, manually set targets, review-before-save, or privacy boundaries. Default nutrient values should be preserved; if their source/copy changes, verify current authoritative guidance instead of treating a general reference value as personalized advice.

## 11. Best-practice basis

The recommendations favor visible actions, clear status, error recovery, and content hierarchy. They do not require copying another app or adopting a new visual fashion.

- [Nielsen Norman Group: usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/) supports visible status, user control, consistency, recognition, and recovery. The concrete judgment about Hearth is based on the source/renders above.
- [NN/g: aesthetic and minimalist design](https://www.nngroup.com/articles/aesthetic-minimalist-design/) distinguishes reducing competing information from merely making a sparse-looking screen. That is why this plan removes repeated explanations while keeping useful nutrition data.
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) emphasizes hierarchy that serves content. Hearth can keep its own cream identity while adopting familiar navigation and actions.
- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) supports retaining repository boundaries and testing components together. There is no evidence-based reason here to replace Riverpod or rewrite the application framework.

## 12. Handoff checklist

- [ ] Brendan approves selected packages/defaults; optional additions are explicitly identified.
- [ ] Implementer rechecks current SHA/open work and marks earlier completed findings accurately.
- [ ] F01/F02 durable regression tests demonstrate current behavior before correction.
- [ ] F03/F04 extraction/commit failure tests reproduce the inspected sequences.
- [ ] Populated before/after visual designs reviewed, including desktop and dark mode.
- [ ] Each PR reports IDs, behavior, tests/exit codes, migrations, and manual gates.
- [ ] Spec wording is reconciled with approved existing behavior; stale “pre-build” claims removed.
- [ ] Hosted/device verification completed or left explicitly pending, never inferred from CI.
- [ ] No app uninstall/cache clearing or historical nutrition recalculation used as a shortcut.
- [ ] Two-week replacement trial evaluated before adding further product breadth.
