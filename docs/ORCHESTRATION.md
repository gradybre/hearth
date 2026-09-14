# How work is dispatched

Adapted from an architecture Brendan brought over on 14 September 2026, built
for a different project with a planner agent and a memory ledger. Two of its
rules generalise and are the reason this file exists; the rest is fitted to
this repository and some of it is deliberately dropped.

The two that generalise:

1. **Ownership is the concurrency primitive.** Two pieces of work may run at
   once exactly when the sets of files they own are disjoint. No locks, no
   merge strategy.
2. **An agent's report is a hypothesis.** Re-run everything and read the code,
   not the summary.

Both earned themselves here on the first day. Two lanes ran concurrently with
disjoint ownership and produced no conflict; and of the two that reported a
clean gate, one was right about the tests and still had three real defects a
reading found.

---

## 1. Ownership

Work that fans out declares what it owns — file paths, a trailing `/` meaning
everything beneath. Two lanes may run together iff their sets are disjoint.

Three rules that come from being burned elsewhere and are kept verbatim:

- **A lane in review still owns its files.** Its pull request is open; a second
  lane editing them produces the conflict the model exists to prevent.
- **A lane owning nothing is an error**, because nothing serialises it.
- **A shared append point is a conflict generator**, whatever else it is.

## 2. The files no lane may own

These are appended to by nearly every change, so they cannot be owned without
serialising everything. Lanes **report what they owe** and the orchestrator
applies it serially, against the tree as it actually stands.

| File | Why it is a conflict generator |
|---|---|
| `test/support/swept_surfaces.dart` | Every new sheet or dialog appends an entry |
| `test/support/app_harness.dart` | Every new adapter adds a named parameter |
| `lib/app/providers.dart` | ~1,400 lines; every feature appends |
| `supabase/migrations/` | **Timestamp-named — two lanes reach for the same one.** See §3 |
| `supabase/migrations/.applied.json` | One manifest of every migration |
| `lib/data/local/hearth_database.dart`, `lib/core/build_info.dart` | `schemaVersion` must move in both at once |
| `drift_schemas/`, `test/data/local/generated_migrations/` | Regenerated wholesale, one version at a time |
| `docs/HEARTH_SPEC.md` | Nearly every change amends it |
| `CLAUDE.md`, `.github/workflows/ci.yml`, `pubspec.yaml` | One shared document each |
| `test/render/gallery.dart` | One scene list |

The value here is not conflict avoidance. It is that a lane computing against
a base that moved underneath it gets the answer wrong *without being wrong* —
a stale line number, a name already taken, a total from before another lane
landed. Only an actor with the current tree in front of it catches that.

## 3. Pre-assigned migration timestamps

A migration is named `YYYYMMDDHHMMSS_name.sql`, and two lanes adding one on the
same day will both reach for the same plausible minute. This is the same
insight as ownership: a shared counter with no allocator collides by
construction.

So the orchestrator assigns the timestamp before a lane starts, and
`test/architecture/migrations_are_history_test.dart` refuses a duplicate.

## 4. Declaration blocks

Every pull request body ends with three fields. All three must be present.

```
DEVIATIONS: none
NEGATIVE_TESTS: none
BLOCKED: none
```

**All three reading `none`, and CI green on every check → the pull request
merges itself.** Anything else — a non-empty field, a missing field, a red or
pending check — stops and waits for Brendan.

Missing has to stop, or the lane that never wrote the section is exactly the
one whose exceptions stay invisible.

- **DEVIATIONS** — where the work differs from what was asked, including
  anything deliberately not done. Never ranked, only surfaced: a lane that
  overrules its brief citing something that outranks it may well be right, and
  a rule that ranked it would be wrong half the time.
- **NEGATIVE_TESTS** — which new guards were proven able to *fail*, by breaking
  them on purpose. A gate that has only ever passed is indistinguishable from
  a gate that does nothing. This replaces a mutation-testing field from the
  original; there is no mutation testing here and a field nobody can fill
  honestly is worse than no field.
- **BLOCKED** — **"this change is not safe to merge", and nothing else.** Not
  "downstream work remains blocked". A gate that punishes a lane for honestly
  scoping what it did not claim gets lied to.

## 5. Verification is the orchestrator's, always

Solo or fanned out, before anything lands:

```bash
dart format . && flutter analyze
flutter test > /tmp/hearth-test.log 2>&1; echo "EXIT: $?"
```

Read the exit code, never the tail. Then **read the diff**, not the summary.

When a lane reports, the report is where to look, not what to conclude.

## 6. A check that does not run is not a gate

`HEARTH_RENDER=1 flutter test test/render` is not in CI, and the House gallery
scenes sat broken across three merges because of it. An env-gated check is not
a gate; it is a thing somebody has to remember. Either put it in CI or treat
its result as unknown.

`deno lint` was missing from CI for the same reason, and a duplicate `case`
shipped that silently made a whole branch unreachable — `deno check` passes on
that happily.

## 7. What this cannot do

Worth writing down, because the structure invites more trust than it has
earned:

- **It cannot see work nobody queued.** Nothing detects a task that was never
  added.
- **It cannot tell a narrower implementation from a complete one.** A lane that
  implements half a requirement, correctly, passes everything.
- **It cannot catch a value that is wrong but self-consistent.** The shopping
  list said "4 lb" of a sauce sold in 24-ounce jars: every test passed, every
  number was right, and the answer was useless.

## What was dropped, and why

- **The planner tier.** The original has a planner outside the process that
  rules on questions an executor may not decide. There is no second party
  here, so `astra_ruling` and `human` collapse into Brendan.
- **The review packet and inbox.** Both exist to feed that planner. With one
  person, a pull request body is the packet.
- **`SURVIVED_MUTANTS`.** See §4.
