-- The package-to-serving relationship, and the display preference beside it.
--
-- Run against a local database, from the repository root:
--   docker exec -i supabase_db_hearth psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/package_nutrition.sql
--
-- Everything below runs inside one transaction that is rolled back at the
-- end, so it leaves nothing behind and can be run against a database that is
-- already seeded. The fixtures are global foods (no household), which is what
-- lets this file run without manufacturing an auth user: RLS is not the
-- subject here, and `schema_guards.sql` already proves it holds.
--
-- The one fact this whole feature rests on is the join between a printed net
-- weight and a printed serving count, and there are exactly two places it can
-- be lost: a record that is stored in a shape nothing can use, and a sync
-- write that resets or forgets one half of it. Both are checked here rather
-- than trusted, because neither would fail loudly -- the user would simply get
-- a wrong number of calories for a tin of beans.

\set ON_ERROR_STOP on

begin;

-- ── 1. Defaults, and the enum ──────────────────────────────────────────────
--
-- Every food that already exists gets the conservative answer, and only the
-- three documented answers can be written.
do $$
declare
  v_food uuid := gen_random_uuid();
  v_mode text;
  v_record jsonb;
begin
  insert into public.foods (id, name) values (v_food, 'Package guard oats');

  select mass_display_mode, package_nutrition into v_mode, v_record
  from public.foods where id = v_food;

  if v_mode is distinct from 'automatic' then
    raise exception 'a new food did not default to automatic: %', v_mode;
  end if;
  if v_record is not null then
    raise exception 'a new food invented a package relation: %', v_record;
  end if;

  -- Not-null with a default, because "unknown" is not one of the answers a
  -- display preference has.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'foods'
      and column_name = 'mass_display_mode'
      and (is_nullable = 'YES' or column_default is null)
  ) then
    raise exception 'foods.mass_display_mode is nullable or has no default';
  end if;

  -- Asserted by name: `add column if not exists … check (…)` skips the clause
  -- when the column is already there and reports success, so the constraint
  -- can be absent while every behavioural check below still passes.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.foods'::regclass
      and conname = 'foods_mass_display_mode_check'
  ) then
    raise exception 'the mass_display_mode constraint is missing';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.foods'::regclass
      and conname = 'foods_package_nutrition_valid'
  ) then
    raise exception 'the package_nutrition constraint is missing';
  end if;

  begin
    update public.foods set mass_display_mode = 'pounds' where id = v_food;
    raise exception 'an unknown display mode was accepted';
  exception
    when check_violation then null;
  end;

  foreach v_mode in array array['automatic', 'ounces', 'weight'] loop
    update public.foods set mass_display_mode = v_mode where id = v_food;
  end loop;

  raise notice 'mass display mode guards passed';
end;
$$;

-- ── 2. What may be stored as a relation, and what may not ──────────────────
--
-- The record is the only thing standing between a printed label and a
-- fabricated density, so the shapes that must never reach the column are
-- enumerated rather than described. Each one is a way the feature could
-- silently produce a wrong cup weight.
do $$
declare
  v_food uuid := gen_random_uuid();
  v_cup  uuid := gen_random_uuid();
  -- 10 oz of it, two 1-cup servings: a cup weighs 5 oz.
  v_valid jsonb := jsonb_build_object(
    'version', 1,
    'servings_per_package', 2,
    'serving_option_id', v_cup::text,
    'serving_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'cup'),
    'package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'oz'),
    'is_approximate', false,
    'source', 'manual',
    'basis', 'as_packaged'
  );
  v_bad jsonb;
  v_bads jsonb[];
  v_unit text;
  v_stored jsonb;
begin
  insert into public.foods (id, name, package_nutrition)
  values (v_food, 'Package guard beans', v_valid);

  select package_nutrition into v_stored from public.foods where id = v_food;
  if (v_stored ->> 'servings_per_package')::numeric <> 2
     or v_stored ->> 'serving_option_id' <> v_cup::text
     or (v_stored -> 'package_amount' ->> 'canonical_amount')::numeric
        <> 283.495 then
    raise exception 'a valid relation did not survive being stored: %',
      v_stored;
  end if;

  -- An absent relation is the ordinary state and must always be allowed.
  update public.foods set package_nutrition = null where id = v_food;
  update public.foods set package_nutrition = v_valid where id = v_food;

  -- "About 2 servings" is a printed fact, not a defect.
  update public.foods
  set package_nutrition = v_valid || '{"is_approximate": true}'::jsonb
  where id = v_food;

  -- Half-cup servings, four to the package: the same 10 oz, counted in
  -- servings rather than in cups.
  update public.foods
  set package_nutrition = v_valid || jsonb_build_object(
        'servings_per_package', 4,
        'serving_amount', jsonb_build_object(
          'canonical_amount', 118.294, 'kind', 'volume', 'unit', 'cup'))
  where id = v_food;

  -- Fractional counts are real.
  update public.foods
  set package_nutrition = v_valid || '{"servings_per_package": 2.5}'::jsonb
  where id = v_food;

  -- Every unit either side can be authored in. The allowlist here is a copy
  -- of one kept in Dart, and a unit missing from this copy refuses a record
  -- the user has already reviewed -- which is the failure this loop exists to
  -- catch, because it cannot be seen from either side alone.
  foreach v_unit in array array[
    'tsp', 'tbsp', 'cup', 'fl_oz', 'ml', 'l',
    'pt', 'pint', 'qt', 'quart', 'gal', 'gallon'
  ] loop
    update public.foods
    set package_nutrition = v_valid || jsonb_build_object(
          'serving_amount', jsonb_build_object(
            'canonical_amount', 236.588, 'kind', 'volume', 'unit', v_unit))
    where id = v_food;
  end loop;

  foreach v_unit in array array['g', 'kg', 'oz', 'lb'] loop
    update public.foods
    set package_nutrition = v_valid || jsonb_build_object(
          'package_amount', jsonb_build_object(
            'canonical_amount', 283.495, 'kind', 'mass', 'unit', v_unit))
    where id = v_food;
  end loop;

  update public.foods set package_nutrition = v_valid where id = v_food;

  v_bads := array[
    -- Not an object at all.
    '[]'::jsonb, '{}'::jsonb, '"cup"'::jsonb, '1'::jsonb, 'true'::jsonb,
    -- A version this schema cannot read is not stored half-understood.
    v_valid || '{"version": 2}'::jsonb,
    v_valid || '{"version": "1"}'::jsonb,
    -- A version that is not a number at all. The type test and the cast once
    -- sat either side of a single `or`, and Postgres does not promise to
    -- evaluate an `or` left to right -- so these raised 22P02 where a refusal
    -- was meant, and a raise inside a check constraint is a 500 rather than a
    -- no. Caught here as a check_violation, so a reappearance of the cast
    -- fails this file loudly instead of reaching a user.
    v_valid || jsonb_build_object('version', 'one'),
    v_valid || jsonb_build_object('version', true),
    v_valid || jsonb_build_object('version', null::text),
    v_valid - 'version',
    -- A count that is missing, zero, negative or not a number. Each of these
    -- is a division by nothing dressed up as a measurement.
    v_valid - 'servings_per_package',
    v_valid || '{"servings_per_package": 0}'::jsonb,
    v_valid || '{"servings_per_package": -2}'::jsonb,
    v_valid || '{"servings_per_package": "2"}'::jsonb,
    -- A number no double can hold. jsonb stores it without complaint and the
    -- client reads it back as Infinity, so it is stopped at the column.
    v_valid || '{"servings_per_package": 1e400}'::jsonb,
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 1e400::numeric, 'kind', 'mass', 'unit', 'oz')),
    v_valid || jsonb_build_object('serving_amount', jsonb_build_object(
      'canonical_amount', 1e400::numeric, 'kind', 'volume', 'unit', 'cup')),
    -- A relation bound to nothing.
    v_valid - 'serving_option_id',
    v_valid || '{"serving_option_id": ""}'::jsonb,
    v_valid || '{"serving_option_id": "   "}'::jsonb,
    v_valid || '{"serving_option_id": 7}'::jsonb,
    -- Amounts missing, non-positive, or not numbers.
    v_valid - 'serving_amount',
    v_valid - 'package_amount',
    v_valid || jsonb_build_object('serving_amount', jsonb_build_object(
      'canonical_amount', 0, 'kind', 'volume', 'unit', 'cup')),
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', -283.495, 'kind', 'mass', 'unit', 'oz')),
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 'ten', 'kind', 'mass', 'unit', 'oz')),
    -- The two sides the wrong way round: a package measured by volume, or a
    -- serving weighed, states no mass-to-volume relation at all.
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'cup')),
    v_valid || jsonb_build_object('serving_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'oz')),
    -- A count on either side.
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 1, 'kind', 'count', 'unit', 'item')),
    -- A unit nothing recognises, and a unit of the wrong dimension. oz and
    -- fl oz are not the same thing, and this is where that is kept true.
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'stone')),
    v_valid || jsonb_build_object('package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'cup')),
    v_valid || jsonb_build_object('serving_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'oz')),
    -- A qualifier that is not a yes or a no.
    v_valid - 'is_approximate',
    v_valid || '{"is_approximate": "yes"}'::jsonb,
    -- Where it came from, and what it describes.
    v_valid - 'source',
    v_valid || '{"source": "guess"}'::jsonb,
    v_valid - 'basis',
    -- A drained or as-prepared basis never activates automatically: a net
    -- weight including liquid says nothing about a drained cup.
    v_valid || '{"basis": "drained"}'::jsonb,
    v_valid || '{"basis": "as_prepared"}'::jsonb,
    -- And a record too large to be the compact thing it is meant to be.
    v_valid || jsonb_build_object('serving_option_id', repeat('x', 5000))
  ];

  foreach v_bad in array v_bads loop
    begin
      update public.foods set package_nutrition = v_bad where id = v_food;
      raise exception 'an invalid relation was accepted: %', v_bad;
    exception
      when check_violation then null;
    end;
  end loop;

  -- None of that disturbed the good record.
  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is distinct from v_valid then
    raise exception 'a refused write changed the stored relation: %', v_stored;
  end if;

  -- The validator itself: null in, true out, so the constraint reads as a
  -- permission rather than as an unknown.
  if not public.package_nutrition_is_valid(null) then
    raise exception 'the validator refused an absent relation';
  end if;

  raise notice 'package relation shape guards passed';
end;
$$;

-- ── 3. What sync does with it ──────────────────────────────────────────────
--
-- The record is written by `upsert_food` and read back by `changed_foods`,
-- and the interesting cases are all about a client that has never heard of
-- either column. An older build sends neither key on every write it makes; if
-- that reset them, one phone in a household would quietly undo the other's
-- work, for ever.
do $$
declare
  v_food uuid := gen_random_uuid();
  v_cup  uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_cup_option jsonb := jsonb_build_object(
    'id', v_cup::text, 'label', '1 cup',
    'amount_canonical', 236.588, 'amount_kind', 'volume', 'amount_unit', 'cup',
    'kcal', 100, 'protein_g', 2, 'carb_g', 20, 'fat_g', 1, 'sort_order', 0);
  v_relation jsonb := jsonb_build_object(
    'version', 1,
    'servings_per_package', 2,
    'serving_option_id', v_cup::text,
    'serving_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'cup'),
    'package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'oz'),
    'is_approximate', false,
    'source', 'photos',
    'basis', 'as_packaged'
  );
  v_food_payload jsonb;
  v_stored jsonb;
  v_mode text;
begin
  v_food_payload := jsonb_build_object(
    'id', v_food::text, 'name', 'Package guard corn', 'source', 'manual',
    'pack_canonical', 283.495, 'pack_kind', 'mass', 'pack_unit', 'oz',
    'serving_options', jsonb_build_array(v_cup_option));

  -- The new client, saying everything.
  perform public.upsert_food(
    v_food_payload
    || jsonb_build_object('mass_display_mode', 'ounces',
                          'package_nutrition', v_relation));

  select mass_display_mode, package_nutrition into v_mode, v_stored
  from public.foods where id = v_food;
  if v_mode is distinct from 'ounces' then
    raise exception 'upsert_food lost the display mode: %', v_mode;
  end if;
  if v_stored is distinct from v_relation then
    raise exception 'upsert_food lost the relation: %', v_stored;
  end if;

  -- And the pull half agrees with the push half, which is what puts it on the
  -- other phone.
  if not exists (
    select 1 from public.changed_foods(null) c
    where (c ->> 'id')::uuid = v_food
      and c ->> 'mass_display_mode' = 'ounces'
      and (c -> 'package_nutrition' ->> 'servings_per_package')::numeric = 2
      and c -> 'package_nutrition' ->> 'serving_option_id' = v_cup::text
      and (c -> 'package_nutrition' -> 'package_amount'
             ->> 'canonical_amount')::numeric = 283.495
  ) then
    raise exception 'changed_foods did not carry the relation faithfully';
  end if;

  -- An older build, saying nothing about either. Silence is not an
  -- instruction to forget.
  perform public.upsert_food(v_food_payload);

  select mass_display_mode, package_nutrition into v_mode, v_stored
  from public.foods where id = v_food;
  if v_mode is distinct from 'ounces' then
    raise exception 'an old client reset the display mode to %', v_mode;
  end if;
  if v_stored is distinct from v_relation then
    raise exception 'an old client cleared the relation';
  end if;

  -- The same older build deleting the very serving the relation names. It
  -- must still be able to save -- a user on an old phone who could never edit
  -- a food again is a far worse failure than a stale record -- and what is
  -- left is evidence the client can see is out of date, not a silent wrong
  -- answer.
  perform public.upsert_food(
    v_food_payload || jsonb_build_object('serving_options', '[]'::jsonb));

  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is distinct from v_relation then
    raise exception
      'deleting the serving through an old client destroyed the evidence';
  end if;
  if exists (select 1 from public.food_serving_options where id = v_cup) then
    raise exception 'the serving was not actually deleted';
  end if;

  -- Sending the stored record back unchanged alongside the serving is the
  -- ordinary new-client write and must keep working.
  perform public.upsert_food(
    v_food_payload
    || jsonb_build_object('package_nutrition', v_relation));

  -- An explicit null is the user removing the relation, which is a different
  -- answer from silence and must actually take.
  perform public.upsert_food(
    v_food_payload || jsonb_build_object('package_nutrition', null));

  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is not null then
    raise exception 'clearing the relation did not take: %', v_stored;
  end if;

  -- ── A newly submitted relation has to describe this food ─────────────────

  -- A serving this food does not have.
  begin
    perform public.upsert_food(
      v_food_payload
      || jsonb_build_object('package_nutrition',
           v_relation || jsonb_build_object('serving_option_id',
                                            v_other::text)));
    raise exception 'a relation named a serving this food does not have';
  exception
    when check_violation then null;
  end;

  -- The right serving, reviewed against a different amount: the two halves
  -- arrived out of step, and storing them would state a cup weight nobody
  -- confirmed.
  begin
    perform public.upsert_food(
      v_food_payload
      || jsonb_build_object('package_nutrition',
           v_relation || jsonb_build_object('serving_amount',
             jsonb_build_object('canonical_amount', 118.294,
                                'kind', 'volume', 'unit', 'cup'))));
    raise exception 'a relation was stored against a different serving amount';
  exception
    when check_violation then null;
  end;

  -- And against a different measure entirely.
  begin
    perform public.upsert_food(
      v_food_payload
      || jsonb_build_object('package_nutrition',
           v_relation || jsonb_build_object('serving_amount',
             jsonb_build_object('canonical_amount', 236.588,
                                'kind', 'volume', 'unit', 'ml'))));
    raise exception 'a relation was stored against a different serving unit';
  exception
    when check_violation then null;
  end;

  -- A malformed record never reaches the column through the function either.
  begin
    perform public.upsert_food(
      v_food_payload
      || jsonb_build_object('package_nutrition',
                            v_relation || '{"servings_per_package": 0}'::jsonb));
    raise exception 'upsert_food accepted a package of no servings';
  exception
    when check_violation then null;
  end;

  -- None of those refusals left anything behind.
  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is not null then
    raise exception 'a refused upsert stored a relation anyway: %', v_stored;
  end if;

  -- The good write still works afterwards, and a payload that never mentions
  -- the display mode on a brand-new food gets the conservative default.
  perform public.upsert_food(
    v_food_payload || jsonb_build_object('package_nutrition', v_relation));
  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is distinct from v_relation then
    raise exception 'the relation could not be saved again: %', v_stored;
  end if;

  perform public.upsert_food(jsonb_build_object(
    'id', gen_random_uuid()::text, 'name', 'Package guard plain',
    'source', 'manual', 'serving_options', '[]'::jsonb));

  raise notice 'package relation sync guards passed';
end;
$$;

-- ── 4. Stale evidence survives an unrelated edit (plan §R13) ────────────
--
-- The case that is easy to get exactly backwards. An old client moves the
-- serving the relation was reviewed against; the relation stays, out of date.
-- The user then renames the food on a new client, which sends the stored
-- record back untouched along with everything else it holds. If that resend
-- were judged against the current servings it would be refused, and the food
-- would be unsaveable for ever -- on account of a relation the user has not
-- been asked about yet.
do $$
declare
  v_food uuid := gen_random_uuid();
  v_cup  uuid := gen_random_uuid();
  v_option jsonb := jsonb_build_object(
    'id', v_cup::text, 'label', '1 cup',
    'amount_canonical', 236.588, 'amount_kind', 'volume', 'amount_unit', 'cup',
    'kcal', 100, 'sort_order', 0);
  v_relation jsonb := jsonb_build_object(
    'version', 1, 'servings_per_package', 2,
    'serving_option_id', v_cup::text,
    'serving_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'cup'),
    'package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'oz'),
    'is_approximate', false, 'source', 'manual', 'basis', 'as_packaged');
  v_payload jsonb;
  v_stored jsonb;
  v_name text;
begin
  v_payload := jsonb_build_object(
    'id', v_food::text, 'name', 'Stale guard rice', 'source', 'manual',
    'serving_options', jsonb_build_array(v_option));

  perform public.upsert_food(
    v_payload || jsonb_build_object('package_nutrition', v_relation));

  -- An old client resizes the serving. It says nothing about the relation, so
  -- the relation stays -- now describing a serving that has moved.
  perform public.upsert_food(
    v_payload || jsonb_build_object('serving_options', jsonb_build_array(
      v_option || '{"amount_canonical": 118.294}'::jsonb)));

  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is distinct from v_relation then
    raise exception 'an old client destroyed the stale evidence';
  end if;

  -- The rename, carrying the stored record back verbatim.
  perform public.upsert_food(
    v_payload
    || jsonb_build_object(
         'name', 'Stale guard brown rice',
         'serving_options', jsonb_build_array(
           v_option || '{"amount_canonical": 118.294}'::jsonb),
         'package_nutrition', v_relation));

  select name, package_nutrition into v_name, v_stored
  from public.foods where id = v_food;
  if v_name <> 'Stale guard brown rice' then
    raise exception 'the unrelated edit was refused over a stale relation';
  end if;
  if v_stored is distinct from v_relation then
    raise exception 'resending the stored record changed it: %', v_stored;
  end if;

  -- A genuinely different record is still judged against the servings being
  -- saved, stale predecessor or not. This is the line that keeps the
  -- exemption above from becoming a way round the check altogether.
  begin
    perform public.upsert_food(
      v_payload
      || jsonb_build_object(
           'serving_options', jsonb_build_array(
             v_option || '{"amount_canonical": 118.294}'::jsonb),
           'package_nutrition',
           v_relation || '{"servings_per_package": 4}'::jsonb));
    raise exception 'a changed relation skipped its serving check';
  exception
    when check_violation then null;
  end;

  select package_nutrition into v_stored from public.foods where id = v_food;
  if v_stored is distinct from v_relation then
    raise exception 'a refused change disturbed the stored relation';
  end if;

  raise notice 'stale relation guards passed';
end;
$$;

-- ── 5. The paged pull says exactly what the unpaged one says ───────────────
--
-- The client reads only `changed_foods_page`. Every existing guard for a food
-- column reads `changed_foods`, which the app no longer calls -- so a key
-- added to one definition and forgotten in the other is invisible until a
-- phone quietly stops seeing package relations, which is how this pair first
-- diverged. Compared whole, so the next key added is covered for free.
do $$
declare
  v_food uuid := gen_random_uuid();
  v_cup uuid := gen_random_uuid();
  v_relation jsonb := jsonb_build_object(
    'version', 1, 'servings_per_package', 2,
    'serving_option_id', v_cup::text,
    'serving_amount', jsonb_build_object(
      'canonical_amount', 236.588, 'kind', 'volume', 'unit', 'cup'),
    'package_amount', jsonb_build_object(
      'canonical_amount', 283.495, 'kind', 'mass', 'unit', 'oz'),
    'is_approximate', true, 'source', 'mixed', 'basis', 'as_packaged');
  v_paged jsonb;
  v_unpaged jsonb;
begin
  perform public.upsert_food(jsonb_build_object(
    'id', v_food::text, 'name', 'Paged guard cheddar', 'source', 'manual',
    'mass_display_mode', 'weight',
    'package_nutrition', v_relation,
    'serving_options', jsonb_build_array(jsonb_build_object(
      'id', v_cup::text, 'label', '1 cup',
      'amount_canonical', 236.588, 'amount_kind', 'volume',
      'amount_unit', 'cup', 'kcal', 100, 'sort_order', 0))));

  select c into v_paged
  from public.changed_foods_page(null, null, null, 1000) c
  where (c ->> 'id')::uuid = v_food;

  select c into v_unpaged
  from public.changed_foods(null) c
  where (c ->> 'id')::uuid = v_food;

  if v_paged is null then
    raise exception 'the paged pull did not return the food at all';
  end if;
  if v_paged ->> 'mass_display_mode' is distinct from 'weight' then
    raise exception 'the paged pull lost the display mode: %',
      v_paged ->> 'mass_display_mode';
  end if;
  if v_paged -> 'package_nutrition' is distinct from v_relation then
    raise exception 'the paged pull lost the relation: %',
      v_paged -> 'package_nutrition';
  end if;
  if v_paged is distinct from v_unpaged then
    raise exception 'the paged and unpaged payloads differ: % vs %',
      v_paged, v_unpaged;
  end if;

  raise notice 'paged pull guards passed';
end;
$$;

-- ── 6. Nothing here runs as anybody else ───────────────────────────────────
--
-- The sync functions are security invoker, which is the whole of what keeps a
-- client writing only what its own policies allow -- a definer would hand it
-- every household's library and the global catalogue with it. And the two
-- validators back a check constraint, which does not behave sensibly for a
-- function that is not really immutable.
do $$
declare
  v_offenders text;
begin
  select string_agg(p.proname, ', ') into v_offenders
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'upsert_food', 'changed_foods', 'changed_foods_page',
      'package_nutrition_is_valid', 'package_nutrition_amount_is_valid')
    and p.prosecdef;
  if v_offenders is not null then
    raise exception 'these now run as their owner: %', v_offenders;
  end if;

  select string_agg(p.proname, ', ') into v_offenders
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'package_nutrition_is_valid', 'package_nutrition_amount_is_valid')
    and p.provolatile <> 'i';
  if v_offenders is not null then
    raise exception 'a package_nutrition validator is not immutable: %',
      v_offenders;
  end if;

  -- Two columns on a table that already has its policies, and this migration
  -- must not have disturbed them.
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'foods' and c.relrowsecurity
  ) then
    raise exception 'RLS is no longer enabled on foods';
  end if;

  raise notice 'function volatility and invoker guards passed';
end;
$$;

rollback;
