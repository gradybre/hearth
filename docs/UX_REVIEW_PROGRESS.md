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
writing: #49–#65 are all on `main`.

---

## Defects

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| F01a | Dirty-state guard on recipe/food editors | ✓ | ✓ | ✓ #49 | n/a | — |
| F01b | Recoverable local drafts (N01) | ✓ | ✓ | ✓ #51 | ✓ | — |
| F02 | Targeted shopping Undo | ✓ | ✓ | ✓ #50 | n/a | — |
| F03 | PDF page states: rendered vs extracted | ✓ | ✓ | ✓ #52 | n/a | — |
| F04 | Accumulated uncertainty; retry-safe batch save | ✓ | ✓ | ✓ #52 | n/a | — |
| F05 | Calendar-derived day labels; no constant "Today" card | ✓ | ✓ | ✓ #55 | n/a | — |
| F06 | Direct gram/ounce entry | ✓ | ✓ | ✓ #56 | n/a | — |
| F07a | Backoff wake-up | ✓ | ✓ | ✓ #53 | n/a | — |
| F07b | B02 reserve/settle, fail closed; record truncated usage | ✓ | ✓ | ✓ #54 | ✓ | B |
| F07c | Windows recovery protocol handler | — | — | — | n/a | B — needs a Windows machine or a Windows CI job; see below |
| F07d | Hosted recovery activation | n/a | n/a | n/a | B | B |

## Approved additions

| ID | What | Impl | Test | Review | Deployed | Verified |
|---|---|---|---|---|---|---|
| N01 | Recoverable drafts | ✓ | ✓ | ✓ #51 | ✓ | — |
| N02 | Move/copy a single meal entry | ✓ | ✓ | ✓ #57 | n/a | — |
| N03 | Usual restaurant orders | ✓ | ✓ | ✓ #60 | n/a | — |
| N04 | Recipe nutrition repair queue | ✓ | ✓ | ✓ #68 | n/a | — |
| N05a | Food reuse — `Use existing` | ✓ | ✓ | ✓ #69 | n/a | — |
| N05b | Reviewed merge | — | — | — | — | — |
| N08 | Menu maintenance and provenance | — | — | — | — | — |

Deferred by Brendan, not to be built: N06, N07, N09, N10, N11, N12.

## §10 defaults

| # | Default | Status |
|---|---|---|
| 1 | Keep warm identity; fewer repeated cards/headings/copy | ✓ (#61 desktop bounds, #62 shopping header, #63 filter rail, #64 one Add menu, #65 settings prose, #67 the week's four stacked headings) |
| 2 | Compact Today kept; Week becomes seven-day comparison | ✓ (Today cleanup #58; week as seven rows #67) |
| 3 | Direct gram/ounce entry and Move/Copy | ✓ (#55/#56/#57) |
| 4 | Restaurant search, selected review, usual orders | ✓ (#59/#60) |
| 5 | Settings index; shopping prep separated from the trip | ✓ (#58 reachable, #62 trip separated, #65 index) |
| 6 | Lost-edit and unsafe-Undo protection before visual work | ✓ (#49/#50/#51) |
| 7 | Import bookkeeping and operational gates before trial | ~ (#52/#53/#54, now deployed; F07c–d open) |
| 8 | Optional features approved individually | ✓ (N06/N07/N09–N12 deferred) |

## Packages

| Package | Status | Landed as |
|---|---|---|
| P0 Verify remaining scope | ✓ | baseline `ae57f62`, and the rows below |
| P1 Protect work | ✓ | #49 dirty guards · #50 targeted Undo · #51 drafts |
| P2 Import reliability | ✓ | #52 page states and retry-safe batch |
| P3 Operational completion | ~ | #53 backoff wake-up · #54 AI ceiling (**pushed and deployed**, not yet exercised) · F07c–d open |
| P4 Daily logging and navigation | ✓ | #55 day labels · #56 direct grams · #57 Move/Copy · #58 Today and Settings access |
| P5 Restaurant ordering | ✓ | #59 menu navigation · #60 selected summary and usual orders |
| P6 Lists and visual consolidation | ✓ | #61 desktop bounds · #62 shopping · #63 filters · #64 foods · #65 settings · #67 week |
| P7 Data maintenance | ~ | #68 repair queue (N04) · #69 `Use existing` (N05a) — N05b merge and N08 remain |
| P8 Optional additions | n/a | deferred by Brendan |
| P9 Household trial | — | B — needs an installed build on two phones |

## Known gaps in the guards themselves

Named rather than assumed, because a guard that is trusted further than it
reaches is worse than no guard.

- **The swept-surface guard is per *file*, not per sheet.** A second sheet
  added to a file that already has an entry ships with nothing walking it.
  Raised as its own task rather than widened inside a feature PR.
- **`pumpHearthApp` overrides the library streams**, so a food or recipe saved
  through the app never appears in a list in a widget test. Several assertions
  have to be written against what moves on screen instead; #64 says so where
  it matters.
- **No native build, golden or performance job in CI.** Every timing and every
  platform claim in this repository is a widget test on a laptop.

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
- **Settings prose** (§6.2.4): a sentence survives if it describes a
  consequence the label cannot. That cut the three under Light/Dark/Follow the
  device and the three under the start screens, and kept "this device only —
  it does not move anyone else's app", all of Cook together's, and everything
  attached to Your data and Sign out. #65.
- **Sign out stays on the settings index**, last and alone, rather than moving
  behind the Account page. It is the one control somebody needs in a hurry,
  and it is already isolated; burying it is not protecting it. #65.
- **A scope, not a filter** (§7.5): Foods shows your own or a restaurant's
  menus, both on screen, either one tap away. A filter that disappears a chain
  teaches people the menu is gone. #64.
- **Units** display preference: *As written / Metric / Imperial* (§7.5). Still
  unbuilt — a new feature rather than a reorganisation, and deliberately not
  folded into P6.
- §9.3 acceptance targets adopted as proposed.

## Schema

**Rule 8 is satisfied.** `supabase migration list` shows all 37 migrations
with local and remote agreeing; `20260915090000_ai_reservations`, the AI
ledger from #54, was pushed on 11 September 2026.

Pushing it was only half. The hosted `recipe-ai` function was still at v18,
built on 5 September — five days older than #54 — so it had never called
`reserve_ai_spend` and the table sat inert. Deployed as **v19** the same day,
which is what actually put the ceiling in force. Worth remembering as a shape:
a migration and the function that uses it are two deployments, and
`migration list` agreeing says nothing about the second.

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

## Installed builds

A release build of `a7938e1` was signed and installed on Brendan's iPhone on
11 September 2026 — `com.brendangrady.hearth` 1.0.0 (1), confirmed present
with `devicectl` rather than assumed from an exit code. It is signed against a
development team, so iOS expires the provisioning after about a week and the
app refuses to launch until it is reinstalled.

That is what moves the `Deployed` column to `✓` on the two draft rows: they
need no server, only a build carrying the local migration.

## Standing limits

Nothing in this repository can establish these; they are Brendan's to perform
and report.

- **The AI ceiling actually holding.** The table is there and the function
  that reads it is live, but nothing has yet reserved, settled, or been
  refused at the limit on the hosted project — that takes a real request and
  real money. Importing a recipe is the way to find out, and a bug in #54
  shows up as a refusal rather than as an overspend.
- Hosted password recovery: a real email received and its link completing,
  including **cross-device**, which same-device success does not imply.
- Two-device convergence on real phones.
- Screen-reader and physical-keyboard journeys.
- Native builds, signed installation, notifications.
- Performance on a representative device with 500 recipes, 1,000 foods and a
  year of logs. Widget-test timings are not a device result.
