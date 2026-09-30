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
| 2 — Grocery clarity | UX-058, UX-060 | Approved 2026-09-30 | Implemented in [PR #117](https://github.com/gradybre/hearth/pull/117) | 3,985 passed; analyze clean; 87 render checks passed; CI status on PR | Passed after corrections; code candidate `7d2121f` | Not performed |
| 3 — Recipe actions and nutrition | UX-001; recipe-detail scope of UX-010 | Awaiting decision | Not started | — | — | — |

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

Proposed: Plan and Shop directly from recipe detail, with a reviewed personal
date/meal/portion and a reviewed shared shopping quantity respectively. Plan
defaults to Today, Dinner and one personal serving, with Undo. Shop inherits
the displayed cooking yield and offers View list after adding. Recipe detail
also gains Per serving / Whole dish nutrition, retaining coverage labels and
large-text accessibility. No implementation is authorized until approved.

The nutrition portion of this group is limited to recipe detail; wording
parity in the editor, cook completion and log confirmation remains later
scope within UX-010.
