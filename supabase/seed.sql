-- The account the live integration tests sign in as.
--
-- `HEARTH_LIVE=1 flutter test --tags live test/integration` is the only place
-- Hearth's sync is exercised against a real Postgres, a real PostgREST and a
-- real GoTrue rather than against fakes. Every one of those tests signs in as
-- this user — and it existed nowhere: not in this repository, not in the
-- local database, not in any setup step. So the suite failed at the first
-- line with "Invalid login credentials", and had, as far as the repository
-- can tell, never run at all.
--
-- **Local only.** Seeds run on `supabase db reset`, which targets the local
-- stack; `supabase db push` applies migrations and never this file. The
-- password below is a fixture for a database that lives in a container on
-- this machine and is thrown away on every reset. It is not a credential for
-- anything, and nothing outside this file may reuse it (CLAUDE.md's secrets
-- rule is about keys that reach a real service; this reaches a disposable
-- container).

do $$
declare
  v_user uuid := '9e5c1f10-0000-4000-8000-00000000ac01';
  v_house uuid;
begin
  -- Fixed id rather than random: a test that wants to write a row owned by
  -- this user can name the owner without first asking who it is. Not
  -- 1111…1111, which is the recipe the library-sync test looks for — two
  -- fixtures sharing an id is a confusion waiting to be debugged.
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    -- Empty strings, not nulls. GoTrue scans these into Go strings, and a
    -- null comes back as "Database error querying schema" — a 500 that says
    -- nothing about which column it could not read.
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    phone_change_token,
    reauthentication_token
  )
  values (
    v_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'pull@hearth.test',
    extensions.crypt('HearthPull2026a', extensions.gen_salt('bf')),
    -- Confirmed, or GoTrue refuses the sign-in and the suite fails the same
    -- way it did before, one step further along.
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '',
    '',
    '',
    '',
    '',
    '',
    ''
  )
  on conflict (id) do nothing;

  -- The identity row is what makes email sign-in work; a user without one
  -- authenticates against nothing.
  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    v_user,
    v_user::text,
    jsonb_build_object('sub', v_user::text, 'email', 'pull@hearth.test'),
    'email',
    now(),
    now(),
    now()
  )
  on conflict do nothing;

  -- The library that account is expected to already have.
  --
  -- `library_sync_live_test` signs in and asserts that a pull brings
  -- something down — "the seeded recipe should have arrived" — naming this
  -- id. Without it the suite gets past authentication and fails one line
  -- later, which is not an improvement worth having.
  --
  -- In the same block as the account on purpose: two blocks each declaring
  -- the id is two things to keep in step.

  -- Whatever household the new account was given. A trigger makes one; this
  -- does not assume its id, only that the account owns it.
  select id into v_house
  from public.households
  where owner_id = v_user
  -- Oldest first, so this cannot depend on the order rows happen to come
  -- back in if the account ever owns more than one.
  order by created_at, id
  limit 1;
  if v_house is null then
    raise exception 'the fixture account has no household to put a recipe in';
  end if;

  insert into public.recipes (id, household_id, title, servings, created_by)
  values (
    '11111111-1111-4111-8111-111111111111',
    v_house,
    -- The title the test names. A recipe the *other* person in the household
    -- wrote is the case this suite exists to prove: a pull that brings down
    -- what your partner added is the whole of what a household means.
    'Partner''s paella',
    4,
    v_user
  )
  on conflict (id) do nothing;

  -- Two ingredients and a step with a timer, because that is what the test
  -- reads back: a recipe row on its own would prove the row arrived and
  -- nothing about whether its children came with it.
  insert into public.recipe_sections (id, recipe_id, name, sort_order)
  values (
    '11111111-1111-4111-8111-111111111112',
    '11111111-1111-4111-8111-111111111111',
    -- The unnamed single section every plain recipe has.
    '',
    0
  )
  on conflict (id) do nothing;

  insert into public.recipe_ingredients (
    id, recipe_id, section_id, name, sort_order
  )
  values
    (
      '11111111-1111-4111-8111-111111111113',
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111112',
      'bomba rice',
      0
    ),
    (
      '11111111-1111-4111-8111-111111111114',
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111112',
      'saffron',
      1
    )
  on conflict (id) do nothing;

  insert into public.recipe_steps (
    id, recipe_id, section_id, step_number, body, timer_seconds
  )
  values (
    '11111111-1111-4111-8111-111111111115',
    '11111111-1111-4111-8111-111111111111',
    '11111111-1111-4111-8111-111111111112',
    1,
    'Toast the rice, then leave it alone.',
    120
  )
  on conflict (id) do nothing;
end;
$$;
