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

-- ── 7. Recipe photo storage (spec §5.2, §8.2) ───────────────────────────────
-- Sections 1 and 2 scan `nspname = 'public'`, so nothing in `storage` is
-- visible to them. Photo objects are a household's private pictures behind a
-- publishable key, which makes these the guards worth having explicitly.
do $$
declare
  v_public boolean;
  v_limit bigint;
  v_policies int;
begin
  select public, file_size_limit into v_public, v_limit
    from storage.buckets where id = 'recipe-photos';

  if v_public is null then
    raise exception 'The recipe-photos bucket does not exist';
  end if;
  if v_public then
    raise exception 'The recipe-photos bucket is public; it holds private photos';
  end if;
  -- Must match RecipePhotoStore.maxBytes, or a photo can save locally and
  -- never upload, which looks like nothing at all to the user.
  if v_limit is distinct from 4194304 then
    raise exception 'recipe-photos size limit is %, expected 4194304', v_limit;
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage' and c.relname = 'objects' and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on storage.objects';
  end if;

  select count(*) into v_policies from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname like 'recipe_photos%';
  if v_policies <> 2 then
    raise exception
      'Expected exactly 2 recipe_photos policies (select, insert), found %',
      v_policies;
  end if;

  -- A client chooses the object path, so the recipe id is a string it made
  -- up. This cast must deny rather than raise: a raise inside a policy is a
  -- 500 where a denial was meant.
  if public.uuid_or_null('nonsense') is not null
     or public.uuid_or_null('') is not null then
    raise exception 'uuid_or_null accepted a value that is not a uuid';
  end if;

  raise notice 'recipe photo storage guards passed';
end;
$$;

-- ── 8. The storage policies, executed rather than merely written ────────────
-- Guard 7 proves the policies exist. This proves they do the right thing,
-- which is the part that is easy to get subtly wrong and impossible to see
-- from Dart: photo objects are a household's private pictures sitting behind
-- a publishable key.
do $$
declare
  v_alice uuid;
  v_bob uuid;
  v_carol uuid;
  v_household uuid;
  v_recipe uuid;
  v_seen int;
begin
  select id into v_alice from auth.users where email = 'alice@example.test';
  select id into v_carol from auth.users where email = 'carol@example.test';
  select id into v_bob   from auth.users where email = 'bob@example.test';
  if v_alice is null or v_carol is null then
    raise exception 'Guard 8 needs the users guard 3 creates';
  end if;

  select household_id into v_household from public.profiles where id = v_alice;

  insert into public.recipes (household_id, title, servings, created_by)
  values (v_household, 'Alice''s photographed pie', 4, v_alice)
  returning id into v_recipe;

  -- Alice can put a photo under her own recipe.
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_alice, 'role', 'authenticated')::text, true);

  insert into storage.objects (bucket_id, name, owner_id)
  values ('recipe-photos', v_recipe || '/first.jpg', v_alice::text);

  select count(*) into v_seen from storage.objects
   where bucket_id = 'recipe-photos' and name = v_recipe || '/first.jpg';
  if v_seen <> 1 then
    raise exception 'Owner cannot read back their own photo (saw % rows)', v_seen;
  end if;

  -- Bob, in the same household, can read it. This is the whole point of the
  -- feature: a partner's copy of the recipe should have the picture.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_bob, 'role', 'authenticated')::text, true);
  select count(*) into v_seen from storage.objects
   where bucket_id = 'recipe-photos' and name = v_recipe || '/first.jpg';
  if v_seen <> 1 then
    raise exception 'A household member cannot see the shared photo';
  end if;

  -- Carol, in another household, sees nothing and can write nothing.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_carol, 'role', 'authenticated')::text, true);

  select count(*) into v_seen from storage.objects
   where bucket_id = 'recipe-photos' and name = v_recipe || '/first.jpg';
  if v_seen <> 0 then
    raise exception
      'Cross-household leak: another household read % photo rows', v_seen;
  end if;

  begin
    insert into storage.objects (bucket_id, name, owner_id)
    values ('recipe-photos', v_recipe || '/intrusion.jpg', v_carol::text);
    raise exception
      'Cross-household leak: a photo was written under another household''s recipe';
  exception
    when insufficient_privilege then null;
  end;

  -- A path naming no recipe at all is refused, and refused *as a denial*
  -- rather than as an error: `'loose'::uuid` would raise, and a raise inside
  -- a policy is a 500 where a "no" was meant.
  begin
    insert into storage.objects (bucket_id, name, owner_id)
    values ('recipe-photos', 'loose-file.jpg', v_carol::text);
    raise exception 'A path with no recipe folder was accepted';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into storage.objects (bucket_id, name, owner_id)
    values ('recipe-photos', 'not-a-uuid/x.jpg', v_carol::text);
    raise exception 'A non-uuid recipe folder was accepted';
  exception
    when insufficient_privilege then null;
  end;

  -- And one under a recipe that does not exist.
  begin
    insert into storage.objects (bucket_id, name, owner_id)
    values ('recipe-photos', gen_random_uuid() || '/x.jpg', v_carol::text);
    raise exception 'A photo was accepted under a recipe that does not exist';
  exception
    when insufficient_privilege then null;
  end;

  reset role;
  raise notice 'storage policy isolation guards passed';
end;
$$;

-- ── Unknown is not zero (spec §5.6) ─────────────────────────────────────────
--
-- The whole of the minor-nutrient feature rests on one distinction, and there
-- are exactly two places in SQL where it could be lost: a `default 0` on the
-- column, and a `coalesce` in `upsert_food`. Both are checked here rather than
-- trusted, because neither would fail loudly — they would simply put a wrong
-- number on every food that has never been asked.
do $$
declare
  v_food_id uuid := gen_random_uuid();
  v_silent  uuid := gen_random_uuid();
  v_stated  uuid := gen_random_uuid();
  v_value   numeric;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'food_serving_options'
      and column_name in ('fiber_g', 'sodium_mg', 'cholesterol_mg')
      and (is_nullable = 'NO' or column_default is not null)
  ) then
    raise exception 'A minor nutrient column is not-null or defaulted';
  end if;

  perform public.upsert_food(jsonb_build_object(
    'id', v_food_id, 'name', 'Guard oats', 'source', 'manual',
    'serving_options', jsonb_build_array(
      jsonb_build_object('id', v_stated, 'label', '100 g',
        'amount_canonical', 100, 'amount_kind', 'mass', 'amount_unit', 'g',
        'kcal', 380, 'fiber_g', 10, 'cholesterol_mg', 0, 'sort_order', 0),
      jsonb_build_object('id', v_silent, 'label', '1 cup',
        'amount_canonical', 80, 'amount_kind', 'mass', 'amount_unit', 'g',
        'kcal', 300, 'sort_order', 1)
    )
  ));

  select fiber_g into v_value
  from public.food_serving_options where id = v_stated;
  if v_value is distinct from 10 then
    raise exception 'upsert_food lost a stated fibre: %', v_value;
  end if;

  -- A stated zero is a fact — water really has no sodium — and must survive.
  select cholesterol_mg into v_value
  from public.food_serving_options where id = v_stated;
  if v_value is distinct from 0 then
    raise exception 'upsert_food turned a stated zero into %', v_value;
  end if;

  select fiber_g into v_value
  from public.food_serving_options where id = v_silent;
  if v_value is not null then
    raise exception 'upsert_food invented a fibre of % for a silent serving',
      v_value;
  end if;

  -- And the pull half agrees with the push half.
  if not exists (
    select 1 from public.changed_foods(null) c
    where (c ->> 'id')::uuid = v_food_id
      and (c -> 'serving_options' -> 0 ->> 'fiber_g')::numeric = 10
      and (c -> 'serving_options' -> 1 -> 'fiber_g') = 'null'::jsonb
  ) then
    raise exception 'changed_foods did not carry the nutrients faithfully';
  end if;

  delete from public.foods where id = v_food_id;
  raise notice 'minor nutrient guards passed';
end;
$$;

-- ── A recipe you order rather than cook (spec §5.2) ─────────────────────────
--
-- `kind` is the one column a shopping list consults to decide whether you are
-- sent to the shop for a meal. Both halves of sync have to carry it, and a
-- recipe that says nothing has to arrive as one you cook.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_house uuid := gen_random_uuid();
  v_bowl  uuid := gen_random_uuid();
  v_pot   uuid := gen_random_uuid();
  v_kind  text;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'kind-guard@example.test', 'x', now(), now(), now()
  );
  insert into public.households (id, name, owner_id)
  values (v_house, 'Kind guard', v_owner);

  perform public.upsert_recipe(jsonb_build_object(
    'id', v_bowl, 'household_id', v_house, 'title', 'Burrito bowl',
    'servings', 1, 'kind', 'eaten_out', 'sections', '[]'::jsonb
  ));
  select kind into v_kind from public.recipes where id = v_bowl;
  if v_kind is distinct from 'eaten_out' then
    raise exception 'upsert_recipe lost the kind: %', v_kind;
  end if;

  if not exists (
    select 1 from public.changed_recipes(null) c
    where (c ->> 'id')::uuid = v_bowl and c ->> 'kind' = 'eaten_out'
  ) then
    raise exception 'changed_recipes did not carry the kind';
  end if;

  -- A payload from a client that has never heard of `kind` is a recipe you
  -- cook, which is what every recipe written before today is.
  perform public.upsert_recipe(jsonb_build_object(
    'id', v_pot, 'household_id', v_house, 'title', 'Chilli',
    'servings', 4, 'sections', '[]'::jsonb
  ));
  select kind into v_kind from public.recipes where id = v_pot;
  if v_kind is distinct from 'cooked' then
    raise exception 'a recipe with no kind did not default to cooked: %', v_kind;
  end if;

  -- Unwound in reference order. A new auth user gets a profile and a
  -- household of their own from a trigger, so tearing down only the rows this
  -- guard created leaves those behind and the delete fails on a foreign key.
  delete from public.recipes where household_id = v_house;
  delete from public.profiles where household_id in (
    select id from public.households where owner_id = v_owner
  );
  delete from public.profiles where id = v_owner;
  delete from public.households where owner_id = v_owner;
  delete from auth.users where id = v_owner;
  raise notice 'recipe kind guards passed';
end;
$$;

-- ── A chain's menu in the shared catalogue (spec §5.2, §8.2) ────────────────
--
-- The Chipotle seed writes global foods, and the claim that needed no new
-- policy is that the existing ones already do the right thing with them. That
-- claim is checked here rather than trusted: readable by a signed-in member,
-- unwritable from the client, and carried by the ordinary pull.
do $$
declare
  v_user  uuid := gen_random_uuid();
  v_seen  int;
  v_chicken uuid;
begin
  select id into v_chicken
  from public.foods where brand = 'Chipotle' and name = 'Chicken';
  if v_chicken is null then
    raise exception 'the Chipotle seed did not land';
  end if;

  if exists (select 1 from public.foods where brand = 'Chipotle'
             and (household_id is not null or source <> 'restaurant')) then
    raise exception 'a seeded component is not a global restaurant food';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_user, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'menu-guard@example.test', 'x', now(), now(), now()
  );

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  select count(*) into v_seen from public.foods where brand = 'Chipotle';
  if v_seen <> 29 then
    raise exception 'a member could see % of the 29 components', v_seen;
  end if;

  -- And the pull carries them, which is what puts them on a phone.
  if not exists (
    select 1 from public.changed_foods(null) c
    where (c ->> 'id')::uuid = v_chicken
      and (c -> 'serving_options' -> 0 ->> 'protein_g')::numeric = 32
  ) then
    raise exception 'changed_foods did not carry a global food';
  end if;

  -- Unwritable from the client: the write policies are keyed on the caller's
  -- own household, and a global row belongs to nobody's.
  begin
    update public.foods set name = 'Tampered' where id = v_chicken;
    if found then
      raise exception 'a client was able to rewrite a global food';
    end if;
  exception
    when insufficient_privilege then null;
  end;

  reset role;
  delete from public.profiles where id = v_user;
  delete from public.households where owner_id = v_user;
  delete from auth.users where id = v_user;
  raise notice 'restaurant catalogue guards passed';
end;
$$;

-- ── A seeded food is never "needs attention" (spec §5.5) ───────────────────
--
-- `needsAttention` means a food cannot actually be logged as it stands, and
-- the library offers a filter for exactly that. A restaurant's own condiments
-- break it: Freddy's mustard and steakburger seasoning are published as zero
-- across all four macros with only sodium, which is the shape of a half-filled
-- import and is here the restaurant's real answer.
--
-- `is_zero_calorie` is the column that tells those apart, and a seed is the
-- only place it can be set for a global food — `foods_update_household`
-- requires a household, so a client can never clear the flag from the app. Get
-- it wrong in a migration and five condiments sit in "needs attention"
-- forever with no way out.
do $$
begin
  if exists (
    select 1
    from public.foods f
    where f.source = 'restaurant'
      and f.household_id is null
      and not f.is_zero_calorie
      -- A modifier's servings are negative rather than positive, so this
      -- would trip on every one of them — and a global food's flag cannot be
      -- cleared from the app, which is the whole reason this guard exists.
      and not f.is_modifier
      and exists (select 1 from public.food_serving_options o
                  where o.food_id = f.id)
      and not exists (
        select 1 from public.food_serving_options o
        where o.food_id = f.id
          and (coalesce(o.kcal, 0) > 0 or coalesce(o.protein_g, 0) > 0
               or coalesce(o.carb_g, 0) > 0 or coalesce(o.fat_g, 0) > 0)
      )
  ) then
    raise exception 'a seeded food is stuck needing attention';
  end if;

  raise notice 'seeded zero-calorie guards passed';
end;
$$;

-- ── A deduction is signed, and only a modifier may be (spec §5.2) ───────────
--
-- Freddy's publishes "Make any Sandwich a Lettuce Wrap" as -180 kcal with
-- +1 g of fibre. The mixed signs are the point: a "negate everything"
-- implementation would store the fibre as -1 and nothing but a test that
-- looks at the fibre specifically would notice.
--
-- The flag is denormalised onto `food_serving_options` so the checks can see
-- it, and a composite foreign key keeps the copy honest. What is asserted
-- here is that neither half can be loosened without something failing loudly.
do $$
declare
  v_plain    uuid := gen_random_uuid();
  v_modifier uuid := gen_random_uuid();
  v_serving  uuid := gen_random_uuid();
  v_value    numeric;
  v_names    text[] := array['kcal', 'protein_g', 'carb_g', 'fat_g',
                             'fiber_g', 'sodium_mg', 'cholesterol_mg'];
  v_name     text;
begin
  -- 7. Structural, and first: everything below tests behaviour, and a
  -- behaviour test passes for the wrong reason if a constraint quietly went
  -- missing in a `db diff`.
  foreach v_name in array v_names loop
    if not exists (
      select 1 from pg_constraint
      where conrelid = 'public.food_serving_options'::regclass
        and conname = 'food_serving_options_' || v_name || '_signed'
    ) then
      raise exception 'the signed check for % is missing', v_name;
    end if;
  end loop;

  if not exists (
    select 1 from pg_class where relname = 'foods_id_is_modifier_key'
  ) then
    raise exception 'the index the modifier foreign key rests on is missing';
  end if;

  -- 1. An ordinary food still cannot go negative. This is the constraint that
  -- was there before, and the one this change could most easily have
  -- loosened for everybody.
  perform public.upsert_food(jsonb_build_object(
    'id', v_plain, 'name', 'Guard burger', 'source', 'manual',
    'serving_options', jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid(), 'label', '1 serving',
      'amount_canonical', 1, 'amount_kind', 'count', 'amount_unit', 'item',
      'kcal', 380, 'protein_g', 24, 'sort_order', 0))
  ));

  foreach v_name in array v_names loop
    begin
      execute format(
        'update public.food_serving_options set %I = -1 where food_id = $1',
        v_name) using v_plain;
      raise exception 'a plain food accepted a negative %', v_name;
    exception
      when check_violation then null;
    end;
  end loop;

  -- 2. A modifier may, and the fibre keeps its own sign.
  perform public.upsert_food(jsonb_build_object(
    'id', v_modifier, 'name', 'Guard lettuce wrap', 'source', 'restaurant',
    'brand', 'Guard Diner', 'menu_group', 'Modifications', 'menu_order', 0,
    'is_modifier', true,
    'serving_options', jsonb_build_array(jsonb_build_object(
      'id', v_serving, 'label', '1 serving',
      'amount_canonical', 1, 'amount_kind', 'count', 'amount_unit', 'item',
      'kcal', -180, 'protein_g', -3, 'carb_g', -25, 'fat_g', -6,
      'fiber_g', 1, 'sodium_mg', -270, 'cholesterol_mg', 0, 'sort_order', 0))
  ));

  select kcal into v_value from public.food_serving_options where id = v_serving;
  if v_value is distinct from -180 then
    raise exception 'a modifier lost its deduction: %', v_value;
  end if;

  select fiber_g into v_value from public.food_serving_options where id = v_serving;
  if v_value is distinct from 1 then
    raise exception 'a modifier had its fibre flipped to %', v_value;
  end if;

  -- 3. A serving cannot claim a flag its food does not have, either way.
  begin
    update public.food_serving_options set is_modifier = false
    where id = v_serving;
    raise exception 'a serving disowned its food''s flag';
  exception
    when foreign_key_violation then null;
    when check_violation then null;
  end;

  begin
    insert into public.food_serving_options (
      id, food_id, label, amount_canonical, amount_kind, amount_unit,
      kcal, is_modifier, sort_order
    ) values (
      gen_random_uuid(), v_plain, '1 serving', 1, 'count', 'item',
      -5, true, 1
    );
    raise exception 'a plain food grew a modifier serving';
  exception
    when foreign_key_violation then null;
  end;

  -- 4. And a flagged food cannot be un-flagged while a negative remains. This
  -- is the one that makes "the flag and its servings agree" unrepresentable
  -- rather than merely tested.
  begin
    update public.foods set is_modifier = false where id = v_modifier;
    raise exception 'a modifier was un-flagged with its deduction intact';
  exception
    when check_violation then null;
  end;

  -- 5. But `upsert_food` can turn one back into an ordinary food, because it
  -- clears the servings before it touches the flag. Get the order wrong and
  -- the cascade above fires on rows that are about to be deleted anyway, and
  -- a user who un-ticked the switch could never save that food again.
  perform public.upsert_food(jsonb_build_object(
    'id', v_modifier, 'name', 'Guard lettuce wrap', 'source', 'restaurant',
    'brand', 'Guard Diner', 'menu_group', 'Modifications', 'menu_order', 0,
    'is_modifier', false,
    'serving_options', jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid(), 'label', '1 serving',
      'amount_canonical', 1, 'amount_kind', 'count', 'amount_unit', 'item',
      'kcal', 20, 'sort_order', 0))
  ));

  if exists (select 1 from public.foods
             where id = v_modifier and is_modifier) then
    raise exception 'upsert_food would not let a modifier become a food';
  end if;

  -- 6. The pull half carries the flag and the signs.
  perform public.upsert_food(jsonb_build_object(
    'id', v_modifier, 'name', 'Guard lettuce wrap', 'source', 'restaurant',
    'brand', 'Guard Diner', 'menu_group', 'Modifications', 'menu_order', 0,
    'is_modifier', true,
    'serving_options', jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid(), 'label', '1 serving',
      'amount_canonical', 1, 'amount_kind', 'count', 'amount_unit', 'item',
      'kcal', -180, 'fiber_g', 1, 'sort_order', 0))
  ));

  if not exists (
    select 1 from public.changed_foods(null) c
    where (c ->> 'id')::uuid = v_modifier
      and (c ->> 'is_modifier')::boolean
      and (c -> 'serving_options' -> 0 ->> 'kcal')::numeric = -180
      and (c -> 'serving_options' -> 0 ->> 'fiber_g')::numeric = 1
  ) then
    raise exception 'changed_foods did not carry the modifier faithfully';
  end if;

  -- A modifier and a default are contradictory: a default is matched into
  -- cooked recipes by name, which is the one place a deduction must not go.
  begin
    update public.foods set is_default = true where id = v_modifier;
    raise exception 'a modifier was also made a default';
  exception
    when check_violation then null;
  end;

  delete from public.foods where id in (v_plain, v_modifier);

  -- 8. And every seeded modifier is a real one: a flag with nothing negative
  -- under it is a switch somebody set by mistake.
  if exists (
    select 1 from public.foods f
    where f.is_modifier
      and not exists (
        select 1 from public.food_serving_options o
        where o.food_id = f.id
          and (o.kcal < 0 or o.protein_g < 0 or o.carb_g < 0 or o.fat_g < 0
               or o.fiber_g < 0 or o.sodium_mg < 0 or o.cholesterol_mg < 0)
      )
  ) then
    raise exception 'a modifier deducts nothing';
  end if;

  raise notice 'modifier guards passed';
end;
$$;

-- ── A library can be read past the row cap (spec §7.1) ─────────────────────
--
-- PostgREST truncates a response at `max_rows` and says nothing, so the pull
-- that asked for everything at once took the first thousand rows and moved
-- its watermark past the rest. The paged functions exist so a client can
-- cursor instead — and the properties that make that safe are worth pinning,
-- because all of them fail silently.
--
-- Both tables, driven by name rather than written out once: the two paged
-- functions are duplicates of each other, and a guard covering only one lets
-- the other's cursor rot. A wrong tiebreak in `changed_recipes_page` would
-- re-read a boundary row on every page, or stall the client's paging loop
-- outright — and neither shows up anywhere else.
do $$
declare
  v_table text;
  v_after_ts timestamptz;
  v_after_id uuid;
  v_rows integer;
  v_total integer;
  v_pages integer;
  v_last jsonb;
  v_actual integer;
  v_compared integer;
  v_mismatch integer;
  v_capped integer;
begin
  foreach v_table in array array['foods', 'recipes'] loop
    v_after_ts := null;
    v_after_id := null;
    v_total := 0;
    v_pages := 0;

    -- 1. Cursoring reads every row exactly once.
    loop
      execute format(
        'select count(*) from public.changed_%s_page(null, $1, $2, 100)',
        v_table
      ) into v_rows using v_after_ts, v_after_id;
      exit when v_rows = 0;

      v_pages := v_pages + 1;
      v_total := v_total + v_rows;
      if v_pages > 200 then
        raise exception 'paging % did not finish: the cursor is not advancing',
          v_table;
      end if;

      -- The page's *last* row in the page's own ordering. Getting this
      -- backwards overlaps the pages and counts rows twice — which is how
      -- this guard first failed, and is exactly the mistake a client could
      -- make.
      execute format(
        'select x from public.changed_%s_page(null, $1, $2, 100) x '
        'order by (x ->> ''updated_at'') desc, (x ->> ''id'') desc limit 1',
        v_table
      ) into v_last using v_after_ts, v_after_id;
      v_after_ts := (v_last ->> 'updated_at')::timestamptz;
      v_after_id := (v_last ->> 'id')::uuid;
    end loop;

    execute format('select count(*) from public.%I', v_table) into v_actual;
    if v_total <> v_actual then
      raise exception 'paging read % of %, the table holds %',
        v_total, v_table, v_actual;
    end if;

    -- 2. A page says exactly what the unpaged function says.
    --
    -- Six guards in this file assert that `changed_foods` / `changed_recipes`
    -- carry a column the client needs — nutrients, kind, global foods,
    -- `is_modifier`, the menu columns, the icon. The client now reads only
    -- the paged twins, so every one of those guards is aimed at a function
    -- the app no longer calls. Comparing whole rows points them all back at
    -- the real path for free, and catches the next column added to one
    -- definition and forgotten in the other.
    execute format(
      'select count(*), count(*) filter (where p is distinct from u) '
      'from public.changed_%s_page(null, null, null, 1000) p '
      'join public.changed_%s(null) u on (u ->> ''id'') = (p ->> ''id'')',
      v_table, v_table
    ) into v_compared, v_mismatch;

    if v_compared = 0 then
      raise exception 'nothing compared: % returned no rows either way',
        v_table;
    end if;
    if v_mismatch > 0 then
      raise exception '% of % rows differ between the paged and unpaged %',
        v_mismatch, v_compared, v_table;
    end if;
  end loop;

  -- 3. The limit is clamped rather than trusted. A caller asking for a
  -- million rows is asking PostgREST to truncate again, silently — the very
  -- defect these functions exist to remove.
  --
  -- Asserting that against the seeded catalogue proves nothing: it holds a
  -- few hundred foods, so an unclamped call returns a few hundred and the
  -- check passes whether the clamp is there or not. Grow the table past the
  -- cap first, so the clamp is the only thing that can hold the count down.
  insert into public.foods (name)
  select 'guard page filler ' || g from generate_series(1, 1001) g;

  -- Counted before the cleanup and judged after it: raising in between would
  -- leave a thousand fillers sitting in the library.
  select count(*) into v_capped
  from public.changed_foods_page(null, null, null, 999999);
  select count(*) into v_rows
  from public.changed_foods_page(null, null, null, 0);

  delete from public.foods where name like 'guard page filler %';

  if v_capped > 1000 then
    raise exception 'the page limit is not clamped: % rows came back', v_capped;
  end if;
  -- And the floor, so a client asking for nothing still makes progress
  -- rather than looping on an empty page for ever.
  if v_rows <> 1 then
    raise exception 'a page of zero returned % rows, not one', v_rows;
  end if;

  -- 4. The unpaged functions are still there. They are what a phone running
  -- an older build calls, and nothing here may take them away mid-rollout.
  perform 1 from public.changed_foods(null) limit 1;
  perform 1 from public.changed_recipes(null) limit 1;

  raise notice 'paged library guards passed';
end;
$$;

-- ── A menu keeps its own shape (spec §5.2) ──────────────────────────────────
--
-- The builder lays a menu out by `menu_group` and `menu_order`, and both have
-- to survive the sync round trip or the list falls back to alphabetical with
-- the barbacoa between the beans and the cheese.
do $$
declare
  v_food uuid;
  v_group text;
  v_order integer;
begin
  -- Every seeded menu, not just Chipotle: each restaurant added since is one
  -- more chance to paste a sheet in the wrong order.
  if exists (
    select 1 from public.foods
    where source = 'restaurant' and household_id is null
      and (menu_group is null or menu_order is null)
  ) then
    raise exception 'a seeded menu item has no place on its menu';
  end if;

  -- Sections are ordered by where each first appears, so the positions have
  -- to be contiguous and grouped — an interleaved menu_order would scatter
  -- the sections however well each one is named.
  if exists (
    select 1
    from (
      select brand,
             menu_group,
             min(menu_order) as first,
             max(menu_order) as last,
             count(*) as items
      from public.foods
      where source = 'restaurant' and household_id is null
      group by brand, menu_group
    ) as s
    where s.last - s.first + 1 <> s.items
  ) then
    raise exception 'a seeded section is interleaved with another';
  end if;

  -- And no two items on one menu share a position, which would make the
  -- order of those two arbitrary.
  if exists (
    select 1 from public.foods
    where source = 'restaurant' and household_id is null
    group by brand, menu_order having count(*) > 1
  ) then
    raise exception 'two items on one menu claim the same position';
  end if;

  select id into v_food from public.foods
  where brand = 'Chipotle' and name = 'Chicken';

  perform public.upsert_food(jsonb_build_object(
    'id', v_food, 'name', 'Chicken', 'brand', 'Chipotle',
    'source', 'restaurant', 'menu_group', 'Proteins', 'menu_order', 9,
    'serving_options', '[]'::jsonb
  ));

  select menu_group, menu_order into v_group, v_order
  from public.foods where id = v_food;
  if v_group is distinct from 'Proteins' or v_order is distinct from 9 then
    raise exception 'upsert_food lost the menu place: % %', v_group, v_order;
  end if;

  if not exists (
    select 1 from public.changed_foods(null) c
    where (c ->> 'id')::uuid = v_food
      and c ->> 'menu_group' = 'Proteins'
      and (c ->> 'menu_order')::integer = 9
  ) then
    raise exception 'changed_foods did not carry the menu place';
  end if;

  raise notice 'menu section guards passed';
end;
$$;

-- ── A recipe's sketch icon survives the round trip (spec §5.2) ──────────────
--
-- `upsert_recipe` and `changed_recipes` are restated in full every time a
-- column is added to `recipes`, and `create or replace` deletes whatever is
-- not repeated. Three migrations once sat local-only for want of this check
-- and three features were silently broken (CLAUDE.md rule 8) — so the column
-- is proved to make it out and back, not merely to exist.

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_house uuid := gen_random_uuid();
  v_soup  uuid := gen_random_uuid();
  v_plain uuid := gen_random_uuid();
  v_icon  text :=
    '<svg viewBox="0 0 24 24"><path d="M3 11h18c0 5-4 9-9 9s-9-4-9-9z"/></svg>';
  v_stored text;
begin
  -- Structural, and first. `add column if not exists … check (…)` skips the
  -- whole clause when the column is already there — the check with it — and
  -- reports success, so the cap can be absent while everything below still
  -- passes. Asserted by name, because the behavioural test at the end of this
  -- block passes for the wrong reason the moment the constraint goes missing
  -- for any other reason too.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.recipes'::regclass
      and conname = 'recipes_icon_svg_length'
  ) then
    raise exception 'the icon length constraint is missing';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'icon-guard@example.test', 'x', now(), now(), now()
  );
  insert into public.households (id, name, owner_id)
  values (v_house, 'Icon guard', v_owner);

  perform public.upsert_recipe(jsonb_build_object(
    'id', v_soup, 'household_id', v_house, 'title', 'Chicken noodle soup',
    'servings', 4, 'icon_svg', v_icon, 'sections', '[]'::jsonb
  ));

  select icon_svg into v_stored from public.recipes where id = v_soup;
  if v_stored is distinct from v_icon then
    raise exception 'upsert_recipe lost the icon: %', v_stored;
  end if;

  if not exists (
    select 1 from public.changed_recipes(null) c
    where (c ->> 'id')::uuid = v_soup and c ->> 'icon_svg' = v_icon
  ) then
    raise exception 'changed_recipes did not carry the icon';
  end if;

  -- No icon is the ordinary state, not a failure. A client that has never
  -- heard of the column must still be able to save a recipe.
  perform public.upsert_recipe(jsonb_build_object(
    'id', v_plain, 'household_id', v_house, 'title', 'Chilli',
    'servings', 4, 'sections', '[]'::jsonb
  ));
  select icon_svg into v_stored from public.recipes where id = v_plain;
  if v_stored is not null then
    raise exception 'a recipe with no icon did not stay without one: %', v_stored;
  end if;

  -- Clearing one is a real value, not an absence: a user who dislikes a
  -- drawing must be able to be rid of it, and the next pull must agree.
  perform public.upsert_recipe(jsonb_build_object(
    'id', v_soup, 'household_id', v_house, 'title', 'Chicken noodle soup',
    'servings', 4, 'icon_svg', null, 'sections', '[]'::jsonb
  ));
  select icon_svg into v_stored from public.recipes where id = v_soup;
  if v_stored is not null then
    raise exception 'clearing the icon did not take: %', v_stored;
  end if;

  -- A sketch is a few hundred bytes. Forty kilobytes of it is a traced
  -- photograph, and this column is read on every row of the library.
  begin
    update public.recipes
    set icon_svg = repeat('x', 4097) where id = v_soup;
    raise exception 'an oversized icon was accepted';
  exception
    when check_violation then null;
  end;

  delete from public.recipes where household_id = v_house;
  delete from public.profiles where household_id in (
    select id from public.households where owner_id = v_owner
  );
  delete from public.profiles where id = v_owner;
  delete from public.households where owner_id = v_owner;
  delete from auth.users where id = v_owner;
  raise notice 'recipe icon guards passed';
end;
$$;

-- ── A deletion reaches the other phone (spec §7.1) ─────────────────────────
--
-- Five tables used to remove rows outright, and a pull only ever sees rows
-- that exist — so a meal your partner deleted stayed on your phone for ever.
-- They soft-delete now, the way recipes and foods always have.
--
-- Guarded per table by name rather than written out five times: they were
-- given this treatment together and the next one added to the list should
-- fail here rather than quietly go without.
do $$
declare
  v_table text;
  v_owner uuid := gen_random_uuid();
  v_house uuid := gen_random_uuid();
  v_list uuid;
  v_item uuid;
  v_again uuid;
  v_deleted boolean;
begin
  foreach v_table in array array[
    'meal_plan_entries', 'shopping_list_items', 'collections',
    'plan_templates', 'ingredient_matches'
  ] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'is_deleted'
    ) then
      raise exception '% cannot record that a row was deleted', v_table;
    end if;

    -- Not nullable and not null-by-default: "unknown" is not one of the two
    -- states a deletion has, and a null here would read as neither.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'is_deleted'
        and (is_nullable = 'YES' or column_default is null)
    ) then
      raise exception '%.is_deleted is nullable or has no default', v_table;
    end if;
  end loop;

  -- A deleted line must not hold its name on the list for ever. Re-adding
  -- milk after deleting it writes a new row, and the old whole-table
  -- constraint would have refused it on behalf of a line nobody can see.
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated',
    -- Keyed off the fixture id rather than a fixed address, so this block
    -- can be re-run against a database that already has one.
    'authenticated', v_owner || '@delete-guard.test', 'x', now(), now(), now()
  );
  insert into public.households (id, name, owner_id)
  values (v_house, 'Delete guard', v_owner);
  insert into public.shopping_lists (household_id, from_date, to_date)
    values (v_house, current_date, current_date + 6)
    returning id into v_list;

  insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
    values (v_list, 'milk', 'Milk') returning id into v_item;
  update public.shopping_list_items set is_deleted = true where id = v_item;

  begin
    insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
      values (v_list, 'milk', 'Milk') returning id into v_again;
  exception when unique_violation then
    raise exception 'a deleted line still holds its name on the list';
  end;

  -- And two *live* lines of the same name are still refused, which is what
  -- the constraint was there for in the first place.
  begin
    insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
      values (v_list, 'milk', 'Milk');
    raise exception 'two live lines of the same name were allowed';
  exception when unique_violation then
    null;
  end;

  -- `ingredient_matches` keeps its whole-table constraint on purpose: it is
  -- the upsert's conflict target. Answering the same wording again must
  -- therefore revive the row rather than be refused.
  insert into public.ingredient_matches (household_id, ingredient_string)
    values (v_house, 'olive oil');
  -- Stating the time, as every real write does: the tombstone records the
  -- deleting writer's clock, and only a later write may clear it.
  update public.ingredient_matches
    set is_deleted = true, updated_at = timestamptz '2026-09-14 12:00:00Z'
    where household_id = v_house and ingredient_string = 'olive oil';

  insert into public.ingredient_matches (
    household_id, ingredient_string, is_deleted, updated_at
  )
    values (
      v_house, 'olive oil', false, timestamptz '2026-09-14 12:00:01Z'
    )
    on conflict (household_id, ingredient_string) do update
      set is_deleted = excluded.is_deleted,
          updated_at = excluded.updated_at;

  select is_deleted into v_deleted from public.ingredient_matches
    where household_id = v_house and ingredient_string = 'olive oil';
  if v_deleted then
    raise exception 'answering the same wording again did not revive the match';
  end if;

  -- The household and its rows go; the fixture user stays, as the other
  -- guards in this file leave theirs. This runs against a reset database.
  delete from public.households where id = v_house;
  raise notice 'soft delete guards passed';
end;
$$;

-- ── A deletion is not undone by a write that predates it (spec §7.1) ───────
--
-- Every soft-deleting table had the same hole, and recipes and foods have had
-- it since they were built: an edit sitting unsent in one phone's outbox
-- clears the flag on a row the other phone deleted. The rule is one trigger
-- across all seven, so it is checked across all seven here.
--
-- Both directions matter equally. A guard that only refused would be a guard
-- that broke Undo, and Undo is the commoner action by a wide margin.
do $$
declare
  v_table text;
  v_owner uuid := gen_random_uuid();
  v_house uuid := gen_random_uuid();
  v_list uuid;
  v_id uuid;
  v_deleted boolean;
  v_at timestamptz;
  v_count integer;
  v_missing text[] := '{}';
begin
  -- Every soft-deleting table carries the rule. A table that gained
  -- `is_deleted` without it would be the one that still resurrects.
  foreach v_table in array array[
    'recipes', 'foods', 'meal_plan_entries', 'shopping_list_items',
    'collections', 'plan_templates', 'ingredient_matches'
  ] loop
    if not exists (
      select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal
        and c.relname = v_table
        and t.tgname = v_table || '_refuse_resurrection'
    ) then
      v_missing := v_missing || v_table;
    end if;

    -- And somewhere to record whose clock said so.
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = v_table
        and column_name = 'deleted_at'
    ) then
      v_missing := v_missing || (v_table || '.deleted_at');
    end if;
  end loop;

  if array_length(v_missing, 1) is not null then
    raise exception 'these can still be resurrected: %',
      array_to_string(v_missing, ', ');
  end if;

  -- The rule itself, on one real table.
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', v_owner || '@resurrection-guard.test', 'x',
    now(), now(), now()
  );
  insert into public.households (id, name, owner_id)
  values (v_house, 'Resurrection guard', v_owner);
  insert into public.shopping_lists (household_id, from_date, to_date)
    values (v_house, current_date, current_date + 6) returning id into v_list;

  insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
    values (v_list, 'milk', 'Milk') returning id into v_id;

  -- One phone deletes it, stating its own clock.
  update public.shopping_list_items
    set is_deleted = true, updated_at = timestamptz '2026-09-14 12:00:00Z'
    where id = v_id;

  select deleted_at into v_at from public.shopping_list_items where id = v_id;
  if v_at is distinct from timestamptz '2026-09-14 12:00:00Z' then
    raise exception 'the tombstone did not record the writer''s time: %', v_at;
  end if;

  -- The other phone pushes an edit it made *before* that. It must not undo it.
  update public.shopping_list_items
    set is_deleted = false, raw_name = 'Whole milk',
        updated_at = timestamptz '2026-09-14 11:59:00Z'
    where id = v_id;

  select is_deleted into v_deleted
    from public.shopping_list_items where id = v_id;
  if not v_deleted then
    raise exception 'a write from before the deletion undid it';
  end if;

  -- Undo, made after the deletion, must still work — including from the very
  -- device that deleted it, one second later.
  update public.shopping_list_items
    set is_deleted = false, updated_at = timestamptz '2026-09-14 12:00:01Z'
    where id = v_id;

  select is_deleted, deleted_at into v_deleted, v_at
    from public.shopping_list_items where id = v_id;
  if v_deleted then
    raise exception 'Undo could not bring the line back';
  end if;
  if v_at is not null then
    raise exception 'a live row is still carrying a deletion time: %', v_at;
  end if;

  -- And it can be deleted again afterwards, rather than being stuck alive.
  update public.shopping_list_items
    set is_deleted = true, updated_at = timestamptz '2026-09-14 12:00:02Z'
    where id = v_id;
  select is_deleted into v_deleted
    from public.shopping_list_items where id = v_id;
  if not v_deleted then
    raise exception 'the line could not be deleted a second time';
  end if;

  -- A deleted row with no recorded time is a row the rule cannot protect,
  -- and the two ways to get one are the two that were nearly shipped: rows
  -- already deleted when the column was added, and rows that arrive already
  -- deleted through an insert a before-update trigger never sees.
  for v_table in
    select unnest(array[
      'recipes', 'foods', 'meal_plan_entries', 'shopping_list_items',
      'collections', 'plan_templates', 'ingredient_matches'
    ])
  loop
    execute format(
      'select count(*) from public.%I where is_deleted and deleted_at is null',
      v_table
    ) into v_count;
    if v_count > 0 then
      raise exception '% has % deleted rows that can still be resurrected',
        v_table, v_count;
    end if;
  end loop;

  -- The backfill, which nothing else can reach. A fresh database has no
  -- rows left over from before the rule existed, so the statement that gave
  -- them a time would otherwise ship untested — and it is the whole of what
  -- protects everything deleted up to now.
  --
  -- The trigger has to come off to manufacture the state, which is itself
  -- the point: once it is on, a deleted row cannot be talked out of its
  -- `deleted_at` by any update at all.
  insert into public.shopping_list_items (
    shopping_list_id, item_key, raw_name, is_deleted, updated_at
  )
  values (v_list, 'oats', 'Oats', true, timestamptz '2026-09-14 12:00:00Z')
  returning id into v_id;

  alter table public.shopping_list_items
    disable trigger shopping_list_items_refuse_resurrection;
  update public.shopping_list_items set deleted_at = null where id = v_id;

  -- Still off for the backfill, exactly as the migration takes the triggers
  -- away before running it. That ordering is load-bearing rather than tidy:
  -- with the rule in force, an update changing neither flag holds
  -- `deleted_at` at what the row already had — so the backfill would undo
  -- itself, silently, and protect nothing. This guard failed that way first.
  update public.shopping_list_items set deleted_at = updated_at
    where is_deleted and deleted_at is null;

  alter table public.shopping_list_items
    enable trigger shopping_list_items_refuse_resurrection;

  select deleted_at into v_at from public.shopping_list_items where id = v_id;
  if v_at is null then
    raise exception 'the backfill left a deleted row without a time';
  end if;

  update public.shopping_list_items
    set is_deleted = false, updated_at = timestamptz '2020-01-01 00:00:00Z'
    where id = v_id;
  select is_deleted into v_deleted
    from public.shopping_list_items where id = v_id;
  if not v_deleted then
    raise exception 'a backfilled row was resurrected by an older write';
  end if;

  -- Arriving already deleted. A recipe created and deleted while offline
  -- reaches the server as a single insert, because the outbox supersedes the
  -- create with the delete.
  insert into public.shopping_list_items (
    shopping_list_id, item_key, raw_name, is_deleted, updated_at
  )
  values (
    v_list, 'butter', 'Butter', true, timestamptz '2026-09-14 12:00:00Z'
  )
  returning id into v_id;

  select deleted_at into v_at from public.shopping_list_items where id = v_id;
  if v_at is null then
    raise exception 'a row inserted already deleted recorded no time';
  end if;

  update public.shopping_list_items
    set is_deleted = false, updated_at = timestamptz '2020-01-01 00:00:00Z'
    where id = v_id;
  select is_deleted into v_deleted
    from public.shopping_list_items where id = v_id;
  if not v_deleted then
    raise exception 'a row inserted already deleted was resurrected';
  end if;

  -- A client cannot name the time itself. There are no column grants in this
  -- schema, so `deleted_at` is writable through the API like any other
  -- column, and a far-future one would put a row beyond anything the app can
  -- do about it.
  insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
    values (v_list, 'flour', 'Flour') returning id into v_id;

  update public.shopping_list_items
    set is_deleted = true,
        deleted_at = timestamptz '9999-01-01 00:00:00Z',
        updated_at = timestamptz '2026-09-14 12:00:00Z'
    where id = v_id;

  select deleted_at into v_at from public.shopping_list_items where id = v_id;
  if v_at <> timestamptz '2026-09-14 12:00:00Z' then
    raise exception 'a client named its own deletion time: %', v_at;
  end if;

  -- And it cannot park one on a row that is still alive for the next
  -- deletion to adopt.
  insert into public.shopping_list_items (shopping_list_id, item_key, raw_name)
    values (v_list, 'sugar', 'Sugar') returning id into v_id;

  update public.shopping_list_items
    set deleted_at = timestamptz '9999-01-01 00:00:00Z',
        updated_at = timestamptz '2026-09-14 12:00:00Z'
    where id = v_id;
  select deleted_at into v_at from public.shopping_list_items where id = v_id;
  if v_at is not null then
    raise exception 'a live row was made to carry a deletion time: %', v_at;
  end if;

  delete from public.households where id = v_house;
  raise notice 'resurrection guards passed';
end;
$$;

-- ── Two phones can set the same week's targets (spec §7.1) ─────────────────
--
-- `macro_targets` is unique on (user_id, week_start_date) and keyed on the
-- id. Both phones in a household decide this week's targets on their own,
-- offline, and each used to mint its own id for the same constrained pair —
-- so the second to reach the server was refused by the unique key, for ever,
-- because retrying carries the same id it was refused for.
--
-- New rows derive their id from the pair now, but a row written before that
-- still carries a random one, and the two have to be able to meet.
do $$
declare
  v_user uuid := gen_random_uuid();
  v_rows integer;
  v_kcal numeric;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  values (
    v_user, '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', v_user || '@targets-guard.test', 'x', now(), now(), now()
  );

  insert into public.macro_targets (
    id, user_id, week_start_date, kcal, protein_g, carb_g, fat_g
  )
  values (gen_random_uuid(), v_user, date '2026-09-07', 2000, 150, 200, 70);

  -- The other phone, with an id of its own, resolving on the pair the key is
  -- on — which is what the client asks PostgREST to do.
  insert into public.macro_targets (
    id, user_id, week_start_date, kcal, protein_g, carb_g, fat_g
  )
  values (gen_random_uuid(), v_user, date '2026-09-07', 2200, 150, 200, 70)
  on conflict (user_id, week_start_date) do update
    set id = excluded.id, kcal = excluded.kcal;

  select count(*), max(kcal) into v_rows, v_kcal
  from public.macro_targets where user_id = v_user;

  if v_rows <> 1 then
    raise exception 'one week, two rows: %', v_rows;
  end if;
  if v_kcal <> 2200 then
    raise exception 'the later write did not win: %', v_kcal;
  end if;

  -- Only what this guard made. A new user arrives with a household and a
  -- profile attached by trigger, and unpicking those is not this guard's
  -- business — the database it runs against is reset, and the other guards
  -- in this file leave their fixtures behind for the same reason.
  delete from public.macro_targets where user_id = v_user;

  raise notice 'macro target guards passed';
end;
$$;

-- ── The live suite still has an account to sign in as (spec §9.3) ──────────
--
-- The integration suite is the only place sync meets a real Postgres,
-- PostgREST and GoTrue, and it signs in as one seeded account. That account
-- did not exist for the whole life of this repository, so the suite failed on
-- its first line and nobody saw — because the suite is not in CI, and cannot
-- be: it needs the local stack running.
--
-- These guards are in CI. So this is where the fixture gets watched: if the
-- seed stops producing something that can authenticate, this says so on the
-- next run rather than the next time somebody happens to try the live tests.
do $$
declare
  v_user uuid;
  v_recipe uuid := '11111111-1111-4111-8111-111111111111';
begin
  select id into v_user from auth.users where email = 'pull@hearth.test';
  if v_user is null then
    raise exception 'the live suite has no account to sign in as';
  end if;

  -- A password GoTrue can actually check. `crypt` returns the same hash for
  -- the right password and the stored salt, and something else for anything
  -- else — so this is the sign-in, in one line.
  if not exists (
    select 1 from auth.users
    where id = v_user
      and encrypted_password =
          extensions.crypt('HearthPull2026a', encrypted_password)
  ) then
    raise exception 'the fixture password would not authenticate';
  end if;

  -- Unconfirmed, and GoTrue refuses the sign-in.
  if not exists (
    select 1 from auth.users where id = v_user and email_confirmed_at is not null
  ) then
    raise exception 'the fixture account is not confirmed';
  end if;

  -- No identity, and there is nothing for email sign-in to match against.
  if not exists (
    select 1 from auth.identities where user_id = v_user and provider = 'email'
  ) then
    raise exception 'the fixture account has no email identity';
  end if;

  -- And the library the suite reads back, with the children it checks: a
  -- recipe row alone would prove it arrived and nothing about whether its
  -- ingredients and steps came with it.
  if not exists (select 1 from public.recipes where id = v_recipe) then
    raise exception 'the seeded recipe the live suite looks for is gone';
  end if;
  if (select count(*) from public.recipe_ingredients where recipe_id = v_recipe)
     <> 2 then
    raise exception 'the seeded recipe no longer has the two ingredients';
  end if;
  if not exists (
    select 1 from public.recipe_steps
    where recipe_id = v_recipe and timer_seconds = 120
  ) then
    raise exception 'the seeded step lost its timer';
  end if;

  raise notice 'live fixture guards passed';
end;
$$;

-- ── The AI ceiling reserves before it spends (spec §3, §8.1) ───────────────
--
-- `ai_usage_this_month` was a read, and a read is a fact about the past:
-- twenty requests arriving together all saw the same pre-call total and all
-- proceeded. The reservation is what the *next* request can see, so this is
-- the guard that matters — that a second call counts the first one's claim,
-- that a claim nobody settles expires instead of holding the money for the
-- month, and that a client cannot reach any of it.
do $$
declare
  v_month date := date_trunc('month', now())::date;
  v_had boolean;
  v_id uuid;
  v_second uuid;
  v_allowed boolean;
  v_spent numeric;
  v_offenders text;
begin
  select exists(select 1 from public.ai_usage where month = v_month) into v_had;

  -- Under a $1 ceiling, two 60-cent claims fit and the third does not — but
  -- only because what is outstanding is counted. Without that, all three pass
  -- against a table that says nothing has been spent.
  select reservation_id, allowed into v_id, v_allowed
    from public.reserve_ai_spend(0.60, 'extract', 1.00, 300);
  if not v_allowed then
    raise exception 'the first claim of the month was refused';
  end if;

  select reservation_id, allowed into v_second, v_allowed
    from public.reserve_ai_spend(0.60, 'extract', 1.00, 300);
  if not v_allowed then
    raise exception 'the second claim was refused with 40 cents still free';
  end if;

  select allowed into v_allowed
    from public.reserve_ai_spend(0.60, 'extract', 1.00, 300);
  if v_allowed then
    raise exception 'a third claim passed a ceiling already fully reserved';
  end if;

  -- Settling records what it really cost and gives the claim back.
  perform public.settle_ai_spend(v_id, 1000, 2000, 0.0330);
  if exists (select 1 from public.ai_reservations where id = v_id) then
    raise exception 'a settled reservation outlived its call';
  end if;
  select cost_usd into v_spent from public.ai_usage where month = v_month;
  if v_spent <> 0.0330 then
    raise exception 'settling recorded % rather than 0.0330', v_spent;
  end if;

  -- Releasing gives it back without recording anything.
  perform public.release_ai_spend(v_second);
  if exists (select 1 from public.ai_reservations where id = v_second) then
    raise exception 'a released reservation was left standing';
  end if;
  select cost_usd into v_spent from public.ai_usage where month = v_month;
  if v_spent <> 0.0330 then
    raise exception 'releasing charged for a call that never happened';
  end if;

  -- A ceiling of zero or less is a misconfiguration, not permission. Checked
  -- here, with nothing outstanding, so it is the zero that refuses and not
  -- the claims above it.
  select allowed into v_allowed
    from public.reserve_ai_spend(0.60, 'extract', 0, 300);
  if v_allowed then
    raise exception 'a ceiling of zero was read as unlimited';
  end if;

  -- And one that nobody settles is swept by the next claim rather than
  -- holding the money until the month turns over. Deliberately larger than
  -- the whole ceiling: at 90 cents it would be refused-or-not for the wrong
  -- reason, and the guard would pass whether the sweep ran or not.
  insert into public.ai_reservations (month, mode, amount_usd, expires_at)
  values (v_month, 'extract', 1.50, now() - interval '1 minute');
  select allowed into v_allowed
    from public.reserve_ai_spend(0.60, 'extract', 1.00, 300);
  if not v_allowed then
    raise exception 'an expired reservation was still holding the ceiling up';
  end if;

  -- Nothing this block did is anybody's real spending.
  delete from public.ai_reservations where month = v_month;
  if v_had then
    update public.ai_usage
       set calls = calls - 1, input_tokens = input_tokens - 1000,
           output_tokens = output_tokens - 2000, cost_usd = cost_usd - 0.0330
     where month = v_month;
  else
    delete from public.ai_usage where month = v_month;
  end if;

  -- The ledger is the security boundary the ceiling rests on: a client that
  -- could write either table, or call either function, could raise its own.
  select string_agg(p.tablename || '.' || p.policyname, ', ') into v_offenders
    from pg_policies p
   where p.schemaname = 'public'
     and p.tablename in ('ai_usage', 'ai_reservations')
     and p.cmd <> 'SELECT';
  if v_offenders is not null then
    raise exception 'the AI ledger has a write policy: %', v_offenders;
  end if;

  if has_table_privilege('authenticated', 'public.ai_reservations', 'INSERT')
     or has_table_privilege('authenticated', 'public.ai_reservations', 'DELETE')
     or has_table_privilege('anon', 'public.ai_reservations', 'INSERT')
     or has_table_privilege('anon', 'public.ai_reservations', 'DELETE') then
    raise exception 'a client can write the reservation ledger directly';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.reserve_ai_spend(numeric, text, numeric, integer)',
       'EXECUTE')
     or has_function_privilege(
       'authenticated',
       'public.settle_ai_spend(uuid, bigint, bigint, numeric)',
       'EXECUTE')
     or has_function_privilege(
       'authenticated', 'public.release_ai_spend(uuid)', 'EXECUTE') then
    raise exception 'a client can move the AI ledger itself';
  end if;

  raise notice 'AI budget reservation guards passed';
end;
$$;

-- ── The `private` schema is not a hole in guards 1 and 2 ────────────────────
--
-- Both of those scan `nspname = 'public'`, so a table in `private` passes them
-- vacuously. That is exactly the kind of test-that-could-only-pass this file
-- exists to avoid, and `private.nest_link` holds a live credential for the
-- household's heating — so the checks are widened rather than dodged.

do $$
declare
  offenders text;
begin
  -- RLS on, even though nothing can address these rows through PostgREST.
  -- The list of exposed schemas is a hosted setting outside this repository,
  -- so the table must not rely on that setting being right.
  select string_agg(c.relname, ', ')
  into offenders
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relkind = 'r'
    and not c.relrowsecurity;

  if offenders is not null then
    raise exception 'RLS is not enabled on private tables: %', offenders;
  end if;

  -- And no policies, which is the correct policy set here: a row nothing but
  -- the secret key may ever read. A policy appearing on one of these is a
  -- sign somebody reached for the public-table pattern by habit.
  select string_agg(c.relname, ', ')
  into offenders
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relkind = 'r'
    and exists (select 1 from pg_policy p where p.polrelid = c.oid);

  if offenders is not null then
    raise exception
      'private tables must have no policies, but these do: %', offenders;
  end if;

  raise notice 'private schema RLS guards passed';
end;
$$;

do $$
begin
  -- The client's two roles cannot so much as enter the schema.
  if has_schema_privilege('anon', 'private', 'USAGE') then
    raise exception 'anon has USAGE on schema private';
  end if;
  if has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated has USAGE on schema private';
  end if;

  raise notice 'private schema access guards passed';
end;
$$;

do $$
declare
  offenders text;
begin
  -- Nor execute any of the doors into it. These are `security definer`, so an
  -- execute grant would hand the caller the table's whole contents.
  select string_agg(p.proname, ', ')
  into offenders
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'nest\_link\_%'
    and (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );

  if offenders is not null then
    raise exception
      'the client can execute nest_link functions: %', offenders;
  end if;

  raise notice 'nest link function guards passed';
end;
$$;
