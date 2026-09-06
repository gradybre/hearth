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
-- because all three fail silently.
do $$
declare
  v_after_ts timestamptz := null;
  v_after_id uuid := null;
  v_rows integer;
  v_total integer := 0;
  v_pages integer := 0;
  v_last jsonb;
begin
  -- 1. Cursoring reads every row exactly once.
  loop
    select count(*) into v_rows
    from public.changed_foods_page(null, v_after_ts, v_after_id, 100);
    exit when v_rows = 0;

    v_pages := v_pages + 1;
    v_total := v_total + v_rows;
    if v_pages > 200 then
      raise exception 'paging did not finish: the cursor is not advancing';
    end if;

    -- The page's *last* row in the page's own ordering. Getting this
    -- backwards overlaps the pages and counts rows twice — which is how this
    -- guard first failed, and is exactly the mistake a client could make.
    select x into v_last
    from public.changed_foods_page(null, v_after_ts, v_after_id, 100) x
    order by (x ->> 'updated_at') desc, (x ->> 'id') desc
    limit 1;
    v_after_ts := (v_last ->> 'updated_at')::timestamptz;
    v_after_id := (v_last ->> 'id')::uuid;
  end loop;

  if v_total <> (select count(*) from public.foods) then
    raise exception 'paging read % foods, the table holds %',
      v_total, (select count(*) from public.foods);
  end if;

  -- 2. The limit is clamped rather than trusted. A caller asking for a
  -- million is asking PostgREST to truncate again, silently.
  if (select count(*) from public.changed_foods_page(null, null, null, 999999))
     > 1000 then
    raise exception 'the page limit is not clamped';
  end if;

  -- 3. The unpaged functions are still there. They are what a phone running
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
