# Phase 2 UX implementation

Tracks approvals and implementation from [HEARTH_UX_REVIEW.md](../HEARTH_UX_REVIEW.md).
The review is an assessment of its stated baseline; this file records subsequent work.
The earlier [UX review progress](UX_REVIEW_PROGRESS.md) covers a separate review.

Upcoming decisions and the approval-card workflow are tracked in
[UX_PHASE_2_APPROVALS.md](UX_PHASE_2_APPROVALS.md).

Groups are approved individually. An approval authorizes that group's described
scope, not every recommendation linked to the same feature area. Builders own
disjoint files; shared providers, specifications and test fixtures are integrated
by the coordinating agent under [the ownership rules](ORCHESTRATION.md).

| Group | Scope | Approval | Implementation | Automated checks | Fresh-context review | Real-device verification |
|---|---|---|---|---|---|---|
| 1 — Daily logging | UX-039, UX-041, UX-053 | Approved 2026-09-30 | Merged in [PR #116](https://github.com/gradybre/hearth/pull/116) | 3,925 passed; analyze clean; 71 render checks and all CI passed | Passed after corrections; code candidate `9e50bd1` | Not performed |
| 2 — Grocery clarity | UX-058, UX-060 | Approved 2026-09-30 | Merged in [PR #117](https://github.com/gradybre/hearth/pull/117) | 3,985 passed; analyze clean; 87 render checks and all CI passed | Passed after corrections; code candidate `7d2121f` | Not performed |
| 3 — Recipe actions and nutrition | UX-001; recipe-detail scope of UX-010 | Approved 2026-09-30 | Merged in [PR #118](https://github.com/gradybre/hearth/pull/118) | 4,089 passed in UTC plus 2 DST checks in New York; analyze clean; 99 render checks and all CI passed | Passed after one correction; final candidate `3c64406` | Not performed |
| 4 — Export preview | UX-083 | Approved 2026-10-01 | Merged in [PR #119](https://github.com/gradybre/hearth/pull/119) | 4,161 passed in UTC; 21 calendar checks in New York; analysis clean; 103 render checks and all CI passed | No actionable findings; candidate `27d9eff` | Not performed |
| 5 — Ongoing nutrition targets | UX-052, bounded personal carry-forward and weekly exceptions | Approved 2026-10-01 | Merged in [PR #120](https://github.com/gradybre/hearth/pull/120) after Brendan's merge approval | 4,259 passed in UTC; 72 checks in New York; clean analysis; 111 render checks and all CI passed | No actionable findings; candidate `cf3bdd8`; 133 independent checks passed | Not performed |
| 6 — Cooking ingredient checklist | UX-018 | Approved 2026-10-01 | Merged in [PR #121](https://github.com/gradybre/hearth/pull/121) | 4,339 passed in UTC; 50 checks in New York; clean analysis; 115 render checks and all final CI passed | No actionable findings after the persistence correction; reviewed code unchanged by rebase onto main | Not performed |
| 7 — Faster grocery additions | UX-061, plain-item quantity and reviewed paste scope | Approved 2026-10-01 | Merged in [PR #122](https://github.com/gradybre/hearth/pull/122) | 4,427 passed in UTC; 35 checks in New York; clean analysis; 119 render checks and all final CI passed | No actionable findings after dismissal correction; 47 independent final checks passed | Not performed |
| 8 — Open meals from Plan | UX-051, source navigation and separate logging control; exact log/unlog Undo excluded | Approved 2026-10-01 | Merged in [PR #123](https://github.com/gradybre/hearth/pull/123) | 4,500 UTC tests; 38 New York checks; clean analysis; 135 render checks and all final CI passed | Code correction passed on `57e0968`; 44 independent focused tests; all 48 design captures reviewed | Not performed |
| 9 — Trustworthy logged portions | UX-040, new food-log portion evidence and frozen details; Plan-only input continuity excluded | Approved 2026-10-01 | Merged in [PR #124](https://github.com/gradybre/hearth/pull/124) as `57cd417` | 4,583 UTC tests; 32 New York checks; clean analysis; 143 render checks and all final CI passed | All 40 integration captures cleared; candidate `460e85e` reviewed with 111 independent tests passing | Not performed |
| 10 — Adjustable cooking timers | UX-019, extend and set time left on existing timers | Approved 2026-10-01 | Merged in [PR #125](https://github.com/gradybre/hearth/pull/125) as `f478498` | Combined candidate: 4,655 UTC tests; 116 New York checks; clean analysis; 157 render checks and all final CI passed | All design findings cleared; candidate `af6843e` reviewed with 185 independent tests passing | Not performed |

## Group 1 — Daily logging

- Personal recipe favorites and meal-relevant recents in the picker, optional
  Foods/Recipes scopes, all recents, and a separate remembered-portion review.
- Future entries default to planning; planned edits save the plan, with eating
  as a separate action. Today/past repeats retain their quick logging path.
- Consumed totals remain useful without targets, with honest missing-data
  labels and no invented goal comparisons.
- Save actions commit typed portions without requiring keyboard Done. An
  untouched rounded display retains the exact stored portion.

Review corrections preserve an open sheet's intent across midnight and carry
the selected serving basis through multi-day assignment. Tests cover later
logging, nutrient coverage, approximate package nutrition and frozen history.
The coordinating agent reran the full suite and inspected the changed code
and rendered fixtures after the corrections.

This group does not include historical raw-portion storage (UX-040), target
carry-forward (UX-052), or the broader Today/Week layout change (UX-087).
No migration, paid AI request or new dependency is required.

Automated tests and rendered fixtures do not establish native screen-reader,
two-device sync or installed-build acceptance. Those remain distinct checks.

## Group 2 — Grocery clarity

Approved: Remaining/All views, separate Bought/At home counts, more room for the
checklist with Add item prominent, and explicit Needed − Have = Buy quantities
with known package counts. Sharing/export and the existing AI entry move under
a labeled More action. No migration, additional AI request or new dependency.

Filtered reordering retains hidden rows, and a pointer already on the list
holds its displayed rows until release. Bought, At home and zero-total Not
needed remain distinct. The quantity preview retains original needs and
unchanged stored precision, and only existing conversion evidence supplies
package counts.

Regression checks caught and corrected footer overlap with Undo, contrast on
the selected list view, unticking cross-unit on-hand coverage, and dismissal
of an assistant sheet with a request in flight. The coordinating agent reran
the complete suite and inspected light, dark, desktop and enlarged-text
rendered fixtures. New journeys also reach the options, help, amount editor,
export review and assistant controls; they do not perform real AI requests or
external handoffs. Native-device acceptance remains unperformed.

Fresh-context review prompted further guards for acting on a held row after
new quantities arrive, keeping partial-Undo explanations visible inside the
assistant sheet, and matching Remaining with export when part of a need is
unmeasured. Those unresolved asks travel in copy/search with a stated missing
amount; a direct basket handoff excludes them instead of guessing a complete
purchase count. The coordinating agent reran formatting, analysis, all 3,985
tests (109 opt-in skips), and 87 render checks after the corrections. The
fresh-context reviewer found no remaining findings on code candidate
`7d2121f`. Native-device verification remains separate and unperformed.

This group does not include shopping-trip lifecycle (UX-057), realtime/conflict
changes (UX-059), or the AI proposal/review protocol (UX-063). The existing AI
chat's missing before/after proposal review remains the separately identified
UX-063 work; relocating its entry does not complete that recommendation.

## Group 3 — Recipe actions and nutrition

Approved: Plan and Shop directly from recipe detail, with a reviewed personal
date/meal/portion and a reviewed shared shopping quantity respectively. Plan
defaults to Today, Dinner and one personal serving, with Undo. Shop inherits
the displayed cooking yield and offers View list after adding. Recipe detail
also gains Per serving / Whole dish nutrition, retaining coverage labels and
large-text accessibility. The plan review sheet and the detail/actions work
have disjoint builder ownership; shared integration stays with the
coordinating agent. No AI request, dependency or migration is required.

The date review retains its opening day across midnight, accepts fractions
without requiring keyboard Done, and keeps its fields and actions scrollable
with enlarged text and the keyboard open. Shopping keeps the reviewed yield,
including quarter servings and large batches, and remains additive. The
displayed recipe header and nutrition basis follow cooking scale together.

Regression checks cover exact-entry Undo, repeated taps, cancellation and
recoverable failures. Undo and Retry remain usable after leaving the recipe;
an account or household change expires the earlier review instead of applying
its saved action to the wrong context. Enlarged serving controls wrap their
buttons and retain each serving count on one line. Confirmation actions sit
below the full-width message so Undo, Retry and View list remain readable at
3× text. The desktop date review is constrained to a compact dialog while
the phone version remains scrollable.

The coordinating agent independently ran formatting, analysis, all 4,089
tests in UTC (121 opt-in skips plus 2 daylight-saving checks skipped in UTC),
the 2 daylight-saving checks separately in New York time, and 99 render checks,
and inspected the changed code
and rendered light, dark, desktop and enlarged-text fixtures after the
corrections. Native-device verification is unperformed.

Fresh-context review found that the account-change explanation could be
dismissed immediately after Undo or Retry with accessible navigation enabled.
The write guard already prevented the expired action; deferring its feedback
until the old snackbar finishes dismissal keeps the explanation visible.
Both regressions failed before the correction and passed after it. Final
review and CI status are recorded on [PR #118](https://github.com/gradybre/hearth/pull/118).

The October rollover in CI also exposed three calendar-dependent assertions
in existing grocery tests: a visible range assumed September, and two
changed-week checks accidentally rebuilt the same range as today's default.
The fixtures now state their dates explicitly and keep the initial and
rebuilt ranges distinct. The failures reproduced under UTC before these
test-only corrections; production behavior is unchanged.

The nutrition portion of this group is limited to recipe detail; wording
parity in the editor, cook completion and log confirmation remains later
scope within UX-010.

## Group 4 — Export preview

Approved: rename Export everything to Export food data (JSON), preview the
local snapshot's scope, counts, logged date range, pending changes and
exclusions, then share that exact reviewed snapshot. Sync first refreshes the
review before sharing; Export this device now remains available. A receipt
states the filename and only the share outcome the platform can establish.
Readable archives, photos and restore are separate scopes. No migration,
dependency or paid AI request is required. The snapshot/data adapter and
review/receipt UI have disjoint builder ownership; the coordinating agent
integrates shared providers, test fixtures and documentation.

The export remains version-2 JSON with additive manifest facts. Counts and
logged meal dates are captured alongside immutable bytes in one transaction.
The device-wide outbox count is explicitly separate from local reference
resolution and does not certify a complete server backup. Shopping references
now participate in that check without including another household's private
records. Each OS handoff gets its own temporary directory so a later export
cannot replace an earlier file that a receiving app is still reading.

Regression checks proved defects before correction: literal pending-count
text, a filename crossing midnight separately from its contents, shared-file
overwrite, incomplete shopping reference checks, network-dependent offline
export, raw error text, large-text receipt positioning, missing years in date
labels, and navigation/sync cancellation boundaries. The coordinating agent
independently ran the full suite, analysis, calendar checks and render suite.
New review/receipt journeys also walk section by section at large text. Native
share-sheet and installed-device verification remain unperformed.

## Group 5 — Ongoing nutrition targets

Approved: personal targets carry forward after an explicit reviewed Save,
with a default-enabled “Use these targets each new week” option. Allow a
one-week exception and a way to stop carrying targets forward after the
current week. Existing saved targets retain their exact-week meaning until
the user enables continuity; historical weeks remain unchanged. No body-stat
presets, automatic coaching or trend history is included. This needs local
and server storage, sync and export changes. Independent files may be built
alongside Group 4; shared integration is sequenced. The first worker owns
only the new target-schedule domain model and its tests while export work was
active. Storage, sync, the target editor and export are now integrated.

Exact-week rows take precedence over private, effective-dated ongoing choices.
An explicit stop travels to other devices and cannot resurrect an older choice.
All seven authored values retain their null/zero meaning. The editor captures
the account and week when opened, retains typed values after recoverable
failures, and rejects an ongoing save after the week changes. Day and Week
read the values and source together and refresh when targets change without
a meal edit. JSON exports retain personal boundaries and stops alongside
the existing exact-week rows. The schema-30 upgrade adds no inferred rows;
the new hosted table has same-household privacy guards and finite-value checks.
Local reset and schema guards passed; all 46 hosted migration versions match.

Regression tests exposed the existing wrong-week editor save, a queued
midweek date, and a stale alternate-ID sync record replacing a newer stop;
each failed before correction. Old-device weekly rows retain their exact-week
meaning after migration. Target scope/stop controls are covered in accessibility
sweeps and light, dark, desktop and 3× captures.

Declaration for this group: a builder additionally proved four domain guards
by temporarily reversing exact-week precedence, removing the historical
cutoff, removing the exact-week user filter, and skipping stop boundaries.
Each experiment failed its focused test and the original source was restored.
These deliberate negative checks must appear in the PR's `NEGATIVE_TESTS`
field; under the repository policy this group requires Brendan's merge
decision after review and green CI. There is no unresolved implementation
deviation from the approved scope.

Brendan approved the merge on 2026-10-01; PR #120 merged as `d1f5899` with the
declaration retained. All checks passed on the approved candidate `cf3bdd8`.

## Group 6 — Cooking ingredient checklist

Approved: tappable ingredient checks in cook mode, retained for the current
local cook and reversible with another tap. Keep amounts and checked rows
visible. Reset ingredients is separate from directions and timers. Checks
remain independent of the partner, the shared recipe and shopping quantities.
No AI request is required. A worker owns the cook-session domain model and
cooking UI; persistence and the local schema are integrated serially after
Group 5's schema work.

Ingredient rows now retain quantities, section headings and a visible
**Prepared / added** state. Another tap undoes a check. A separate reset leaves
directions and timers intact; **Start over** explicitly clears the whole cook.
Checks remain device-local, keyed by stable ingredient IDs, and retain the
existing 24-hour cook expiry. Schema 31 adds an empty-default ingredient field
without altering saved direction progress. No server migration or AI call is
needed. Delayed restoration preserves fresh choices and updates a checklist
that is already open. Regression tests cover reopen/relaunch, expiry, reset,
undo, stale ingredient IDs and interruptions. The shared accessibility sweeps
now include the ingredient checklist and whole-cook reset confirmation, and
the cooking gallery captures checked rows and reset controls in every size.
A failed read is not treated as an empty cook: a scrollable explanation and
Retry preserve unseen saved progress and retain new choices in memory until
they can be merged safely. Tests proved failed reads, repeated failures and
disposed retry boundaries before correction. The same 3× recovery walk exposed
an existing all-steps timer label overflow; wrapping its label fixes the layout
without changing timer behavior. Native-device verification remains unperformed.

Fresh-context review identified a race when leaving and reopening the same cook
before the earlier visit had finished restoring and saving. Failing regressions
also exposed taps lost during a delayed save and old checks returning after
Start over. Shared per-recipe ordering now completes the earlier merge and save
before the next visit reads, while new taps stay responsive. Start over stops
timers immediately, preserves fresh choices and can complete after navigation.
A failed reset has a specific Retry Start over action; its regression failed
before the correction. Both recovery states participate in the accessibility
sweeps, with additional dark and 3× captures. No deliberate guard mutations were
used for this group.

The correction passed fresh-context review with 158 independent checks. After
Group 5 merged, the two cooking commits were rebased onto main; a whole-tree
comparison proved the result identical to reviewed candidate `3f703f6` before
this progress-record update. All final checks passed on `90cc2ef`; PR #121
merged as `08a8da9` on 2026-10-01.

## Group 7 — Faster grocery additions

Approved: optional quantity and unit on the first plain-item entry, with
name-only entry kept quick. Paste one nonempty line per item into an editable
review, with rename, removal and optional quantity controls. Flag exact
normalized-name duplicates within the batch and against the existing list;
skip them when saving and report the added/skipped counts. Preserve ambiguous
wording for the user to correct without AI parsing. Save against the latest
local household list without replacing existing amounts or check-offs, and
retain the draft after a recoverable failure. This scope builds on the typed
recipe shopping quantities already delivered in Group 3. No migration,
dependency or AI request is required. Two builders own the entry/review UI
and the domain/repository behavior separately; shared fixtures, specification
and validation stay with the coordinating agent.

One transaction reads the current list, validates the whole batch, skips
existing/repeated names, and saves accepted rows with their sync work. No-op
batches create no records or queue churn. Tests cover explicit fractions,
unknown amounts, food-backed duplicates, simultaneous commits, rollback,
household isolation and preservation through plan rebuilds. The UI keeps its
review open while saving, retains edits after failure, blocks repeated taps,
and expires held drafts after an account or household change. Addition
feedback preserves an existing Clear/Delete Undo. Failing regressions preceded
fixes for the lost draft, no-op display order and confirmation replacing Undo.
A separate visibility check reproduces clipped confirmation text at 3×;
the concise added/skipped count now fits the shopping viewport.
Light, dark, desktop and enlarged-text captures cover the new entry/review
surfaces; keyboard and 3× tests exercise both themes. Native-device validation
has not been performed. The coordinating agent independently ran formatting,
clean analysis, all 4,427 UTC tests (143 opt-in/time-zone skips), 35 calendar
and repository checks in New York, and all 119 render checks. Review and CI
results are recorded on [PR #122](https://github.com/gradybre/hearth/pull/122).

Fresh-context review found that a downward drag could close a pasted review
while its save was pending. Regressions reproduced both the lost Retry draft
after failure and an incomplete return to Shopping after success. The sheets
now keep the draft open during saving; Cancel, Back and tapping outside remain
available before saving and after a failure. The correction preserves typed
fractions and units, edited names, removals and the underlying plain-item draft.
The matching plain-sheet case did not reproduce the drag failure, but both
entry routes use the same dismissal protection. No remaining findings were
reported in the correction review; the independent design review also found
no actionable issues across the 40 phone, dark, desktop and 3× captures.

## Group 8 — Open meals from Plan

Approved: tap a meal's name to open its recipe or a read-only food summary,
with a separate large check retaining one-tap logging. Planned cooked recipes
get a Cook action using the saved recipe yield, separate from the person's
planned portion. Opening, cooking and returning leave the log unchanged.
Unavailable sources have an explanation, and restaurant meals receive no
Cook action. Exact Undo for logging/unlogging requires its own data safeguards
and remains a separate scope. No AI request, migration or dependency is needed.
The Plan owner handles row gestures and source navigation; the destination
owner builds a read-only current-food summary and unavailable-recipe handling.
Shared accessibility, gallery, specification and integration changes stay with
the coordinating agent. Current food details are distinct from the frozen
logged details approved separately below.

The coordinating agent independently checked the combined diff, ran the full
4,500-test UTC suite (159 opt-in/time-zone skips), 38 New York checks, clean
analysis and all 135 render checks, and inspected light/dark/3× captures.
New regressions preceded fixes for zero-calorie logging after a serving was
removed, unavailable recipe actions, a held action after deletion, and an Open
semantics node merging with the meal heading. Review-sheet saves retain their
reviewed amounts and verify recipe availability before committing.

Fresh-context code review found a held Log callback could still use the source
from an earlier frame. A behavioral regression failed before correction; logging
now resolves availability, nutrition and name together from the current library.
The complete coordinating-agent gates passed again after that change. Independent
design review inspected all 48 new captures and found no new release blocker. It
also recorded an inherited Plan display issue: an entirely unmatched recipe can
show zero calories while its detail explains unavailable nutrition. That separate
qualification change remains a future group. Native-device verification has not
been performed.

## Group 9 — Trustworthy logged portions and nutrition details

Approved: new food logs remember the parsed amount and unit or named serving
the person entered. View logged details shows the frozen name, portion and
nutrition. Corrections use the original serving and conversion evidence even
after a shared food changes. Older logs retain their saved servings with an
honest explanation that the original amount was not recorded; their corrections
use those frozen servings. Log again keeps its existing current-food nutrition
and stored-serving-count behavior. Preserving an amount entered earlier through
Plan only until a later log remains a separately scoped planning change.

The data work uses optional versioned snapshot evidence, with safe fallback for
unsupported or stale metadata and preservation through storage, sync and export.
No AI request or database migration is planned. Domain/data work can proceed
alongside Group 8; logging and standalone details follow its agreed API, while
shared Day rows and source navigation wait for Group 8's ownership to finish.

The logged-portion evidence is optional snapshot JSON, so it needs no database
migration or export-version change. Tests preserve it through a queued write,
a remote read on another local database, and JSON export, including unsupported
future records and unknown nested fields. Corrections retain the frozen name,
nutrition, coverage, conversion and recording time; Move keeps the recording
time separate from the diary date. Generic corrections cannot accidentally
revive stale amount evidence from an older client.

Independent design review prompted accurate fallback copy for unreadable or
stale evidence, while genuine older records still say the amount was not
recorded. Regression checks also caught wrapped action labels crossing their
button outline at 3× text. Both fixes passed focused checks before integration.

The complete Day flow exposes saved details from More, keeps the recorded
portion visible on the row, and offers a separate current-food view. Review
also caught an open planned editor mixing different versions of a food.
Entered amounts, nutrition and the receipt now use one definition. Pending
typing retains its original unit through library updates; removed units or
sources require a valid choice rather than creating a guessed log. Regression
failures preceded each correction, including continuing to type after an update.

## Group 10 — Adjustable cooking timers

Approved: existing timers gain +1 min, +5 min and Set time left. Running
timers keep running; paused timers stay paused; adding time to a finished
timer restarts it from now. Updates retain the timer's identity and recipe/step
linkage, survive local restoration, and reschedule the existing alert adapter
where supported. This group does not add custom timers, recipe-time parsing,
new background notification guarantees or AI. Timer implementation has disjoint
ownership from Groups 8 and 9; shared fixtures and accessibility registration
are integrated sequentially.

The same timer controls are available in Cook and the app-wide tray. Stored
updates are ordered, preserve timer and recipe/step identity, and cannot
recreate a timer that was stopped. Alert failures retain the saved countdown
and offer Retry alert without adding time again. Finished timers appear first
in Cook, with a persistent finished count when several timers are present.
The bounded tray keeps status and time readable at large text without hiding
the recipe; named finished announcements include offscreen timers.

Review regressions covered stale callbacks, rapid starts, alert failures,
elapsed storage reads, multiple finished timers and clipped large-text
readouts. A restored timer paused past its deadline gains the full extension
while staying paused. Each correction followed a behavioral failure. No migration,
dependency or AI change is required. Native background-alert delivery has
not been verified; the existing platform adapter remains the boundary.

## Group 11 — Exact Undo for one-tap logging

Approved: keep the existing Day row's one-tap Log/Unlog check, then offer Undo.
Restore the previous state with its saved portion, name, seven nutrients,
coverage, approximation qualifier, entered amount and original recording time.
A later edit, move or deletion makes the old action stale; Undo explains that
without overwriting newer work. New-entry logging, portion-correction Undo and
durable history are separate scopes. No AI, dependency or persistent schema
change is required.

The repository retains an in-memory action receipt with the exact prior row.
Connection-local SQLite revision tracking observes content changes from all
local writers, including sync, and catches edits changed back within the same
clock tick. A routine server confirmation with a later timestamp or equivalent
JSON encoding leaves Undo available. Unknown snapshot fields are preserved;
ambiguous duplicate JSON members are handled conservatively. This tracking
disappears with the connection and adds nothing to exported user records.

Feedback survives leaving the Day screen, expires with the account/household
session, and retains a safe Retry after a failed transaction. Ordinary Undo
uses the shared six-second window; assistive navigation and Retry retain their
action until used or dismissed. Rebuilt rows share an in-flight claim so a
second tap cannot replace the first tap's Undo. Other meals remain tappable.

Behavioral failures preceded fixes for null snapshot restoration, closed
connections, an unqualified restored timestamp, immediate identity changes,
rebuilt-row double taps, normal sync confirmations, and ambiguous JSON member
reordering. Retained taps after sync deletion were also checked; that suspected
issue did not reproduce and needed no product fix. The coordinating agent read
the full diff and independently passed formatting, clean analysis, all 4,716
UTC tests (189 opt-in/time-zone skips), 87 New York checks and all 165 gallery
render checks, including the new light, dark, desktop and 3× Undo captures.
Native-device validation has not been performed.

[PR #127](https://github.com/gradybre/hearth/pull/127) merged on 2026-10-01 as
`a0f1026`. All CI checks passed on `d1f22b5`; the merged tree is identical.
Fresh-context code review found no actionable issues and independently passed
127 focused UTC tests and 61 New York tests. Independent design review inspected
all 16 new captures and found no actionable issues.

## Group 12 — Readable Today and Week

Approved: give dates their own line on narrow screens or at enlarged text,
remove redundant headings, and offer a compact Day/Week choice. Preserve full
text scaling, date actions and ordinary phone/desktop navigation while bringing
a meaningful nutrition figure or meal into the initial viewport. No AI,
dependency, schema or data behavior changes.

Day and Week now use readable date headers with full date/year announcements
and 48-point date actions. A compact labelled menu replaces the Day/Week
segments when space is scarce. Compact summaries lead with a complete calorie
amount and unit; targets, remaining amounts, planned qualifiers and Week day
identity remain available at full text size. Ordinary phone headings keep
whole words, wrapping their actions below when needed. The shared Copy/Move
picker scrolls its title and choices while its wrapping action footer stays
reachable. Existing date navigation, saved-week actions, copy/move results and
Group 11's exact logging Undo retain their behavior.

Behavioral failures preceded repairs for the initial nutrition figure falling
below the usable viewport, ordinary-phone weekday wrapping, and an overflowing
Copy dialog with unreachable Cancel. Real-shell tests include the Home bar,
bottom tabs and safe areas at 320×568 with 3× text, plus ordinary phone and
desktop journeys in both themes. Dedicated picker journeys exercise Cancel,
multi-date Copy with sorted results, and Move with a changed meal slot using
the visible controls.

Fresh-context code review found a calendar-dependent test fixture: its fixed
2026 date would become a historical date, and its Monday could gain a Today
label. Both fixture boundaries were reproduced before correction. The ordinary
viewport fixture now uses a Wednesday in the current year outside the current
week; the existing strict viewport assertions remain. Separate checks retain
historical-date, New Year and Today coverage. No production correctness or
security findings remain. Independent design review inspected all 24 new
light, dark, desktop and 3× captures and found no actionable issues.

The coordinating agent read the full diff and independently passed formatting,
clean analysis, all 4,777 UTC tests (201 opt-in/time-zone skips), 85 New York
checks and all 177 render checks. The final fixture-only correction did not
change production or render code. Native-device and live screen-reader
acceptance have not been performed. [PR #128](https://github.com/gradybre/hearth/pull/128)
merged on 2026-10-01 as `c4a5a76`. All CI checks passed on `adae6c4`; the merged
tree is identical to that reviewed candidate.

## Groups 13–16 — Approved implementation queue

The user approved all four on 2026-10-01: “Approve those 4.” The exact accepted
scopes are recorded in UX_PHASE_2_APPROVALS.md. Group 13's archive/data lane,
Group 14's nutrition-receipt lane and Group 15's restaurant-usuals lane started
in separate worktrees from `c4a5a76`. The coordinating agent owns archive UI
and shared integration. Group 16 is approved and queued behind overlapping
editor/capture ownership and agent availability. The user subsequently approved
Groups 17, 18 and 19 through their separate decision cards. Groups 17 and 18
started in separate worktrees from `c4a5a76` as builder slots became available;
19's independent projection and screen also started from `c4a5a76`, with Day
entry points sequenced separately. Group 13's implementation is in integrated validation and
Group 14's receipt builder has finished, with shared logging integration under
coordinator validation. Groups 20–22 have actual decision cards and text
overviews; their answers remain pending.

Group 13's first independent source review identified missing planned serving
identity in the readable projection and cancellation waiting on a stalled photo.
Behavioral regressions reproduced both; corrected focused checks pass. The full
suite also caught three test-journey/fixture issues and a removed JSON photo
warning, addressed before the next gate. Group 14's first full run exposed
stale chip-label finders in 12 accessibility sweeps; those retain their selection
assertions while locating the new wrapping labels. Neither group is released
yet. Group 15's builder handed off 70 focused checks and four render scenes;
editor/router save-variation integration remains queued behind Group 14.

Group 13's corrected source review is clear; independent final UTC validation
passed 4,862 tests and the New York gate passed 60. The final complete visual
gate is running. Group 14's full pre-review suite passed 4,822 tests and its
render gate passed 185; review then found missing AI provenance, a snapped
calculation multiplier and unavailable history described as saved nutrition.
Behavioral regressions reproduced these; the corrected focused gate passes 38.
Those production changes require final release validation before publication.

Group 16 now has an independent builder for match review and capture context;
its editor/router return integration remains coordinator-owned. Group 17's
builder handed off 115 focused tests and 24 captures, and the integrated Week
journeys passed 51 filtered checks; full validation and fresh review are in
progress. Group 18's integrated checks passed 32; the full run exposed one old
button-copy assertion, and fresh review identified count-noun evidence and
item-specific spoken-label gaps. Corrections are in progress. Group 19 handed
off its snapshot-only projection and screen with 30 focused tests and 25 render
scenarios; Day integration follows Group 17. None of Groups 13–19 is described
as merged at this checkpoint. Groups 20–22 still await user answers.

## Group 13 merged; Group 14 final validation — 2026-10-01

Group 13 merged through [PR #129](https://github.com/gradybre/hearth/pull/129)
as `7a29de623afbc8a38c0ed5c66d79b026e6e0367c`. Every CI check passed on
independently reviewed head `a4ec2aff1759c8856b9d0a4dd8fed7effc9a1131`;
the merged tree is exactly `60d68678925c36da3300d97c347fb2944b3fc83f`.
Final root validation passed 4,862 UTC tests, 60 New York checks and 182
render checks. Source and visual reviews are clear; native sharing has not
been manually exercised.

Group 14's corrected candidate has been combined with the merged archive
without changing its tested tree. Root final validation passed 4,910 UTC tests,
45 New York checks and 190 render checks; format and analysis are clean.
Fresh source and final design reviews are clear. The receipt retains food-source
qualifiers, displays a truthful calculation multiplier and disables correction
when no usable frozen nutrition basis exists. Publication and exact published-head
review follow; this checkpoint does not claim Group 14 merged.

Group 17's independent source/design review is clear; its corrected original-base
suite passed 4,831 tests. Group 18's count-noun and item-specific spoken-label
corrections passed 116 focused checks and independent review. The two changes are
now in combined-tree validation with Groups 13–14 so shared screens and test
journeys are checked together before release.

Group 16's builder handed off 117 focused/render checks and 44 captures. Review
identified a camera-layout limitation and duplicate-wording ambiguity for correction
before production router/editor integration. Group 15 still needs its shared
save-variation handoff. Group 19 is building guarded handoffs from its captured
nutrition receipt; shared Day wiring remains sequenced behind Group 17.
Groups 20–22 remain unanswered; no work on those scopes is authorized yet.
