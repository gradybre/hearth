-- Structural guards for the schema and its policies.
--
-- Run against a freshly reset local database:
--   supabase db reset
--   docker exec -i supabase_db_hearth psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/schema_guards.sql
--
-- This is NOT the exhaustive cross-household negative suite, which spec §8.2
-- defers to a dedicated test-suite stage. It is the smaller thing that would
-- be reckless to skip: proof that RLS is on everywhere, that every table has
-- a policy, and that the household scoping mechanism actually works when
-- executed rather than merely being written down.

\set ON_ERROR_STOP on

-- ── 1. RLS is enabled on every table (spec §8.2, default-deny) ──────────────

do $$
declare
  offenders text;
begin
  select string_agg(c.relname, ', ')
  into offenders
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity;

  if offenders is not null then
    raise exception 'RLS is not enabled on: %', offenders;
  end if;
end;
$$;

-- ── 2. No table is left without a policy ────────────────────────────────────

do $$
declare
  offenders text;
begin
  select string_agg(c.relname, ', ')
  into offenders
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = c.relname
    );

  if offenders is not null then
    raise exception 'No RLS policy on: %', offenders;
  end if;
end;
$$;

-- ── 3. Signup gives every user a household of one (spec §5.1) ───────────────

do $$
declare
  v_alice uuid := gen_random_uuid();
  v_bob uuid := gen_random_uuid();
  v_alice_household uuid;
  v_bob_household uuid;
  v_recipe_id uuid;
  v_visible integer;
  v_code text;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values
    (v_alice, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'alice@example.test', 'x', now(), now(), now()),
    (v_bob, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'bob@example.test', 'x', now(), now(), now());

  select household_id into v_alice_household
    from public.profiles where id = v_alice;
  select household_id into v_bob_household
    from public.profiles where id = v_bob;

  if v_alice_household is null or v_bob_household is null then
    raise exception 'Signup did not create a household for each user';
  end if;
  if v_alice_household = v_bob_household then
    raise exception 'Two new users must start in separate households';
  end if;

  -- ── 4. Household scoping actually isolates ────────────────────────────────
  -- One assertion, not the deferred per-table sweep: it proves
  -- current_household_id() and the policies built on it work when executed.

  insert into public.recipes (household_id, title, servings, created_by)
  values (v_alice_household, 'Alice''s short ribs', 4, v_alice)
  returning id into v_recipe_id;

  -- Alice sees her own recipe.
  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_alice, 'role', 'authenticated')::text,
    true
  );
  select count(*) into v_visible from public.recipes where id = v_recipe_id;
  if v_visible <> 1 then
    raise exception 'Owner cannot see their own recipe (saw % rows)', v_visible;
  end if;

  -- Bob, in a different household, sees nothing.
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bob, 'role', 'authenticated')::text,
    true
  );
  select count(*) into v_visible from public.recipes where id = v_recipe_id;
  if v_visible <> 0 then
    raise exception
      'Cross-household leak: another household read % recipe rows', v_visible;
  end if;

  -- And cannot write into it either.
  begin
    insert into public.recipes (household_id, title, servings)
    values (v_alice_household, 'Bob''s intrusion', 2);
    raise exception 'Cross-household leak: a write into another household succeeded';
  exception
    when insufficient_privilege then null;
  end;

  reset role;

  -- ── 5. Joining by share code merges the libraries (spec §5.1) ─────────────

  select share_code into v_code
    from public.households where id = v_alice_household;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_bob, 'role', 'authenticated')::text,
    true
  );
  perform public.join_household(v_code);

  select count(*) into v_visible from public.recipes where id = v_recipe_id;
  if v_visible <> 1 then
    raise exception
      'After joining, the partner still cannot see the shared library';
  end if;
  reset role;

  raise notice 'schema guards passed';
end;
$$;

-- ── 6. A logged entry can never exist without its frozen snapshot ───────────
-- The §4 non-negotiable, enforced by the schema rather than trusted to the
-- client.

do $$
declare
  v_user uuid := gen_random_uuid();
  v_day uuid;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (v_user, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'carol@example.test', 'x', now(), now(), now());

  insert into public.meal_plan_days (user_id, day)
  values (v_user, current_date)
  returning id into v_day;

  begin
    insert into public.meal_plan_entries (
      meal_plan_day_id, meal_slot, ref_type, ref_id, servings,
      is_logged, logged_at, macro_snapshot
    )
    values (v_day, 'dinner', 'recipe', gen_random_uuid(), 1,
            true, now(), null);
    raise exception 'A logged entry was accepted with no macro_snapshot';
  exception
    when check_violation then null;
  end;

  raise notice 'frozen snapshot guard passed';
end;
$$;
