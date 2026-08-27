# Supabase setup

Everything in `supabase/migrations/` runs against a local Postgres with no
account at all, so the schema and its policies are developed and validated
before any hosted project exists. This checklist is what to do when you're
ready to put Hearth on a real project.

**I never handle keys.** Every step below that involves a credential is yours;
the repo only ever contains `config/example.json`, which has key names and
empty values.

---

## Local development (no account needed)

```bash
colima start          # container runtime — not Docker Desktop
supabase start        # local Postgres + Auth + Storage
supabase db reset     # re-apply every migration from scratch
supabase stop         # when you're done
```

`supabase start` prints a local URL and keys. Those are well-known development
defaults, identical on every machine, and are not secrets.

---

## When you create the hosted projects

### 1. Two projects, not one

Create **hearth** and **hearth-test**. The test project is what the
integration suite runs against (spec §9.3) — pointing those tests at the real
project would let a failing test wipe your actual recipes.

### 2. Settings to change in the dashboard

Under **Authentication → Sign In / Providers → Email**:

- [ ] **Confirm email** — on. (Spec §8.3 requires email verification.)
- [ ] **Minimum password length** — 12, matching `supabase/config.toml`.
- [ ] **Password requirements** — lowercase, uppercase, and digits.

Under **Authentication → Attack Protection**:

- [ ] **Leaked password protection** — on. This is the HaveIBeenPwned check
      from §8.3, and it exists only in the hosted dashboard; there is no local
      equivalent, so it cannot be verified by `supabase db reset`.

### 3. Get the client configuration

From **Project Settings → API Keys**, copy:

- the **Project URL**
- the **publishable** key (`sb_publishable_…`)

Create `config/local.json` (gitignored) from the committed template:

```bash
cp config/example.json config/local.json
```

Fill in those two values. Both are public by design and safe in the app
bundle — RLS is what protects the data behind them (§8.1). A test asserts the
compiled-in key is not a secret one and fails the build if it ever is.

### 4. What must never leave the dashboard

The **secret** key (`sb_secret_…`) bypasses RLS entirely. It goes in Edge
Function secrets and nowhere else:

```bash
supabase secrets set SUPABASE_SECRET_KEY=...
supabase secrets set ANTHROPIC_API_KEY=...      # Phase 3
supabase secrets set USDA_FDC_API_KEY=...       # Phase 2
```

Never in `config/`, never in the repo, never pasted into a chat. If one ever
lands in a commit: say so immediately and rotate it.

### 5. Push the schema

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

---

## Known gaps, recorded rather than forgotten

- **Cross-household RLS negative tests are deferred** (§8.2, §12) — the
  accepted risk being that only two people have data. The trigger to pull them
  forward is a third person joining a household, which is exactly when the
  blast radius stops being small.
- **Unlinking a household is not implemented.** §5.1 says the shared library
  should be duplicated into each person's new solo household; that is a deep
  copy with full id remapping and needs its own change.
- **Joining carries the joiner's library with them.** §5.1 covers the reverse
  direction only, so this was a judgement call — flagged for confirmation in
  `20260827190500_household_join.sql`.
