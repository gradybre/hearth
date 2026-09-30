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
| 1 — Daily logging | UX-039, UX-041, UX-053 | Approved 2026-09-30 | Implemented; PR pending | 3,904 passed; analyze clean | Pending | Not performed |
| 2 — Grocery clarity | UX-058, UX-060 | Awaiting decision | Not started | — | — | — |

## Group 1 — Daily logging

- Personal recipe favorites and meal-relevant recents in the picker, optional
  Foods/Recipes scopes, all recents, and a separate remembered-portion review.
- Future entries default to planning; planned edits save the plan, with eating
  as a separate action. Today/past repeats retain their quick logging path.
- Consumed totals remain useful without targets, with honest missing-data
  labels and no invented goal comparisons.

This group does not include historical raw-portion storage (UX-040), target
carry-forward (UX-052), or the broader Today/Week layout change (UX-087).
No migration, paid AI request or new dependency is required.

Automated tests and rendered fixtures do not establish native screen-reader,
two-device sync or installed-build acceptance. Those remain distinct checks.

## Group 2 — Grocery clarity

Proposed: Remaining/All views, separate Bought/At home counts, more room for the
checklist with Add item prominent, and explicit Needed − Have = Buy quantities
with known package counts. No implementation is authorized until approved.
