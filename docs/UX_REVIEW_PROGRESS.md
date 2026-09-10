# UX review — progress

Tracks every finding and approved feature in
[HEARTH_PRODUCT_UX_REVIEW_2026-09-10.md](HEARTH_PRODUCT_UX_REVIEW_2026-09-10.md).
Baseline `ae57f62`.

**The five columns mean different things and are never inferred from each
other.** A green CI run is not a passed email, cart, camera, notification,
keyboard, or two-device test (review §9.2).

- **Impl** — code written and merged to `main`.
- **Test** — an automated test holds the behaviour, and for a defect a failing
  regression test was demonstrated *before* the fix.
- **Review** — shipped through a PR with a fresh-context review over the diff.
- **Deployed** — migration pushed to the hosted project, or Edge Function
  deployed. Blank where the change needs neither.
- **Verified** — a human performed the real-world check. Only Brendan can move
  this column for hosted recovery, real-device sync, installed builds, and
  screen-reader passes.

Status: `—` not started · `~` in progress · `✓` done · `n/a` not applicable ·
`B` waiting on Brendan.

---

## Defects

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| F01a | Dirty-state guard on recipe/food editors | — | — | — | n/a | — |
| F01b | Recoverable local drafts (N01) | — | — | — | — | — |
| F02 | Targeted shopping Undo | — | — | — | n/a | — |
| F03 | PDF page states: selected/rendered/extracted/accepted | — | — | — | n/a | — |
| F04 | Persistent per-row uncertainty; retry-safe batch save | — | — | — | — | — |
| F05 | Calendar-derived day labels; no constant "Today" card | — | — | — | n/a | — |
| F06 | Direct gram/ounce entry | — | — | — | n/a | — |
| F07a | Connectivity retry + backoff wake-up | — | — | — | n/a | — |
| F07b | B02 reserve/settle, fail closed; record truncated usage | — | — | — | — | — |
| F07c | Windows recovery protocol handler | — | — | — | n/a | B |
| F07d | Hosted recovery activation | n/a | n/a | n/a | B | B |

## Approved additions

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| N01 | Recoverable drafts | — | — | — | — | — |
| N02 | Move/copy a single meal entry | — | — | — | n/a | — |
| N03 | Usual restaurant orders | — | — | — | n/a | — |
| N04 | Recipe nutrition repair queue | — | — | — | n/a | — |
| N05 | Food reuse, then reviewed merge | — | — | — | — | — |
| N08 | Menu maintenance and provenance | — | — | — | — | — |

Deferred by Brendan, not to be built: N06, N07, N09, N10, N11, N12.

## §10 defaults

| # | Default | Status |
|---|---|---|
| 1 | Keep warm identity; fewer repeated cards/headings/copy | — |
| 2 | Compact Today kept; Week becomes seven-day comparison | — |
| 3 | Direct gram/ounce entry and Move/Copy | — |
| 4 | Restaurant search, selected review, usual orders | — |
| 5 | Settings index; shopping prep separated from the trip | — |
| 6 | Lost-edit and unsafe-Undo protection before visual work | — |
| 7 | Import bookkeeping and operational gates before trial | — |
| 8 | Optional features approved individually | ✓ (N06/N07/N09–N12 deferred) |

## P0 — baseline

| Item | Status |
|---|---|
| Findings verified against current code | ✓ |
| Spec §5.6 "never a target" reconciled | ✓ |
| Spec §5.7 Walmart cart API reconciled | ✓ |
| `macros.dart` comment reconciled with `dailyValue`/`isFloor` | ✓ |
| `AGENTS.md` made a pointer to `CLAUDE.md` | ✓ |
| Repeatable screen gallery (review §9.1) | ✓ |
| This checklist | ✓ |

## Decisions taken

- **N02 Copy** reproduces the frozen portion and re-freezes the same macros.
  Move keeps its snapshot untouched. One meaning in every menu.
- **B02** fails closed: import, generation and label reading refuse while the
  spend counter is unreadable; logging, cooking and everything manual are
  unaffected.
- **Units** display preference: *As written / Metric / Imperial* (§7.5).
- §9.3 acceptance targets adopted as proposed.

## Standing limits

Nothing in this repository can establish these; they are Brendan's to perform
and report.

- Hosted password recovery: a real email received and its link completing,
  including **cross-device**, which same-device success does not imply.
- Two-device convergence on real phones.
- Screen-reader and physical-keyboard journeys.
- Native builds, signed installation, notifications.
- Performance on a representative device with 500 recipes, 1,000 foods and a
  year of logs. Widget-test timings are not a device result.
