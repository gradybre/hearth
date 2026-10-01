# Phase 2 UX implementation

Tracks approvals and implementation from [HEARTH_UX_REVIEW.md](../HEARTH_UX_REVIEW.md).
The review is an assessment of its stated baseline; this file records subsequent work.
The earlier [UX review progress](UX_REVIEW_PROGRESS.md) covers a separate review.

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
| 6 — Cooking ingredient checklist | UX-018 | Approved 2026-10-01 | Implemented in [PR #121](https://github.com/gradybre/hearth/pull/121) | 4,339 passed in UTC; 50 checks in New York; clean analysis; 115 render checks passed; final CI tracked on the PR | No actionable findings after the persistence correction; reviewed code unchanged by rebase onto main | Not performed |
| 7 — Faster grocery additions | UX-061, plain-item quantity and reviewed paste scope | Awaiting decision | Not started | — | — | — |

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
this progress-record update. Final CI and merge status are recorded on PR #121.

## Group 7 — Faster grocery additions

Proposed: optional quantity and unit on the first plain-item entry, with
name-only entry kept quick. Paste one nonempty line per item into a review
list with duplicate notices before adding. Leave ambiguous quantity wording
as text for the user to correct. This scope builds on the typed recipe
shopping quantities already delivered in Group 3. No AI request is required.
Implementation awaits approval and an available worker.
