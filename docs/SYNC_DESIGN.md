# Sync: what is broken, and what replaces it

**Status:** design note for stabilization package D (R03, R04, R05, B01).
Written before code, per the handoff. Nothing here is implemented.

**Baseline:** `0226765`. Every claim below was read out of the current source;
where a doc comment already states an invariant, it is quoted rather than
paraphrased.

---

## 1. What is actually wrong

Five defects, of which **three are silent data loss** and two are new — they
are not in the handoff's inventory and were found while surveying for it.

### N02 — every record is stamped in the wrong timezone *(new, live, cheapest)*

`'updated_at': updatedAt.toIso8601String()` on a **local** `DateTime` emits no
`Z`, so Postgres reads it in the session zone. On this machine (UTC−4) a
record saved at 14:00 is stored as 14:00 UTC — four hours before it happened.

If the partner's watermark is already past that stamp, their device **never
pulls the record**. Not late: never, because the watermark only moves forward.

Seven call sites are wrong (`food_mapper:164`, `plan_mapper:162,194,205`,
`recipe_mapper:211`, `shopping_mapper:19,45`, `food_profile_repository:88`);
two are right (`collection_repository:130`, `ingredient_match_repository:129`),
which is what makes it a slip rather than a decision.

**Fix independently of everything else in this package.** One `.toUtc()` per
site, a test that asserts the serialised string ends in `Z`, and a guard so
the next mapper cannot forget.

### R04 — a pull silently keeps the oldest 1,000 rows

`max_rows = 1000` (`config.toml:16`), and it applies to stored procedures as
well as tables — so the `changed_*` RPCs are capped too. No pull sets a range,
a limit or a count; none reads `Content-Range`. **The client cannot see
truncation at all**: it receives exactly 1,000 rows and treats them as the
whole answer, then advances the watermark past everything it never saw.

The seeded catalogue alone is ~426 global foods, visible to every account,
before a single household food. `meal_plan_entries` reaches 1,000 in under a
year for two people. And that select has **no `order by`**, so which rows
survive truncation is arbitrary.

**Worst case is not the skip.** `recipe_favorites` and `recipe_collections`
are fetched *whole* every pass and used as the authoritative set:
`replaceFavorites` deletes every local row not in it. A truncated fetch there
does not skip records, it **deletes them locally** — and since the deletion is
local-only they come back next pass and thrash.

The comment justifying that design says "these are a handful of rows"
(`record_sync.dart:103-107`). That assumption is the defect.

### R05 — checkpoints are not scoped to anyone

The key is `'sync.watermark.$table'`, in the device-local `preferences` table.
No user, no household, no project. `signOut()` is
`_client.auth.signOut()` and nothing else: it clears the session, and leaves
the database, the outbox and all eleven watermarks exactly where they were.

So signing in as someone else on the same device means: every watermark is
already at ~now, so **none of their history is ever fetched** and the app
reports "synced"; the previous account's outbox is pushed under the new JWT,
refused by RLS, and retried for ever; and their rows stay on disk, reachable
by any by-id path and by the export.

### R03 — hard deletes never propagate *(fixed in D3)*

Recipes and foods soft-delete. Five tables hard-delete — `meal_plan_entries`,
`shopping_list_items`, `collections`, `plan_templates`, `ingredient_matches` —
and a plain select only ever returns rows that exist. There is no tombstone
and no `is_deleted` on any of them, so a meal your partner deleted stays on
your phone permanently. Worse, an upsert replayed from the outbox **resurrects
a row the other device deleted**, with nothing to stop it.

### B01 — a sync requested during a sync is dropped, and failures retry for ever

`if (_running …) return;` with no pending-rerun flag: a write made while a
pass is in flight is simply not synced until something else happens to
trigger one. And `markFailed` increments `attempts` — which **nothing reads**.
No cap, no backoff. A permanently-rejected write retries on every pass for
ever, *and* blocks its record's pull for ever via `hasPendingFor`.

`macro_targets` reliably generates one: the table has
`unique (user_id, week_start_date)` but the client mints a **random** id, so
two devices setting a week's targets offline produce two ids for one
constrained pair and the loser is poisoned permanently. (Days, shopping items
and ingredient matches all use deterministic uuid5 and are safe.)

Photo sync already solved this — `maxAttempts = 5`, enforced in the candidate
query. The outbox never learned.

---

## 2. The invariant the design has to earn

> **A write committed during a multi-page pull is eventually fetched.**

Today's answer is a client clock minus a 60-second overlap, which is a guess
about clock skew rather than a guarantee, and it is defeated by N02 outright.

**The design: a full paginated reconciliation, not an incremental feed.**

For two people and a library of hundreds, a bounded complete snapshot is
simpler than a correct incremental cursor and has a property no cursor has —
it cannot skip. Each pass fetches every accessible row for a scope, in a
deterministic order, page by page, and reconciles the local store against it.

Why this rather than a cursor: a cursor has to answer "what if a row is
committed with a timestamp inside a page I have already read", and every
honest answer is either a server-side sequence with commit-order handling or
an overlap window that is a guess. A full reconciliation answers it by not
asking — a row committed mid-pull is either in this pass or the next one, and
the next one reads everything again.

**What that costs:** ~500 recipes and ~1,000 foods is a few hundred KB per
pass, and passes are triggered by writes and by resume, not on a timer. If
that becomes wrong, an incremental feed can be added *underneath* the
reconciliation as an optimisation, with the reconciliation as the backstop —
which is the right order to build them in anyway.

**What it does not change:** push before pull; whole-record last-write-wins;
a record with an unsent local write is never overwritten. Those three are
sound and already tested.

---

## 3. What has to be decided before code

| Decision | Proposed | Why it is not obvious |
|---|---|---|
| **Deletion** | ~~Reconciliation, not tombstones~~ → **soft delete, as recipes and foods already do** | *Settled by Brendan, against this row's original proposal.* The choice was framed as reconciliation versus a separate tombstone table, and both were worse than the option already in the codebase. Soft-deleting in place needs no retention policy, no second mechanism, and no id sweep whose cost grows with every meal ever logged on a pass that fires after every local write — and last-write-wins, which is already sound and already tested, makes a delete beat an older edit for free. Reconciliation stays available as a backstop if it is ever needed. |
| **Checkpoint key** | `sync.v2.<project>.<stream>.<owner>` | Must include project so a staging swap cannot poison production, and owner so §R05 cannot recur. v2 so old unscoped keys are never read as if they were complete. |
| **Repair** | Version marker; first run of v2 ignores every v1 watermark and reconciles fully | The current watermarks may already have advanced past rows never seen. They cannot be trusted, only discarded. |
| **Sign-out** | Clear watermarks and *keep* the outbox and rows | Deleting unsynced work to fix a scope bug would be the cure being worse. Rows stay, scoped queries already hide them, and the export needs a scope filter (a separate finding). |
| **Ordering** | Parent tables before children, as today, but *within one transaction per page* | Today a mid-pull failure leaves earlier tables' watermarks advanced and later ones not. |
| **Retry** | 2s, 5s, 15s, 30s, 60s, then stop the burst; cap attempts; keep the work | Matches photo sync, which already got this right. |
| **Dirty flag** | Set when a sync is requested during a pass; rerun once at the end | One flag, not a queue — coalescing bursts is the point. |

---

## 4. Order of work

N02 first and alone — it is live, it is four hours of every record, and it
needs none of the rest.

Then D in three PRs rather than one, because a single diff spanning
pagination, scope, deletion and repair is not reviewable:

1. **D1 — pagination.** Bounded pages, deterministic order, truncation
   detectable. No behaviour change beyond completeness.
2. **D2 — scope.** Versioned scoped keys, the v1 discard, sign-out clearing,
   a scope token captured at pass start and checked before applying.

   *As built,* with one deliberate difference. Sign-out clearing was listed
   here as part of what keeps two accounts apart; once the keys are scoped it
   cannot be, because a scoped key is unreadable by the wrong account by
   construction. Clearing on **every** sign-out would then be pure cost — a
   full library re-download each time a session expires. So it is wired to an
   *explicit* sign-out only, and its job is different: it is the repair lever
   for a checkpoint that has moved past a row the server can no longer offer
   (a restore from backup, or a timestamp bug like N02). "Sign out and back
   in" is what somebody will try, and it now does something.

   Both sync paths keep their own copy of the pull loop, so the key, the v1
   disposal and the scope check live in one `SyncCheckpoints` rather than
   twice — and both paths have their own regressions, because covering one of
   two twins is how D1b's paging guard nearly shipped half-blind.

   A pass therefore checks itself against **two** things, not one: the
   identity it began under, and how many times the checkpoints had been
   deliberately cleared. The second exists because the first does not cover
   the repair lever's own race — someone taps Sync now and then Sign out, the
   sweep runs while the pass is still working through its tables, and the pass
   writes its checkpoint straight back over it. Same account throughout, so
   nothing about the scope changed; the clearing count is what moves.

   The memberships stage gets its own check, after its fetches and before it
   writes. It is the only stage that *replaces* rather than merges — rows the
   server did not send are deleted locally — so run under a session that
   changed underneath it, it would not write the wrong favourites so much as
   delete the right ones.
3. **D3 — deletion.** *Split in two.*

   **D3a — propagation.** The five hard-delete tables soft-delete, the way
   recipes and foods always have: the row stays, `is_deleted` turns true, and
   the ordinary watermark pull carries it across. Each device removes its own
   copy on the way past — local storage is a cache of what exists, so there is
   nothing there for a tombstone to be useful for. The two membership tables
   keep hard deletes deliberately: they are fetched whole and reconciled by
   replacement every pass, so absence there is already read correctly, and a
   flag as well would be a second mechanism for the same fact.

   **D3b — the resurrection guard.** An upsert replayed from the outbox could
   clear `is_deleted` on a row another device deleted, and D3a made that reach
   *further*: all five record payloads now state `is_deleted` explicitly, so
   every replayed upsert is a resurrection attempt. One trigger across all
   seven soft-deleting tables, because recipes and foods have had the same
   hole since they were built.

   **Not compared against `updated_at`.** Every one of these tables has a
   `touch_updated_at` trigger, so the stored value is the *server's* clock
   while the incoming one is the writer's. Comparing across the two means a
   phone two seconds slow cannot undo its own deletion — the Undo looks older
   than the tombstone it is undoing. So the tombstone records the deleting
   writer's stated time in `deleted_at`, and the comparison is client clock
   against client clock: strictly increasing on one device, and across two it
   rests on the assumption the rest of sync already rests on.

   Only the flag is held, not the whole write. A tombstone whose other columns
   took a stale value is invisible either way, and refusing the write outright
   would strand it in the outbox for ever.

**E — B01's retry and status** follows, and is where "Synced" stops being a
claim the app cannot support.

*As built.* Both halves, and one small departure. The decision table proposed
"2s, 5s, 15s, 30s, 60s, then stop the burst; cap attempts" and a dirty flag —
which is what shipped, with the last delay repeating rather than growing: the
cap is what ends the retrying, so a sixth delay would never be reached and a
growing one would only obscure that.

The coalescing rule lives in its own `SyncGate` rather than as two fields on
the controller. Not for tidiness: the controller's own path needs a signed-in
session, a live database and a platform binding before it reaches that
decision, so a test aimed at it through the controller returns early and
passes without ever exercising the rule. That is the shape of vacuous test
this project has now caught three times, and it is cheaper to make the rule
reachable than to keep catching it.

What E does **not** do is repair the write that provokes it. `macro_targets`
mints a random id against a unique `(user_id, week_start_date)`, so two
devices setting a week's targets offline still produce two ids for one
constrained pair, and the loser is still refused for ever. It now stops
asking, and says so, instead of retrying silently until the end of time — but
the poisoning itself is a separate finding and a separate fix.

### Deploy order, both directions

D1b's paged functions are the first place the client hard-depends on
something only a migration provides, so the ordering is now load-bearing in a
way it was not before.

**Server first, then the client.** A build that calls `changed_recipes_page`
against a database without it gets PostgREST's `PGRST202`, which is a
`PostgrestException` and not a `SocketException` — so it is *not* converted
to `RemoteUnavailable`, and it escapes `LibrarySync.pull()` to
`SyncController.sync()`. The library pull, the record pull and both photo
passes are all skipped for that run. It is loud (`SyncStatus.failed`) and it
recovers the moment the migration lands, so it is an outage rather than
corruption — but it is an outage gated on the step CLAUDE.md rule 8 exists
because this repo has already missed it three times.

The other direction is already handled: the unpaged `changed_recipes` and
`changed_foods` stay in place for phones on an older build, and a guard
asserts they are still there.

Deliberately **no client-side fallback to the unpaged function**. Falling back
would restore exactly the silent truncation this package exists to remove, and
would do it at the one moment nobody is watching.

---

## 5. What this note does not settle

- **Whether the hosted `max_rows` is 1,000.** `config.toml` configures the
  local stack only; the hosted value is a dashboard setting not tracked in
  this repo. It must be read before the pagination size is chosen.
- **Whether reconciliation is affordable at 10× the current library.** It is
  at today's size. The measurement belongs in D1.
- **The export's scope filter.** `RecipeRepository.byId` is deliberately
  unfiltered and the export follows it, so a previous account's rows can leave
  the device. Real, out of scope here, tracked separately.
