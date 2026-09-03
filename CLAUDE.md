# Hearth — House Rules

Hearth is a private household app (Flutter + Supabase) targeting **iOS, macOS, and Windows**.
v1 ships **one pillar only: Food & Meal Planning**, built end to end.

**The full spec is [docs/HEARTH_SPEC.md](docs/HEARTH_SPEC.md) — it is the source of truth.**
Read it before planning or building any area. This file holds only the standing rules that
must never be re-litigated; it deliberately does not duplicate the spec. If the two ever
conflict, the spec wins and this file gets fixed.

**Success bar:** Hearth wins when Brendan and his partner have fully replaced MacrosFirst for
daily logging for two straight weeks. Every scope call is judged against that — logging speed
beats cozy/AI features when they compete.

---

## Non-negotiables

These are load-bearing. Do not trade them away for convenience, and flag it explicitly if a
task seems to require breaking one.

1. **Publishable key only in the client.** The app ships `sb_publishable_…` and nothing else.
   `sb_secret_…`, the Claude API key, and USDA keys live **server-side only** (Edge Function
   secrets via `supabase secrets set`). Never in the repo, the app bundle, or a code sample.
   Use the new publishable/secret key format, not legacy anon/service_role. (§8.1)

2. **RLS default-deny on every table.** Because the client key is public, RLS *is* the security
   boundary. Every new table gets RLS enabled and explicit policies in the same change that
   creates it — never "add policies later." Household-scoped vs. user-scoped is a deliberate
   split; check §4/§8.2 before assuming which one a table is.

3. **Frozen log snapshots.** Every log entry stores `macro_snapshot` (macros + portion at log
   time). Editing or deleting a recipe/food later must never rewrite past days. Recipes and
   foods are **soft-deleted**, never physically removed. (§4)

4. **Review before save / before commit.** Anything automated that produces user data — AI
   import, AI generation, shopping export — passes through a mandatory human review screen
   first. No silent writes to the library, no silent external hand-offs. (§5.3, §5.4, §5.7)

5. **Tests alongside the build, not after.** Author the automated tests for an area as part of
   building that area, per §9 — unit tests for the pure Dart logic first (conversion, scaling,
   macro math, aggregation, snapshot integrity). An area is not done until its suite is green
   and handed off for Brendan's manual pass. Every bug found gets a failing regression test
   **before** the fix. (§9.7, §9.9)

6. **Accessibility baseline is not optional.** Dynamic type honored, semantics labels on all
   interactive elements, reduced motion respected, and **never color alone** for meaning
   (over/under macro states carry an icon or label too). (§6.3)

7. **External integrations sit behind interfaces.** Nutrition sources (OFF → USDA → manual) and
   the shopping/Walmart export are swappable adapters. Never call them directly from UI code.

8. **A migration is not done until it is pushed.** `supabase db reset` proves the SQL is right;
   it says nothing about the database the app actually talks to. Three migrations once sat
   local-only: the phone kept writing `is_default`, the hosted `upsert_food` had never heard of
   the column, and every pull quietly reverted it — three features silently broken while every
   local check passed and every commit said "migration applied". Finish a schema change with
   `supabase db push`, and confirm with `supabase migration list` that local and remote agree.

## Working style

- **Plan Mode first for anything non-trivial.** Read the relevant spec section, propose the
  plan, get agreement, then build.
- **Build order is §10.** Don't pull work forward from a later phase without asking.
- **Deferred is deferred.** §12 lists what is explicitly out of scope for v1 — don't
  helpfully add micronutrients, sub-recipes, voice control, weight tracking, etc.
  Two things have been lifted from it deliberately, and are in scope: pantry
  quantity subtraction (phase 4), and **fibre, sodium and cholesterol** as optional
  nullable nutrients (§5.6). Lifting one is Brendan's call and amends the spec in
  the same change — never a quiet addition.
- **Open decisions are Brendan's** (§12). Surface them, don't quietly decide them.
- Flag spec gaps and contradictions instead of inventing an answer.
- Prefer small, reviewable changes over large sweeping ones.

## Design language

Warm, rustic, cozy — a home, not a calorie cop. Paper-cream surfaces, cocoa/wood-brown text,
a single terracotta/amber accent (60/30/10, 2–4 colors total). Serif for recipe titles,
humanist sans for body and data. Theme tokens and dark mode from day one; ship light first.
Kitchen-first legibility in cook-along and logging. (§6.1)

## Secrets hygiene

- The app's runtime config lives in `config/local.json` — **gitignored** — and is passed in
  with `--dart-define-from-file`. It holds only `SUPABASE_URL` and the
  `sb_publishable_…` key, which are public by design. `config/example.json` is the
  committed template: key names, empty values.
- `sb_secret_…`, the Claude API key, and USDA keys go in Edge Function secrets
  (`supabase secrets set`) and nowhere else — never in `config/`, never in the repo.
- Never paste a real key into a commit, a test fixture, a log line, or a chat message.
- If a secret ever lands in a commit or a bundle: say so immediately and rotate it. Do not
  quietly amend the history and move on.

## Commands

```bash
flutter pub get                       # install dependencies
flutter analyze                       # static analysis (must be clean)
dart format .                         # format
flutter test                          # unit + widget + golden tests
HEARTH_LIVE=1 flutter test --tags live test/integration   # against local Supabase
flutter test --update-goldens         # re-baseline goldens (review the diff!)
dart run build_runner build --delete-conflicting-outputs   # drift + riverpod codegen

# Run the app (config/local.json is gitignored; see Secrets hygiene)
flutter run -d macos --dart-define-from-file=config/local.json
flutter run -d ios   --dart-define-from-file=config/local.json

# Supabase — local stack runs on Colima, not Docker Desktop
colima start                          # start the container runtime first
supabase start                        # local Postgres + Auth + Storage
supabase db reset                     # re-apply all migrations from scratch
supabase db diff -f <name>            # capture schema changes as a migration
supabase migration list               # local vs hosted — they must agree
supabase db push                      # apply migrations to the hosted project

# Schema/RLS guards — run after any migration change
docker exec -i supabase_db_hearth psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < supabase/tests/schema_guards.sql
supabase functions serve              # Edge Functions locally (Phase 3+)
```

**Stack:** Flutter 3.47 / Dart 3.13 · Riverpod (state) · Drift (local SQLite) ·
go_router (navigation) · supabase_flutter · flutter_secure_storage · mocktail (mocks).
Generated files (`*.g.dart`, `*.drift.dart`) are excluded from analysis — never hand-edit
them; change the source and re-run build_runner.

**Layering:** `lib/domain/` is pure Dart with **no Flutter imports** — models, unit
conversion, scaling, macro math, aggregation. It is the cheapest test surface (§9.1) and a
test enforces the boundary. Features talk to `lib/data/repositories/`, never to Supabase or
Drift directly. External integrations (nutrition, shopping) sit behind adapter interfaces.
