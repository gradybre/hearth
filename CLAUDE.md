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

## Working style

- **Plan Mode first for anything non-trivial.** Read the relevant spec section, propose the
  plan, get agreement, then build.
- **Build order is §10.** Don't pull work forward from a later phase without asking.
- **Deferred is deferred.** §12 lists what is explicitly out of scope for v1 — don't
  helpfully add micronutrients, sub-recipes, voice control, weight tracking, etc.
- **Open decisions are Brendan's** (§12). Surface them, don't quietly decide them.
- Flag spec gaps and contradictions instead of inventing an answer.
- Prefer small, reviewable changes over large sweeping ones.

## Design language

Warm, rustic, cozy — a home, not a calorie cop. Paper-cream surfaces, cocoa/wood-brown text,
a single terracotta/amber accent (60/30/10, 2–4 colors total). Serif for recipe titles,
humanist sans for body and data. Theme tokens and dark mode from day one; ship light first.
Kitchen-first legibility in cook-along and logging. (§6.1)

## Secrets hygiene

- Real keys go in `.env.local` — **gitignored**. Keep `.env.example` committed with key names
  and empty values only.
- Never paste a real key into a commit, a test fixture, a log line, or a chat message.
- If a secret ever lands in a commit or a bundle: say so immediately and rotate it. Do not
  quietly amend the history and move on.

## Commands

*(Conventional Flutter defaults — starting point only. Update this list once the project is
actually scaffolded so it matches reality.)*

```bash
flutter pub get            # install dependencies
flutter analyze            # static analysis / lints
dart format .              # format
flutter test               # unit + widget tests
flutter test integration_test   # integration tests (needs a test Supabase project)
flutter run -d macos       # run on macOS
flutter run -d windows     # run on Windows
flutter run -d ios         # run on iOS simulator
```
