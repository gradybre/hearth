# Hearth — Stabilization, Reliability, and Usability Handoff

**Prepared:** 2026-09-05  
**Reviewed baseline:** `7d3ff15` — `Spend the status bar once, not once per SafeArea (#12)`  
**Status:** Proposed implementation plan and supplemental specification; no implementation performed by this document.  
**Audience:** Brendan and the Claude session implementing this work.  
**Companion:** [Paste-in Claude prompt](CLAUDE_STABILIZATION_PROMPT.md)  
**Existing source of truth:** [HEARTH_SPEC.md](HEARTH_SPEC.md), plus the repository's current house rules.

## 1. Purpose, authority, and success

Address every finding and recommendation from the codebase review and the subsequent best-practices review. The objective is dependable daily nutrition logging and household use, followed by improvements that make those tasks easier. Preserve the existing Flutter/Riverpod/Drift/Supabase architecture and the warm cream/cocoa design.

This document distinguishes **observed defects**, **source-inspected risks**, and **proposed product improvements**. Writing this handoff does not authorize code changes, production migrations, a deployment, a merge, or an installation. When Brendan explicitly approves implementation of this plan, the proposed defaults below become the implementation brief; follow the existing delivery rules and any explicit deployment/merge instructions given in that session. Resolve genuine conflicts with HEARTH_SPEC.md by amending the relevant section in the implementing PR, not by silently choosing whichever text is convenient.

The end-state success criterion remains: Brendan and his partner replace MacrosFirst for daily logging for two consecutive weeks. Before that trial, nutrition preservation, complete synchronization, recovery, and critical accessibility checks must pass. New Fitness/Health/house features are outside this plan.

### 1.1 Evidence and limits

At the reviewed baseline:

- `flutter analyze` passed.
- The existing full suite passed: **2,054 tests passed, 20 skipped**, exit code 0.
- Separate temporary probes reproduced seven failures: fractional food nutrition, multi-serving Undo, remote deletion propagation, account-scoped sync recovery, minor-nutrient completeness, large-text log confirmation, and DST range calculation. Those probe failures were expected and did not modify application code.
- A representative day screen was rendered at phone size with the application's text fonts. The summary pushed meal content below the initial viewport. An initial fallback-font artifact was excluded from findings.
- The reviewed checkout already includes PR #12. Do not reopen the earlier status-bar/sidebar/home-timer fixes solely because historical agent reports mention them; inspect current behavior first.
- Production authorization settings, billing limits, real two-phone synchronization, actual password recovery delivery, and manual VoiceOver behavior were not verified. These are explicit validation tasks, not claims of failure or compliance.
- Temporary `/tmp` probes are optional evidence, not a required dependency. Recreate durable regression tests in the repository before each fix. Re-check the baseline because another session may have changed the code.

### 1.2 Severity and evidence vocabulary

- **P1:** corrupts or silently omits user data, changes nutrition, or can leave devices permanently inconsistent. Complete before the trial.
- **P2:** impairs a core task, produces misleading state, or creates a meaningful reliability/security gap. Complete before declaring this program done.
- **P3:** usability or maintainability improvement; implement after core correctness.
- **Reproduced:** demonstrated with an isolated regression probe at the baseline.
- **Inspected:** supported by source inspection; implementation begins with a reproducer or a targeted verification.
- **Proposed:** recommended behavior, not a claim that the old behavior is a bug.

## 2. Complete review inventory

Line numbers in earlier reviews may drift. File paths below are navigation aids, not a substitute for reading current code.

| ID | Priority / evidence | Finding or recommendation | Work package |
|---|---|---|---|
| R01 | P1 / reproduced | Delete → Undo multiplies an already-totalled logged snapshot by servings again | WP1 |
| R02 | P1 / reproduced | Food editor writes friendly fractions but reads them with `double.tryParse`, losing nutrition | WP1 |
| R03 | P1 / reproduced for a meal; other tables inspected | Physical deletions have no corresponding deletion pull for ordinary record tables | WP2 |
| R04 | P1 / inspected | Single-page fetches plus advancing watermarks can permanently skip data beyond the API row cap | WP2 |
| R05 | P1 / reproduced | Sync checkpoints are not scoped to user/household, so switching scope can skip older history | WP2 |
| R06 | P2 / reproduced | Partial minor-nutrient coverage is lost between recipe calculation and day/log totals | WP1 |
| R07 | P2 / reproduced | Selected-item logging confirmation overflows at 3× text; the picker-only sweep misses it | WP4 |
| R08 | P2 / reproduced | Shopping default range uses elapsed hours and loses a calendar day across DST | WP3 |
| R09 | P2 / inspected | Reopening Shopping displays a default date range instead of the saved list's range | WP3 |
| R10 | P2 / inspected | AI shopping response and whole-list Undo can overwrite changes made while or after the request runs | WP3 |
| R11 | P2 / inspected | PDF reader silently uses the first six pages, with no route to later pages or page-failure accounting | WP5 |
| R12 | P2 / inspected | Export omits referenced global foods, minor targets, and week templates while claiming completeness | WP5 |
| R13 | P2 / inspected; hosted destination unknown | Password reset sends mail without a verified complete recovery destination | WP6 |
| R14 | P2 / inspected; exploit not tested | URL fetch accepts arbitrary destinations/redirects and caps bytes only after reading the whole response | WP7 |
| B01 | P2 / inspected | Sync drops requests while running and has no reliable reconnection/failure retry policy | WP2 |
| B02 | P2 / inspected | AI budget fails open when accounting is unavailable; check/spend race and usage-recording gaps remain | WP7 |
| U01 | P3 / proposed | Compact the day summary while retaining expanded rings and minor nutrients | WP4 |
| U02 | P3 / proposed | Offer Today as a direct launch destination | WP4 |
| U03 | P3 / proposed | Log using actual saved serving units instead of only a default-serving multiplier | WP4 |
| U04 | P3 / proposed | Preserve day/slot through restaurant building, saving, and logging | WP4 |
| U05 | P3 / proposed | Replace stacked recipe creation buttons with one labelled Add menu | WP4 |
| U06 | P3 / proposed | Make portion editing visible; retain long-press as a shortcut | WP4 |
| U07 | P2 / proposed | Show local save/sync/attention status where people log, with an actionable retry | WP2, WP4 |
| U08 | P3 / proposed | Preserve last tab, filters, search, and position through Home | WP4 |
| U09 | P2 / proposed | Show import coverage and provenance and distinguish a local export from a complete backup | WP5 |
| Q01 | P3 / inspected | Large mixed-responsibility screens/controllers and repeated manual field mappings increase change risk | WP8 |
| Q02 | P2 / inspected | Test coverage misses cross-layer invariants and complete interactive journeys | All, WP8 |
| Q03 | P2 / inspected | CI lacks Edge Function validation and target-platform build coverage | WP8 |
| Q04 | P3 / inspected | Stale spec text and overconfident code comments contradict current approved behavior | WP0, all |
| Q05 | P2 / validation gap | Hosted/security/native/two-device behavior cannot be established by the passing local suite | WP6–WP9 |

## 3. Constraints that every package must preserve

1. Keep server credentials out of client code, artifacts, fixtures, logs, chat, and commits. The client contains only the publishable Supabase key. Inspect configuration without printing its values.
2. Add RLS and explicit grants/policies with any new server table or RPC. Library data is household-scoped; logs, targets, favorites, and profiles remain user-scoped. Global foods are read-only to ordinary clients.
3. Never repair old nutrition by recalculating frozen logs against today's food or recipe definitions. Historical missing information cannot be invented.
4. Recipes and foods remain soft-deleted. Other entity deletion semantics may change to make sync correct, with compatible migrations.
5. Food/recipe automation retains human review. Shopping remains the editable review surface with visible operations and safe Undo; external cart handoff still requires explicit user action. Decorative SVG icons retain their narrow existing exception and validation.
6. Preserve optional/to-taste exclusions, seasoning behavior, signed restaurant modifiers, component deductions, and the guard against a meal below zero. Do not normalize ingredient-list hyphens into deductions globally.
7. Keep the approved theme and accessible tone rules. Minor nutrients remain nullable, and the calorie/protein/carbohydrate/fat displays keep their existing semantics. No new nutritional targets or personalized medical advice are introduced.
8. Use repository/adaptor boundaries. Do not introduce direct Supabase calls into UI widgets, replace Riverpod, or rewrite the router as an unrelated cleanup.
9. Every defect gets a failing regression test before the fix. Reversible documentation/copy cleanup does not need implementation-mirroring tests.
10. Never reset the hosted database, uninstall the phone app, clear unsynced caches, rewrite applied migrations, or force-push as a repair shortcut. Preserve unrelated changes and other agents' worktrees.

## 4. WP0 — Baseline, evidence, and spec reconciliation

**Goal:** establish exactly what remains and prevent the old spec from undoing newer approved work.

### Required work

- Read the current rules, spec, git status, recent commits, and open PR state. Record the actual reviewed SHA and any overlapping work. Do not treat old background-task notifications as proof of present success.
- Convert the inventory above into a progress checklist. Each ID must end as fixed, verified already resolved, or explicitly deferred by Brendan, with evidence. No disappearing findings.
- Reproduce inspected findings before expanding a fix. If one does not reproduce, document the attempted scenario and reason; do not modify correct code just to match a review.
- Build fixtures for fractional nutrients, non-unit serving logs, partial recipes, two users in separate households, a shared household, a multi-page restaurant guide, and data exceeding a single API page. Use synthetic data and fake credentials only.
- Record the existing baseline tests, skipped live tests, native build availability, and pending migration state without exposing secrets.

### Required spec reconciliations

Update each relevant section in the PR implementing it. Do not rewrite the whole product spec preemptively.

| Existing section | Reconciliation |
|---|---|
| Header / end note | Replace stale “pre-build / phase-1 next” status with an accurate version and implementation status |
| §4, §5.6 | Describe snapshot coverage metadata and retain approved minor targets/bars; remove “Never a target / no progress bars” |
| §5.6 | Keep fibre as a floor and sodium/cholesterol as ceilings; preserve numeric amounts and unit spacing; distinguish reference defaults from personal targets |
| §5.7, §12 | Remove the old “no public Walmart cart API” assertion; document the implemented reviewed cart-link and optional pack-size behavior, verified against current official documentation before changing integration claims |
| §5.7 | Make inclusive seven-calendar-day range and saved-list range ownership explicit; distinguish checked state from on-hand quantity according to current approved behavior |
| §5.0, §6.2 | Add Today launch and session navigation restoration if adopting WP4; preserve existing URLs and only-built-section rules |
| §7.1–7.2 | Document scoped complete sync, deletion behavior, concurrency policy, and bounded reconnect retries; retain no permanent Realtime socket by default |
| §7.4 | State exact export contents, references, exclusions, local completeness, and absence of automatic restore |
| §8.3 | Replace the unfinished password-reset allowance when the working recovery journey exists |
| §3, §8.5 | Define what the AI ceiling actually guarantees and how unavailable accounting/concurrency are handled |
| §8.2, §9.5, §12 | On adoption of this stabilization plan, bring cross-scope negative testing into this hardening stage rather than leaving the test-stage deferral indefinite |
| Rules / §5.2 | Keep the pointer to the explicit decorative-icon exception aligned without extending it to nutrition data |

**Acceptance:** every conflict has an explicit disposition; passing earlier home fixes and approved features are preserved. Missing test secrets or dashboard access become precise operator tasks, not claimed completion.

## 5. WP1 — Nutrition preservation and frozen history

**IDs:** R01, R02, R06. **Run first.**

### 5.1 R02: food draft round-trip correctness

**Starting points:** `lib/features/foods/food_draft.dart`, `lib/domain/parsing/amount_parser.dart`, `test/features/foods/food_draft_test.dart`.

The current writer can turn `0.5` into `1/2`, while `double.tryParse` cannot read the result. Use a single compatible parser/formatter contract for all seven nutrient fields. Reuse the established amount parser where appropriate; do not create a competing fractions implementation.

**Requirements**

- Opening, saving, or renaming a food preserves each serving's nutrition, including decimals, fractions, and nullable minor values.
- Blank optional nutrients remain unknown; explicit zero remains zero. Malformed nonblank input produces an inline validation error instead of silently becoming zero or unknown.
- Reject NaN/infinity. Preserve signed values only where the existing modifier rules permit them. Do not impose a blanket nonnegative rule on published modifiers.
- Friendly display rounding must not alter stored values on an unrelated edit. If the display cannot represent a value exactly, retain the original until the field is intentionally edited or use a lossless editable representation.

**Regression cases:** 0.5, 1.5, 0.25, an ordinary decimal such as 0.7, zero, null, all seven columns, multiple serving rows, a signed modifier row, name-only edit, repeated save/reopen, and invalid nonblank input. Assert values in both the domain model and persisted row, not only rendered strings.

### 5.2 R01: exact Undo restoration

**Starting points:** `lib/features/plan/day_screen.dart` (`_restore`), `lib/data/repositories/plan_repository.dart`, plan snapshot models/mappers, `test/features/plan/day_gestures_test.dart`.

Add a repository-level restore operation with unambiguous semantics. It accepts the original entry and restores its frozen snapshot directly; it does not treat the total as per-serving nutrition or call the ordinary logging path with that total.

**Requirements**

- Restore the logical entry, day/slot, portion, planned/logged status, original logged timestamp, label, and all snapshot fields exactly. A new sync mutation timestamp is separate from the original eating timestamp.
- Restore is idempotent: repeated invocation does not duplicate a meal or enqueue conflicting duplicate logical actions.
- Delete followed by Undo works before and after the deletion reaches the server. Coordinate explicit resurrection/version behavior with WP2; an obsolete queued delete cannot erase the restored entry afterward.
- An unrelated food/recipe edit between Delete and Undo does not change the restored nutrition.

**Regression cases:** 2 servings at 100 kcal each restores 200, 0.5 restores 50, all main/minor values and unknowns remain exact, original timestamp preserved, planned-only entry, already-synced delete, repeat Undo, source changed/deleted after log, and second-device convergence.

**Existing data:** do not guess which historical values were previously doubled or erased. Report the affected code paths and offer review of suspect entries only if reliable evidence exists. No bulk recalculation of history.

### 5.3 R06: carry nutrient completeness with totals

**Starting points:** `RecipeMacros`, `lib/features/plan/entry_resolver.dart`, `lib/domain/planning/day_progress.dart`, snapshot serialization, `lib/app/widgets/minor_nutrient_bars.dart`.

Introduce a small pure-domain representation that carries a nutrient's known sum and its coverage state through recipe calculation, entry resolution, logging, and aggregation. Exact type names are implementation choices. Coverage must distinguish **complete**, **partial**, **unknown**, and **legacy/not recorded**; a nonnull subtotal alone does not establish completeness.

**Requirements**

- A recipe with 5 g known fibre and a second required ingredient with unknown fibre remains a partial 5 g total when planned and logged.
- Planned totals use live coverage; logged totals use frozen coverage. Editing the recipe cannot make yesterday's coverage look complete.
- Use a consistent counting basis. If the UI counts meal entries with missing data, label it that way; do not display an ingredient count as a meal count. Count only contributors that participate in nutrition under existing optional/seasoning rules.
- All-unknown is “Not available”; known zero is `0 g`; mixed known/unknown is a known subtotal with a partial indicator. Keep uncertainty visible in compact and expanded summaries and screen-reader output.
- Do not present a partial sodium/cholesterol subtotal as proof of being under the limit. A known subtotal already over the limit may still show “over”; under-target partial data stays qualified.
- Keep the existing floor/ceiling tone distinction. This package does not change the four primary macro policies or invent missing nutrient values.

**Storage / compatibility:** version the snapshot shape or add optional fields with tolerant decoding. Legacy numeric values remain untouched and coverage defaults to “not recorded,” not “complete.” Update RPCs, local mapping, export, and sync together. Test an older-format payload and a newer-format round-trip. Do not attempt to backfill frozen coverage from today's library.

**Regression cases:** complete/partial/all-unknown/known-zero recipes; missing required food match; mixed direct foods and recipes; optional/seasoning exclusions; signed restaurant components; scaling; day and week aggregation; old snapshots; source edits after logging; export round-trip.

## 6. WP2 — Complete, scoped, recoverable synchronization

**IDs:** R03, R04, R05, B01, U07. **Highest integration risk; one owner.**

**Starting points:** `lib/data/sync/{record_sync,library_sync,sync_engine,remote_rows}.dart`, `lib/data/remote/{remote_gateway,supabase_remote_gateway}.dart`, `lib/data/local/pending_write_store.dart`, `lib/app/sync_controller.dart`, related migrations/RPCs and sync tests.

### 6.1 Required behavioral contract

- A successful scoped synchronization cannot permanently skip accessible records because of page limits, equal timestamps, concurrent writes, device clock skew, scope changes, or deletions.
- Pending local mutations survive disconnects/restarts and are never mistaken for stale cache rows during reconciliation.
- No user/household change reuses another scope's checkpoint or dispatches its queued writes as the newly signed-in person.
- A completed pass and “Synced” UI state mean the relevant mutations were acknowledged; an attempted pass alone is not enough.

### 6.2 Scope ownership

Use versioned checkpoint namespaces including backend/project identity, entity stream, and the applicable owner: user for personal rows, household for shared rows, global catalog for global rows. Never infer the owner solely from whichever account happens to be current when an await finishes.

Capture a scope/generation token at pass start. If sign-out, sign-in, or household membership changes during a pass, cancel or discard stale results before applying them. Pending writes must carry sufficient owner context to prevent cross-account replay. Preserve another account's unsynced work without showing its personal data to the active account.

Initial sync for a new scope starts from no valid checkpoint, even if another scope previously synced. Household joining must expose the complete newly accessible library. Regression-test query-by-ID and export paths as well as list filtering; server RLS does not scope a shared local cache automatically.

### 6.3 Pagination and checkpoint contract

Replace single-response “fetch all” calls with explicit pagination for ordinary selects, aggregate RPCs, and membership/reconciliation queries. Do not fix the issue by merely increasing Supabase's row limit.

The preferred implementation uses deterministic server ordering and an opaque, scope-bound cursor or equivalent safe page contract. Persist only progress whose records have been durably applied. Define ties and concurrent changes explicitly. A client clock or an assumed one-minute overlap is not a completeness guarantee; a raw increasing sequence is also insufficient unless transaction commit ordering is handled.

Before coding this portion, write a short design note showing how a write committed during a multi-page pull is eventually fetched. For this two-person app, a bounded fully paginated snapshot/reconciliation strategy is acceptable if it is simpler than an incremental feed and handles concurrent/pending local changes correctly. Choose one approach and prove its invariants; do not build both a new sync framework and a Realtime system.

**Required scenarios:** 0/1/999/1000/1001/2500 rows; more than one page of equal timestamps; aggregate recipes with children; page-two failure and restart; writes/deletes during pagination; device clock ahead/behind; membership tables beyond one page; invalid/corrupt payload without silently advancing past unhandled data.

### 6.4 Deletions and conflict handling

Inventory every synchronized table, its owner, deletion behavior, ordering dependencies, and conflict policy. Include meal entries/days, shopping lists/items, collections/memberships, templates, favorites, and photo references, not just recipes and foods.

Recommended approach: retain the existing recipe/food soft deletes and introduce scoped deletion tombstones or an equivalent authoritative reconciliation for physically deleted entities. If older clients can still physically delete rows, server-side capture must cover those writes during rollout. Absence in a failed, partial, filtered, or capped response must never be treated as proof of deletion.

Preserve the current whole-record last-write-wins product policy where adequate, but document the ordering token, stale update behavior, and explicit Undo resurrection. Retried old writes must not resurrect a deletion accidentally. Only a newer intentional restore may do so. Relationship and parent/child deletions must apply in valid foreign-key order.

Tombstone retention must account for a phone offline longer than retention. Such a phone needs a safe full reconciliation before it can treat its cursor as current. Do not purge tombstones without that fallback.

### 6.5 Repair devices already affected

- Add a versioned sync-protocol/bootstrap marker. Do not reuse old unscoped checkpoints as if they were complete.
- On first upgrade, preserve local records and the outbox, then perform a complete scope-correct reconciliation. Pending/newer local writes are protected and eventually acknowledged.
- Historical physical deletes predating a new tombstone feed cannot be recovered from that feed. Reconcile authoritative server membership after a complete fetch to remove old ghost rows, excluding unsynced local creations/updates and respecting conflict rules.
- Use staging or another transaction-safe approach so a halfway failed repair does not present an empty library or delete valid local records.
- Report repair progress honestly and allow retry without clearing data. A missing connection leaves local cooking/logging usable.

### 6.6 Retry scheduling and status

When sync is requested during a running pass, set a dirty/pending-rerun flag. At completion, run again if needed. Coalesce bursts without dropping work. On transient failures, use bounded exponential backoff with jitter, cancellation on disposal/scope change, a reconnect-triggered attempt, and manual retry. Connectivity is a hint, not proof the backend works.

Suggested defaults for adoption: delays around 2, 5, 15, 30, then 60 seconds while foregrounded; stop the automatic burst after five attempts and retain pending work for reconnect/resume/manual retry. Do not retry invalid/auth-forbidden payloads forever. Existing device background limitations remain; no claim of continuous background sync is made.

Expose state from one controller/repository contract: saving locally, saved locally/pending, syncing, synced, needs attention, and initial repair as applicable. UI labels may collapse these to avoid noise. “Synced” must not appear if a queued write failed, a required pull stopped offline, or repair is incomplete. Provide a useful error and Retry without raw tokens, SQL, or stack traces.

**Tests:** fake clock/retry delays; offline → online while app remains foregrounded; write during slow pull; rapid repeated edits; restart with queue; permanent failure; sign-out mid-request; A → B → A; household join; old queued delete followed by Undo; remote delete against local dirty edit; initial repair interrupted; complete second-device convergence.

## 7. WP3 — Shopping dates and concurrent edits

**IDs:** R08–R10. **Starting points:** `lib/data/repositories/shopping_repository.dart`, `lib/app/providers.dart` (`ShoppingRange`), `lib/features/shopping/{shopping_screen,shopping_chat_controller}.dart`, domain shopping operations and merge logic.

### 7.1 Calendar ranges and persisted ownership

- Define a default inclusive seven-day interval: today plus the next six **calendar dates**. Use date-only/calendar construction, never elapsed 24-hour additions for date ranges.
- Normalize range boundaries through the established date-only representation. Test both DST directions and a non-DST zone, month/year boundaries, and leap day.
- Reopening a saved list shows its persisted `from` and `to` and its existing items. Do not show today's default above an older list.
- If no list exists, use the default. While a list is loading, do not flash a competing range or rebuild implicitly.
- Range selection produces a proposed range until a rebuild is confirmed. Cancel preserves the saved range/list. Save the accepted range and rebuilt contents atomically through the repository.
- Preserve manual lines, quantity overrides, source quantities, checked state, order, and on-hand behavior using the existing merge policy. Clarify any transition that would reset on-hand; do not silently reinterpret a new shop as the same inventory.

**Acceptance tests:** New York `2026-10-28` through `2026-11-03`, not November 2; spring DST case; restart on a later date; cancel range edit; rebuild failure; remote update to the saved range; no transient default-date rebuild.

### 7.2 Safe AI operations and targeted Undo

The model's answer is a set of proposed operations, not a replacement list. Capture stable list/line IDs and the request's base version. Resolve natural-language names to IDs with ambiguity detection. A removed line must not be silently retargeted to a different newly named line.

**Requirements**

- On response, apply each operation to the current list through the repository. Unrelated edits made during the request survive.
- Detect conflicting changes to the same field, line deletion/recreation, list replacement, or range rebuild. Show a concise proposal/review for those conflicts rather than silently choosing the old value.
- An answer arriving after leaving the screen, switching account/household/list, or cancellation cannot mutate the wrong list.
- Prevent double submission/retry from duplicating successful adds. Use an operation/request identity at the appropriate boundary.
- Undo reverses only the accepted operations from that answer. If the affected field was edited again afterward, preserve the newer value and explain the conflict. Do not restore an entire stale list snapshot.
- Keep current review-before-export semantics. The list visibly shows accepted edits and provides Undo; nothing automatically opens Walmart or hands off a cart.

**Tests:** start AI → tick unrelated line → response; edit same quantity while waiting; partner changes item; rebuild range while waiting; delete/recreate same name; cancel/navigate away; rapid replies out of order; failed save and retry; Undo after unrelated edit; Undo after same-field edit.

## 8. WP4 — Faster logging, navigation, and accessible interaction

**IDs:** R07, U01–U08. **Proposed defaults:** implement these together as the adopted UX direction, while shipping in small PRs. Preserve all approved nutritional displays and theme choices.

### 8.1 Compact daily summary

Proposed phone layout, not a pixel-exact mockup:

```text
Today · date                         [Log food]
Calories: amount left / over · target
Protein …       Carbs …       Fat …
Fibre …     Sodium …     Cholesterol …   [Details]
Breakfast                             [+ Add]
  Meal · portion · nutrition          [Edit] [Log]
...
```

- Use existing remaining/over language and explicit totals/targets. The compact view retains a subdued readout for all three minor nutrients, including unknown/partial states; it must not make them disappear again.
- Details expands the existing rings and slim bars. Remember compact/expanded preference device-locally. Existing users retain access to the previously approved presentation.
- Keep Log food easy to reach without covering meal content or the keyboard. At 390×844 and ordinary text, the first meal section should be visible without scrolling through the summary. At large text, prioritize scrollability and readable controls over squeezing content above the fold.
- Do not compress the desktop layout simply to copy the phone. Preserve roomy comparison where it helps planning.

### 8.2 Logging confirmation and portions

- Make the selected-food/recipe confirmation content scrollable with SafeArea and keyboard insets accounted for. The action must remain reachable at 1×, 1.4×, 2×, and 3× text, including a short phone viewport. Avoid nested scroll traps.
- Show a labelled amount field and unit/serving selector using the food's existing serving options: e.g. `170 g`, `1 scoop`, or `½ package`. Do not infer package mass or density that the data does not provide.
- Resolve every amount to one consistent canonical/per-serving basis before calculating macros. Switching units retains the equivalent quantity where conversion is known. Where it is not known, require explicit selection without guessing.
- Recipes remain servings-based unless an explicit measured-yield mapping already exists. Do not invent total recipe grams.
- Reject zero/negative consumption portions and nonfinite numbers. Keep restaurant deductions confined to recipe construction, not negative eaten portions.
- Provide visible Edit portion/overflow on a meal row. Retain long-press as an optional shortcut and preserve one-tap planned → logged for the unchanged portion.
- For portion correction on a previously logged item, base the correction on the frozen nutrition basis. A source-food edit must not silently change the old meal during a portion correction. Explicit replacement/re-log is a separate action.

### 8.3 Preserve restaurant logging intent

- Carry a typed logging context through restaurant selection, component builder, recipe editor, and save: user/scope, selected date, meal slot, and planned versus logged intent.
- When invoked from logging, offer a clear final action such as “Save and log lunch”; from planning, “Save and add to lunch”; from Recipes, ordinary Save.
- Build/edit review occurs before saving/logging. Cancellation creates neither a stray recipe nor an entry. If the recipe save succeeds but adding the plan entry fails, retain the saved recipe and offer retry without duplicating it.
- Freeze the final reviewed nutrition once. Backdated dinner must not silently become today's lunch.

### 8.4 Creation menu, startup, and navigation

- Replace the stacked recipe-creation FABs with a labelled Add recipe control opening existing choices: Write a recipe, Import a recipe, Eat out, and Generate with AI. Do not create additional import engines. Keep accessibility labels and availability/offline explanations.
- Add “Today” to Opens on alongside Home and Nutrition. Today resolves the local current date at launch; it does not persist yesterday's route. Existing saved choices retain their meaning and deep links continue to win when appropriate.
- Preserve last Nutrition tab, search/filter choices, and scroll positions for a Home → Nutrition round-trip in the same signed-in session. Use limited state restoration/providers if that is simpler than retaining navigators.
- Explicit launch choice takes precedence on cold start. Clear private navigation state on account change. Unsaved editors retain their existing discard protection; do not silently autosave them for navigation restoration.
- App-wide cook timers stay visible/reachable after Home navigation. Preserve PR #12's safe-area, sidebar, and home accessibility fixes; verify rather than rebuilding them.

### 8.5 Accessibility acceptance

Test complete journeys, not just the initial screen: picker → selection → amount edit → validation error → confirm; Add menu → builder; Home → Nutrition → Settings; collapsed/expanded summary; shopping conflict/Undo.

- Run both themes and all supported text scales; include notched phone insets and short desktop windows with large text.
- Use actual application fonts. Add only a small set of useful golden fixtures; inspect new baselines rather than treating `--update-goldens` as a test pass.
- All controls need operable semantics, not just labels. Numeric progress, partial data, selected state, and failures must be understandable without color.
- Preserve 44-point minimum interactive targets for the iOS-oriented UI; ensure keyboard focus, tab order, visible focus, Escape/back behavior, and desktop access as well.
- Respect reduced motion; error/status announcements should be meaningful and avoid repeated background-sync chatter.
- Manual VoiceOver pass covers one full meal log and one shopping correction. If hardware access is unavailable, document that gate as pending.

## 9. WP5 — Complete imports and honest, portable exports

**IDs:** R11, R12, U09. **Starting points:** `lib/data/adapters/{pdf_pages,pdfx_pages,menu_reader,data_export}.dart`, `lib/features/foods/menu_import_screen.dart`, menu import domain/writer and export UI.

### 9.1 PDF page coverage

- Return PDF metadata including total page count, selected page numbers, successful renders, and failed page numbers. Preserve page ordering and provenance through extraction/review.
- Add page selection or ranges. Keep a bounded batch size (currently six pages is reasonable), but make every page accessible through additional explicitly requested batches.
- Before paid extraction, show “Selected pages 7–12 of 18” or equivalent. Afterward show which pages were read. Never represent first-six-page extraction as the whole document.
- If a page cannot render, name it and offer retry/change selection. No silently skipped pages. Cancelled picking is not an error and must not clear existing review work.
- Preserve pending review rows when reading another batch. Detect repeated batch submission and present duplicate candidates instead of inserting twice. Do not automatically charge for every page of a long document.
- Show restaurant, source document/date where available, section, serving basis, and uncertain cells in review. Do not describe AI confidence as nutritional verification.
- Commit an accepted batch atomically where possible. If the remote delivery is queued, keep local save/outbox transactional. A partial failure plus retry must not duplicate the already saved rows; test this boundary even though it was not a reproduced original defect.
- Imported menus remain household-scoped. Creating a restaurant in the app must not gain permission to edit global seed data.

**Tests:** 1/6/7/18-page documents; select later pages; failed middle render; reordered selection; cancel; offline/AI error; second batch append; duplicate batch; unknown vs zero cells; save failure and retry; no writes before review.

### 9.2 Export format and completeness

Create a versioned export schema and a table/field coverage manifest. Export in a consistent local database read snapshot rather than independently reading changing tables throughout the operation.

**Required contents**

- Household recipes and foods, including soft-deleted definitions needed by historical references; all serving options, minor nutrients, restaurant metadata/modifiers, icons, and existing supported fields.
- Referenced global food definitions used by exported recipes, direct plan/log entries, templates, or other included references. Mark them as global/source definitions; exporting them does not grant write authority or require exporting the entire global catalog.
- The active user's plans/logs, exact frozen snapshots and coverage metadata, all seven targets, favorites, food profile, and templates with their entries.
- Household collections/memberships, ingredient matches/seasoning rules, shopping ranges/items and their three quantities/order/status, and other already-supported user-owned records found in the schema inventory.
- A manifest with schema version, export time, relevant scope, section counts, missing references, known exclusions, and sync/completeness status. Include no secrets or session material.

**Honest boundaries**

- Offline export remains available as a local-data export. State that remote changes may be missing; pending writes, incomplete bootstrap, or failed sync prevent a claim of server completeness.
- Binary recipe photos may remain excluded for this stage, but enumerate the exclusion and retain object references/metadata where appropriate. Those references are not a portable photo backup.
- Do not include the partner's private logs/profile or other previously signed-in accounts' data.
- Audit persistent device preferences and transient records too. Include safe portable preferences or explicitly list them as excluded; remove “Everything else is here” unless the manifest justifies it.
- A full user-facing import/restore system and binary backup archive are separate proposed follow-ups, not silently included in this program. Provide schema validation/reference-closure tests and document how to interpret the export without implying one-tap restore exists.

**Tests:** referential closure; restaurant recipe using a global component; direct global-food log; template-only reference; all nullable/custom minor targets; deleted source plus frozen log; icon/portion/Walmart metadata; another user's private records excluded; stable counts under concurrent write; offline/incomplete manifest; v1 sample compatibility with the documented v2 format.

## 10. WP6 — Complete password recovery and verify access boundaries

**ID:** R13, Q05. **Starting points:** `lib/data/auth/{auth_gateway,supabase_auth_gateway}.dart`, sign-in/Settings screens, router/platform link registration, `supabase/config.toml`, `docs/SUPABASE_SETUP.md`.

### Proposed route decision

Recommended default: a complete in-app recovery screen backed by Supabase recovery sessions, with explicit allow-listed redirect configuration and platform handlers for iOS/macOS/Windows. Before implementation, verify the installed Supabase SDK's recovery/PKCE behavior, including whether a link opened on a different device can complete the flow. Do not assume cross-device recovery works merely because same-device recovery does.

If a hosted web recovery destination is preferred or required, prepare its concrete implementation/configuration as a separate reviewed artifact. A real controlled domain/hosting destination is Brendan's decision; do not invent or register one. Unavailable dashboard access does not block local implementation/tests, but production recovery remains unfinished until the destination is configured and verified.

### Functional requirements

- Forgot password on sign-in and Reset password in Settings use the same recovery service and preserve generic signed-out messaging that does not disclose account existence.
- A valid recovery link enters a dedicated new-password screen bound to the recovery session. Do not route it into ordinary app content before the reset is complete.
- Validate password/confirmation, submit via Supabase `updateUser`, show success, and provide a tested route back to sign-in or the intended session state. Apply the server password policy; do not implement custom credential storage.
- Expired, invalid, reused, cancelled, and offline recovery all have clear next actions. Never log token-bearing URLs, passwords, email-link fragments, or recovery credentials.
- Handle warm and cold links on every supported platform. Preserve the existing Instagram/share-extension route. Malformed or unrelated links cannot bypass auth gating.
- A page called Site URL is not itself a password-reset implementation. Document the actual destination, allow-list entries, handler, and ownership in setup instructions.

### Security validation

Verify rather than assume hosted email verification, password policy, configured redirects, and paid Edge Function caller authorization. A public publishable key alone must not authorize spending; test absent/invalid credentials and a non-member caller according to the actual private-app membership policy. Do not claim that verifying a JWT necessarily establishes allowed household membership.

Add/extend user and cross-household negative tests for touched tables/RPCs, tombstones, export scope, and local cache access. Inspect existing guards first to avoid duplicate suites. Public/global-food read behavior must remain deliberately allowed while writes are refused.

**Release gate:** real reset email received, valid link completes, old password behavior and new sign-in verified, invalid/expired link handled, all supported platform handlers checked or explicitly marked unavailable. Credentials are entered by Brendan, not copied into tool calls or artifacts.

## 11. WP7 — Harden external fetching and paid AI accounting

**IDs:** R14, B02. **Starting points:** `supabase/functions/recipe-ai/index.ts`, shared Edge Function helpers if present, AI usage migrations/RPCs, adapter contracts.

### 11.1 Fetching untrusted URLs

- Extract fetching/validation behind a testable server-side boundary. Allow only intended protocols; prefer HTTPS and reject embedded credentials.
- Validate destinations before connecting, including host/IP representations, IPv4/IPv6 loopback/private/link-local/metadata ranges, and redirect targets. Protect against DNS rebinding by ensuring the actual connection destination is covered by validation or by using an appropriate controlled egress/fetch service; one DNS precheck is not a full defense.
- Follow redirects manually only if every hop is revalidated and a small hop cap is enforced. Never fall back to unvalidated fetching when a legitimate site fails.
- Apply connection/total timeouts, accepted content types, and a streaming byte cap. Content-Length alone is insufficient; chunked/misreported/compressed responses must also be bounded as supported by the runtime.
- Preserve user input on refusal/failure and provide a useful message with paste/screenshot alternatives. Test with controlled local fixtures or an injected transport, not production internal-address probes.
- Validate request schemas and total payload limits before paid calls. Handle nonstring modes, malformed arrays, oversized message text, unexpected shapes, and nonfinite numbers with structured 4xx responses. TypeScript assertions are not runtime validation.

**Tests:** ordinary recipe URL; credentials in URL; forbidden schemes; private/loopback/link-local IPv4 and IPv6; public-to-private redirect; redirect loop; oversized chunked response; timeout; wrong MIME; malformed JSON/body shape; source preserved; no paid request after validation rejection.

### 11.2 Budget and concurrency

Proposed default: **paid requests fail closed when spending authorization/accounting is unavailable**. Local logging/cooking remains unaffected; decorative icons quietly skip in background and show useful feedback for explicit redraw.

- Reserve a conservative upper-bound cost atomically before dispatch using a server-only ledger/RPC, then settle actual usage. Include concurrent reservations in monthly and decorative-budget checks. Bound input/output so the reservation is meaningful.
- Keep the existing warning and decorative thresholds unless the current configuration or Brendan changes them. Do not hard-code pricing assumptions without verifying the active provider/model and documenting the estimate's source.
- Record provider usage even when extraction/parsing fails after a paid response. A valid billable response is not free just because it contained no useful recipe.
- Handle ambiguous transport failure conservatively: the provider may have processed the request. Do not release the reservation immediately and auto-resend a paid request. Document reconciliation/expiry so a reservation neither disappears too early nor blocks spending forever.
- Use stable request identities for accounting/retry deduplication and a bounded per-user/concurrent-request limit. A timeout/retry must not produce duplicate ledger entries or unbounded charges.
- Add RLS/grant restrictions with any accounting schema changes. Ordinary clients cannot lower spending totals, create trusted reservations directly, or raise limits.
- Verify the external billing backstop separately. Report the application's guarantee honestly if provider pricing/usage uncertainty prevents an exact dollar cap.

**Tests:** counter unavailable → no provider call; simultaneous near-limit requests; decorative threshold; invalid request consumes no budget; successful response settles; parse failure still records usage; timeout ambiguity; replayed request; settlement failure; month boundary; unauthorized caller; user-visible retry without duplicate payment.

## 12. WP8 — Maintainability, CI, and useful observability

**IDs:** Q01–Q05. Implement alongside the packages rather than as a sweeping cleanup PR.

### 12.1 Code organization

- Keep pure domain logic and existing repository/adaptor boundaries. Retain Riverpod and go_router.
- Move touched orchestration out of large widgets when it enables a clear testable action: exact restore, unit conversion, logging context, shopping operation application, and import batches.
- Split `recipe-ai` validation/fetching/accounting into focused modules when adding their tests. Avoid broad formatting/movement of unrelated logic in the same PR as a defect fix.
- Centralize repeated field mapping only where ownership is clear. Use constructor/serialization/DB/RPC/export contract tests to make a missing new field fail visibly. Do not introduce an automatic mapper solely to reduce line count.
- Rewrite comments that claim stronger guarantees than the code provides. Document the invariant and its test instead of a long history or an unsupported “cannot fail” claim.

### 12.2 CI plan

Retain format/analyze/unit/widget and fresh-schema guards. Add:

1. Deno formatting/type-checking and unit tests for Edge Function validators, fetching, shaping, and accounting with mocked external calls. No paid API call on ordinary PR CI.
2. Deterministic contract tests spanning Dart serialization, RPC shapes, local storage, and export. Generated source is regenerated by tools, never hand-edited.
3. Native compilation checks on suitable macOS/Windows runners. iOS no-sign build validates compilation; signing/device installation remains a separate authorized release step. Use scoped platform triggers if needed to manage cost, plus pre-release full coverage.
4. Historical Drift migration tests in addition to a clean database reset. Include the previously half-applied photo migration, the preceding production version, the new schema, and queued offline writes. No migration may query through an API that waits on its own unfinished upgrade.
5. Local/test-backend integration tests covering real auth/RLS, sync pages/deletions/retry, and cross-scope denial. Live third-party extraction checks remain opt-in or a deliberately configured scheduled suite, with missing secrets reported as missing rather than silently counted as passes.
6. A small critical-journey accessibility/golden suite using actual fonts, phone safe areas, large text, and short desktop windows. Test intermediate/error states and final confirmation.
7. Secret scanning for commits and relevant build outputs with synthetic fixtures/allow-listing for placeholders and publishable keys. Configure least-privilege workflow permissions; review third-party action pinning when touching CI. Never print a matched real secret into a public log.

Read process exit codes. Set job timeouts and retain useful logs. Do not use `test | tail` or an indefinitely running watcher as a gate. Rerun targeted checks after a fix; run the integrated suite at coherent PR/release boundaries instead of repeating it without new evidence.

### 12.3 Operational visibility and performance

- Keep diagnostics privacy-safe: operation ID, stage, duration, retry count, page count, and structured failure class. Do not record recipe text, health totals, passwords, or tokens unnecessarily.
- Give Settings a useful diagnostic summary: last successful sync, pending/failed counts, retry action, app/schema version, and export completeness. Avoid raw implementation details in ordinary meal flows.
- Test at 500 recipes, 1,000 foods, a year of meal entries, and a 2,500-row sync fixture. The latter specifically exceeds common API caps; ordinary one-year logging may already do so.
- Measure cold launch, search, opening Today, logging, and backlog sync in profile/release on a representative phone. Establish baseline timings and identify regressions. Do not invent a performance pass from widget-test timings.
- Proposed usability metric: compare the same five common meals in Hearth and MacrosFirst; target no slower median logging time and no extra required navigation for a recent food. Treat this as a trial target, not an already measured fact.

## 13. WP9 — Release, migration safety, and two-week trial

### 13.1 Safe rollout

1. Confirm the release SHA, clean intended diff, green required CI, and review dispositions. Do not deploy from an unrelated worktree or stale main checkout.
2. Before schema changes, document affected rows, old/new client compatibility, backup availability, and forward-repair/rollback behavior. A local export alone is not proof of a complete server backup.
3. Use additive migrations where possible. Test from a fresh local database and supported historical device states. Verify exact RPC bodies retain all fields; `create or replace` replaces the whole body.
4. Apply migrations to the intended hosted project under the implementation session's deployment authorization and repository rules; verify with `supabase migration list`. Never reset hosted data. Missing permissions/configuration remain an explicit blocker for that gate.
5. Deploy tested Edge Functions after prerequisites exist. Verify deployed version and safe contract behavior without making unauthorized paid calls. Keep old clients compatible during rollout or document an explicit minimum-version transition.
6. Build the intended release from merged code and install over the existing app using the platform's preserving install route, such as `xcrun devicectl device install app`. Do not use `flutter install` if it uninstalls and clears local data. Respect device availability and show the actual install result.
7. Verify the installed build/version and startup, preserved food/recipe counts, logged snapshots, queue/repair completion, and a real meal log. A successful build or installer exit alone is not proof the feature works.

### 13.2 Required two-device scenarios

- Device A logs offline, changes a portion, reconnects, and device B converges without duplicates or altered snapshots.
- A deletes a meal/shopping item; B receives the deletion. A performs Undo before and after a sync; both converge correctly.
- A updates a recipe while B logs its older local copy; B's frozen log remains the exact meal it reviewed.
- A changes household or signs in as another test user; old private data and checkpoints do not bleed into the new scope.
- A long PDF imports selected later pages with honest coverage; export contains its referenced definitions and the current user's records.
- A budget rejection or network failure blocks AI only; manual logging still works.

### 13.3 Trial and completion

Run the 14-day replacement trial only after P1 defects and core release gates are resolved. Capture bugs with build, steps, expected/actual result, and non-sensitive evidence. Every trial bug receives a durable failing test before repair.

Completion requires: every review ID accounted for; passing relevant regression/full/CI checks; hosted parity where schemas changed; deployed functions where changed; manual gates explicitly passed; no hidden data-loss workaround; updated spec/setup docs; and a report distinguishing automated evidence from manual results. An unavailable Windows device, missing test secret, or unfinished recovery destination is “pending,” not “passed.”

## 14. Implementation order and PR boundaries

Suggested PR-sized sequence. Adjust boundaries to current code, but preserve dependency order and reviewability.

| PR package | Scope | Depends on | Main validation |
|---|---|---|---|
| A | R02 fractional editor preservation | WP0 | Domain/draft/persistence round-trips |
| B | R01 exact restore | WP0 | Multi-serving, timestamps, idempotency; later sync integration |
| C | R06 completeness metadata | A/B where shared | Domain → snapshot → DB/RPC → UI compatibility |
| D | R03–R05 complete scoped sync and repair protocol | B/C interfaces settled | Real paginated/deletion/scope integration; migrations |
| E | B01 retries and U07 sync state | D | Fake-clock scheduling, reconnect, stale scope |
| F | R08/R09 date and saved-range behavior | WP0 | Calendar/restart/rebuild tests |
| G | R10 safe shopping operations/Undo | D/F | Concurrent local/remote change and undo tests |
| H | R07/U01/U03/U06 daily logging UX | C | Full large-text logging journey; usability pass |
| I | U02/U04/U05/U08 navigation/restaurant context | H interfaces; D scope contract | Cold/warm launch, deep links, context, state restore |
| J | R11 PDF page review | A | Page failures, batch review, atomic/idempotent save |
| K | R12 export schema | C/D/F/J data shapes settled | Coverage manifest, closure, privacy, local snapshot |
| L | R13 recovery | WP0; D scope behavior | Local flow plus actual configured recovery |
| M | R14/B02 Edge security/accounting | WP0 | Deno contracts, SSRF fixtures, concurrent reservations |
| N | Remaining WP8 CI and release evidence | Incremental throughout | Platform builds, migration/security/flow matrix |

Small corrective PRs may combine closely related items; the sync work may need several additive PRs. Do not create one enormous “all review fixes” diff.

### 14.1 Optional parallel agents

Parallel execution is possible **only if Brendan asks for agents in the implementing session**. This document proposes ownership; it does not start agents.

- **Data-integrity owner:** WP1 and shared nutrition/snapshot types.
- **Sync owner:** WP2, remote protocol, outbox, shared database migration integration.
- **Client-flow owner:** WP3/WP4, after domain contracts settle.
- **Import/export owner:** WP5, coordinating with the data-integrity owner.
- **Auth owner:** WP6, coordinating router/bootstrap changes with the client-flow owner.
- **Edge owner:** WP7; owns `recipe-ai` changes, including conflicts with import work.
- **Integrator:** owns shared `providers.dart`, test harness interfaces, migration ordering/schema version, CI, and spec integration.

Use isolated worktrees. Agree interfaces before parallel editing. Only the integrator allocates shared migration versions/schema increments and coordinates hosted pushes. Agents must not independently reset/deploy the same shared backend. Feed review fixes back to the owning branch; use the app's CI events rather than competing watchers.

## 15. Decisions and defaults for Brendan's approval

These are proposed choices, not hidden implementation details. If Brendan approves this plan as written, use the defaults; ask again only for a newly discovered product conflict or an unavailable external destination/credential.

| Decision | Proposed default | Impact |
|---|---|---|
| Daily summary | Compact phone summary with visible minor totals; remembered expanded rings/bars | Faster access without removing approved detail |
| Launch | Add Today; preserve Home/Nutrition and existing saved preference | Fast daily path, no forced landing change |
| Home round-trip | Restore session tab/filter/search/scroll; reset private state on account switch | Predictable navigation without global persistence of drafts |
| Recovery | Complete in-app flow on supported platforms; verify link/PKCE behavior first | Requires explicit dashboard/platform setup; hosted fallback needs a real destination |
| AI counter outage | Refuse new paid requests; retain manual/offline use | Clear temporary failure instead of uncontrolled spending |
| Strict budget | Atomic reservation plus settlement and conservative ambiguous-failure handling | More robust accounting; requires additive server work |
| Export | Versioned complete structured local export with reference definitions and explicit exclusions | No claim of photo backup or one-tap restore |
| Sync | Scoped complete pulls/deletions and bounded retries; keep no permanent Realtime socket | Correctness without a new realtime architecture |
| Security test deferral | Bring cross-user/household negative tests into this stabilization stage | Establishes evidence before the full-library trial |
| Nutrient defaults | Preserve existing values; document current authoritative source when amending spec | No new clinical targets or body-derived goals |

**Remaining separate backlog:** household unlink with storage duplication; missing test-project secrets; actual Instagram/share-extension validation; binary backup and user-facing restore; additional pillars; any other §12 feature not explicitly adopted here. Record these honestly, but do not expand this program to build them silently.

## 16. Sources informing the best-practices pass

These support engineering principles, not claims that the installed app or hosted configuration was independently certified. Recheck current primary documentation when implementing SDK-dependent behavior.

- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations): repository boundaries, separation of responsibilities, and testing components together as well as separately.
- [Flutter offline-first guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first): explicit synchronization strategy and combining local/remote data through repositories.
- [Flutter testing overview](https://docs.flutter.dev/testing/overview): unit/widget coverage complemented by integration coverage of important use cases.
- [Supabase Dart select reference](https://supabase.com/docs/reference/dart/select): default result caps and explicit pagination.
- [Supabase password-based authentication](https://supabase.com/docs/guides/auth/passwords): recovery request, redirect handling, and password update are distinct parts of the flow.
- [OWASP SSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html): destination/redirect validation and defense against internal-network requests.
- [OWASP REST security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html): runtime input validation, request limits, and rate limiting.
- [W3C text-resize guidance](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html): retain content and functionality at enlarged text. WCAG is a useful benchmark, not by itself a native-app accessibility certification; Hearth's existing 3× checks remain in scope.

## 17. Implementation report template

For each PR, report:

```text
Review IDs addressed:
Base/head commits and PR link:
Observed defect / intended user behavior:
Failing regression demonstrated before fix:
Implementation and compatibility notes:
Checks actually run, exit codes, and skipped/unavailable checks:
Migration local/hosted parity (if applicable):
Deployment/version verification (if authorized and applicable):
Manual steps for Brendan and their current status:
Remaining IDs / newly discovered risks / explicit deferrals:
```

The final handoff must account for the entire inventory, not just the last PR. Do not equate “code written,” “tests green,” “merged,” “deployed,” “installed,” and “manually verified”; they are separate states.
