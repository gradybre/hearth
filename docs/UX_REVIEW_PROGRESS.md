# UX review — progress

Tracks every finding and approved feature in
[HEARTH_PRODUCT_UX_REVIEW_2026-09-10.md](HEARTH_PRODUCT_UX_REVIEW_2026-09-10.md).
Baseline `ae57f62`.

**The five columns mean different things and are never inferred from each
other.** A green CI run is not a passed email, cart, camera, notification,
keyboard, or two-device test (review §9.2).

- **Impl** — code written and merged to `main`.
- **Test** — an automated test holds the behaviour, and for a defect a failing
  regression test was demonstrated *before* the fix. `✓` here says the test
  was written and is green, not that it is guarding `main`: read it with the
  Impl column, which is the one that says whether any of it has merged.
- **Review** — shipped through a PR with a fresh-context review over the diff.
- **Deployed** — migration pushed to the hosted project, or Edge Function
  deployed. Blank where the change needs neither.
- **Verified** — a human performed the real-world check. Only Brendan can move
  this column for hosted recovery, real-device sync, installed builds, and
  screen-reader passes.

Status: `—` not started · `~` in progress · `✓` done · `n/a` not applicable ·
`B` waiting on Brendan.

`~` on Impl means the code is written and the PR is open, not merged. It
becomes `✓` when Brendan merges it. Nothing is open at the time of
writing: #49–#57 are all on `main`.

---

## Defects

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| F01a | Dirty-state guard on recipe/food editors | ✓ | ✓ | ✓ #49 | n/a | — |
| F01b | Recoverable local drafts (N01) | ✓ | ✓ | ✓ #51 | B | — |
| F02 | Targeted shopping Undo | ✓ | ✓ | ✓ #50 | n/a | — |
| F03 | PDF page states: rendered vs extracted | ✓ | ✓ | ✓ #52 | n/a | — |
| F04 | Accumulated uncertainty; retry-safe batch save | ✓ | ✓ | ✓ #52 | n/a | — |
| F05 | Calendar-derived day labels; no constant "Today" card | ✓ | ✓ | ✓ #55 | n/a | — |
| F06 | Direct gram/ounce entry | ✓ | ✓ | ✓ #56 | n/a | — |
| F07a | Backoff wake-up | ✓ | ✓ | ✓ #53 | n/a | — |
| F07b | B02 reserve/settle, fail closed; record truncated usage | ✓ | ✓ | ✓ #54 | B | — |
| F07c | Windows recovery protocol handler | — | — | — | n/a | B — needs a Windows machine or a Windows CI job; see below |
| F07d | Hosted recovery activation | n/a | n/a | n/a | B | B |

## Approved additions

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| N01 | Recoverable drafts | ✓ | ✓ | ✓ #51 | B | — |
| N02 | Move/copy a single meal entry | ✓ | ✓ | ✓ #57 | n/a | — |
| N03 | Usual restaurant orders | — | — | — | n/a | — |
| N04 | Recipe nutrition repair queue | — | — | — | n/a | — |
| N05 | Food reuse, then reviewed merge | — | — | — | — | — |
| N08 | Menu maintenance and provenance | — | — | — | — | — |

Deferred by Brendan, not to be built: N06, N07, N09, N10, N11, N12.

## §10 defaults

| # | Default | Status |
|---|---|---|
| 1 | Keep warm identity; fewer repeated cards/headings/copy | — |
| 2 | Compact Today kept; Week becomes seven-day comparison | ~ (Today cleanup #58; Week in P6) |
| 3 | Direct gram/ounce entry and Move/Copy | ✓ (#55/#56/#57) |
| 4 | Restaurant search, selected review, usual orders | — |
| 5 | Settings index; shopping prep separated from the trip | ~ (reachable everywhere #58; index in P6) |
| 6 | Lost-edit and unsafe-Undo protection before visual work | ✓ (#49/#50/#51) |
| 7 | Import bookkeeping and operational gates before trial | ~ (#52/#53/#54; F07c–d open) |
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

- **N02** Move keeps its snapshot untouched — that is the whole reason it
  exists rather than a delete and a re-log. "Plan this again" makes a
  *planned* entry with no snapshot at all, so it is costed from the food as
  it stands when it is eventually logged: a snapshot freezes at log time and
  at no other time. Both are said in words on the sheet. (This supersedes an
  earlier note here that had Copy re-freezing the original's macros; the
  design review settled it the other way.)
- **B02** fails closed: import, generation and label reading refuse while the
  spend counter is unreadable; logging, cooking and everything manual are
  unaffected.
- **Units** display preference: *As written / Metric / Imperial* (§7.5).
- §9.3 acceptance targets adopted as proposed.

## Schema

Local `schemaVersion` is **26** — `editor_drafts`, added by #51. Device-local
and never synced, so there is **no Supabase migration and nothing to push**;
`Deployed` is marked `B` on the draft rows only because installing a build
carrying the local migration is Brendan's step, not because a server needs
anything.

`drift_schemas/` now holds v25 and v26, which is what made the first genuinely
historical migration test possible — v25 built as v25 was, migrated for real,
checked against v26.

## Why the Windows handler is still open

It needs a registry entry under `HKCU\Software\Classes\hearth`, written
either by an installer this repository does not have or by the app at startup
in `windows/runner`. Either is platform C++ that cannot be compiled, run or
tested from here — there is no Windows machine and no Windows CI job (one of
WP8's open items). Writing it blind and reporting it done would be a claim
nothing supports, so it stays named instead.

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
