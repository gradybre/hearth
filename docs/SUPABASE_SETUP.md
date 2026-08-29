# Supabase setup

Everything in `supabase/migrations/` runs against a local Postgres with no
account at all, so the schema and its policies are developed and validated
before any hosted project exists. This checklist is what to do when you're
ready to put Hearth on a real project.

**You are not the blocker.** The local stack issues real `sb_publishable_…`
keys and runs full Auth, Storage, and a mail catcher, so accounts, household
linking, and RLS under real user sessions are all built and verified locally.
Creating the hosted projects is a deploy step at the end of Phase 1, not a
prerequisite for building. Only two things genuinely cannot be exercised
locally, and both are called out below: leaked-password protection, and real
email delivery.

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

`supabase start` prints a local URL and keys. Those are development values for
a stack listening on localhost, and are not production secrets — but generate
`config/local.json` from them rather than pasting them anywhere:

```bash
supabase status -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); \
  json.dump({"SUPABASE_URL": d["API_URL"], \
             "SUPABASE_PUBLISHABLE_KEY": d["PUBLISHABLE_KEY"]}, \
            open("config/local.json","w"), indent=2)'
```

Then run against it:

```bash
flutter run -d ios --dart-define-from-file=config/local.json
```

The integration suite runs against this stack:

```bash
HEARTH_LIVE=1 flutter test --tags live test/integration
```

It is gated on the environment variable as well as the tag so a plain
`flutter test` skips it — a suite that goes red because a container is down
teaches everyone to ignore red.

Confirmation emails do not leave the machine — the local stack catches them at
**http://127.0.0.1:54324** (Mailpit). That is where to click the link when
testing sign-up.

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

Under **Authentication → URL Configuration**:

- [ ] **Site URL** — this is where a confirmation email sends someone *after*
      verifying. It defaults to `http://localhost:3000`, which is nothing: the
      account is confirmed and the browser then shows a connection error, which
      reads exactly like a broken app to whoever just signed up.

      Interim: set it to any page that loads. The real answer is a deep link
      back into Hearth, recorded in the gaps below.

Under **Authentication → Attack Protection**:

- [ ] **Leaked password protection** — on. This is the HaveIBeenPwned check
      from §8.3, and it exists only in the hosted dashboard; there is no local
      equivalent, so it cannot be verified by `supabase db reset`.

### 3. A storage bucket for recipe photos

Recipe photos are on-device only until this exists (spec §5.2). Under
**Storage**, create a bucket named `recipe-photos`, **not public** — the photos
are household data and RLS is what guards them, exactly as for every table.

### 4. Get the client configuration

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

### 5. What must never leave the dashboard

The **secret** key (`sb_secret_…`) bypasses RLS entirely. It goes in Edge
Function secrets and nowhere else:

```bash
supabase secrets set SUPABASE_SECRET_KEY=...
supabase secrets set ANTHROPIC_API_KEY=...      # Phase 3
supabase secrets set USDA_FDC_API_KEY=...       # Phase 2
```

Never in `config/`, never in the repo, never pasted into a chat. If one ever
lands in a commit: say so immediately and rotate it.

### 6. Push the schema

The two projects, created 2026-08-29. These are identifiers, not secrets: the
ref is the project's hostname and is embedded in every client request. The keys
and the database password are not here and never will be.

| Project | Ref | Used for |
|---|---|---|
| `hearth` | `iizsdbvohyhwbukrwilf` | The real one |
| `hearth-test` | `rhyomdiihpiigynzeshu` | The live integration suite (§9.3) |

Switching between them — and between either and the local stack — is one
command:

```bash
supabase link --project-ref iizsdbvohyhwbukrwilf   # or the test ref
supabase db push
```

Both projects carry the full schema, and both have `usda-lookup` and
`recipe-ai` deployed.

### The live suite runs against `hearth-test`, not the real one

`test/support/live_config.dart` reads `config/hosted-test.json`, so
`HEARTH_LIVE=1 flutter test --tags live test/integration` never touches real
recipes or logs. Its publishable key is already in that file.

**One thing still outstanding, and it is yours** — the Edge Functions on
`hearth-test` have no secrets, so the two function suites will fail there with
"…is not set on this project" until you run:

```bash
supabase secrets set USDA_FDC_API_KEY=... --project-ref rhyomdiihpiigynzeshu
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref rhyomdiihpiigynzeshu
```

The sync suites (`round_trip_live_test`, `library_sync_live_test`) use the
local stack via `config/local.json` and need none of this.

---

## Known gaps, recorded rather than forgotten

- **The app does not connect to Supabase yet.** `supabase_flutter` is not
  initialised anywhere in `lib/`; `Env` reads the config and guards it, and
  that is all. Finishing this checklist today changes nothing visible in the
  app until accounts land.
- **The email confirmation link does not come back to the app.** Supabase
  verifies the address and then redirects to the Site URL, so the last thing a
  new user sees is a web page rather than Hearth. The fix is a deep link — a
  `hearth://` URL scheme registered in the iOS and macOS targets, added to
  **Authentication → URL Configuration → Redirect URLs**, and handled by
  `supabase_flutter`, which listens for auth callbacks already. Belongs with
  **§10 phase 5 (household sharing polish)**, and should land *before* a second
  person is invited: the first-run experience is the whole of what they see.

- **A share code cannot be rotated.** `households.share_code` is generated once
  and there is no way to issue a new one, so a code that leaks — read aloud,
  screenshotted, pasted into a chat — lets anyone with an account join that
  household and read and edit the shared library forever. §5.1 does not call
  for rotation, but it is the obvious companion to unlinking, which is also
  unbuilt. Phase 5, with unlink.

- **Data written before first sign-in is not adopted.** An unconfigured build
  writes under a fixed `local-household` id; signing in switches to a real one,
  and those rows stay behind on disk rather than moving across. Only affects a
  development build — a real user signs up before they have a library — but it
  is a re-stamp plus a sync backfill if it ever needs doing.
- **Recipe photos are not synced.** They are written to the device and
  recorded in a local-only table; the upload half needs the bucket above.

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
