-- A package size that also says what a serving weighs (plan §R9–R13).
--
-- A label prints two facts that nothing in this schema could previously join:
-- the net weight on the front (10 oz) and the servings per container on the
-- back (2, of 1 cup). Together they say that a cup of *this* food weighs 5 oz,
-- which is what lets 30 oz of it in a recipe resolve to six nutrition
-- servings. Neither fact alone says anything, so they are stored as one
-- record rather than as three columns that can drift apart in sync.
--
-- ── Why one jsonb rather than columns ──────────────────────────────────────
--
-- The count, the serving it counts, and the two amounts it was reviewed
-- against are a single claim. Split across columns, an old client that writes
-- only some of them leaves a count pointing at a serving it never saw, and the
-- result is a wrong cup weight rather than a missing one. As one value it is
-- written whole or not at all, and a record whose basis has moved is
-- detectably stale instead of quietly wrong.
--
-- ── What the database refuses, and what it leaves to the client ────────────
--
-- Refused here: any shape that is not a complete, finite, in-dimension
-- version-1 record, and any newly submitted record naming a serving this food
-- does not have. Left to the client: deciding whether a *stored* record is
-- still live. An old client that deletes the serving the record names must
-- still be able to save the food — refusing it would strand a user on an old
-- build with a food they can never edit again — so the record survives as
-- stale evidence and the client compares the current facts against the
-- snapshots, exactly as the plan describes.
--
-- No RLS change and none is needed: two columns on a table that already has
-- its policies. Both functions stay `security invoker`, so a client can still
-- only write what its own policies allow.

-- ── The display preference ─────────────────────────────────────────────────

alter table public.foods
  add column if not exists mass_display_mode text not null default 'automatic';

-- Named and added separately, deliberately. `add column if not exists … check
-- (…)` skips the whole clause — the check with it — when the column is already
-- there, and reports success. A constraint added by name is either present or
-- it is not, and a guard can say which.
alter table public.foods
  drop constraint if exists foods_mass_display_mode_check,
  add constraint foods_mass_display_mode_check
    check (mass_display_mode in ('automatic', 'ounces', 'weight'));

comment on column public.foods.mass_display_mode is
  'How this food''s masses are totalled for display: automatic follows the '
  'source hints, ounces pins them to oz, weight uses the oz/lb ladder. A '
  'presentation choice only -- package and serving labels keep their own '
  'authored units, and no canonical quantity is affected.';

-- ── The package-to-serving relationship ────────────────────────────────────

-- One half of the validator, so the two amount snapshots are judged by the
-- same rules. `case` rather than a chain of `and`s: Postgres is free to
-- evaluate the operands of `and` in any order, so a cast sitting behind a
-- type test can still run against a string and raise where a `false` was
-- meant -- and a raise inside a check constraint is an error where a refusal
-- was meant.
create or replace function public.package_nutrition_amount_is_valid(
  p_amount jsonb,
  p_kind text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_amount) is distinct from 'object' then false
    when jsonb_typeof(p_amount -> 'canonical_amount') is distinct from 'number'
      then false
    when (p_amount ->> 'canonical_amount')::numeric <= 0 then false
    -- And bounded to what a double can hold. jsonb keeps a numeric, so 1e400
    -- is stored here without complaint and then arrives on the client as
    -- Infinity, where every conversion built on it quietly becomes a NaN.
    when (p_amount ->> 'canonical_amount')::numeric
         > 1.7976931348623157e308::numeric then false
    when (p_amount ->> 'kind') is distinct from p_kind then false
    -- The unit is the authored one, and it has to be a unit of the dimension
    -- the snapshot claims. oz and fl oz are not the same thing, and this is
    -- the line that keeps them apart.
    when p_kind = 'mass'
      and (p_amount ->> 'unit') in ('g', 'kg', 'oz', 'lb') then true
    -- Every volume unit a serving can be authored in. A carton whose serving
    -- is printed in pints is unremarkable, and a list that omits it refuses a
    -- record the user has already reviewed -- which reaches them as an opaque
    -- sync failure rather than as anything they can correct.
    --
    -- Both spellings, because this list is a copy of one kept in Dart and the
    -- two must not be able to disagree quietly. Admitting a spelling the
    -- client never writes costs nothing: the kind must still agree, so
    -- everything here is a volume either way.
    when p_kind = 'volume'
      and (p_amount ->> 'unit') in (
        'tsp', 'tbsp', 'cup', 'fl_oz', 'ml', 'l',
        'pt', 'pint', 'qt', 'quart', 'gal', 'gallon'
      ) then true
    else false
  end
$$;

comment on function public.package_nutrition_amount_is_valid(jsonb, text) is
  'One amount snapshot inside a package_nutrition record: an object with a '
  'positive canonical_amount, the kind asked for, and a recognised unit of '
  'that dimension.';

-- The whole record. Returns false rather than null for every rejection, so
-- the check constraint denies rather than passing on an unknown.
create or replace function public.package_nutrition_is_valid(p_record jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
begin
  -- No relation at all is the ordinary state, not a failure.
  if p_record is null then
    return true;
  end if;

  if jsonb_typeof(p_record) is distinct from 'object' then
    return false;
  end if;

  -- A compact record. The bound is here rather than trusted to the client
  -- because this column is read on every row of the library, and `octet_length`
  -- of the text form is immutable where `pg_column_size` is not.
  if octet_length(p_record::text) > 4096 then
    return false;
  end if;

  -- A version this schema does not understand is not stored. A future client
  -- bumps the version and deploys its migration first; until then there is
  -- nothing here that could be activated by mistake.
  -- Two statements rather than one `or`. Postgres does not promise to
  -- evaluate the operands of `or` left to right, so a cast sitting behind a
  -- type test can still run against a version of `one` or `true` and raise
  -- 22P02 -- and a raise inside a check constraint is a 500 where a refusal
  -- was meant. The `case` in the amount validator above is written that way
  -- for exactly this reason; this was the one place it was not.
  if jsonb_typeof(p_record -> 'version') is distinct from 'number' then
    return false;
  end if;
  if (p_record ->> 'version')::numeric is distinct from 1 then
    return false;
  end if;

  -- A count of servings, not of cups. Positive and finite -- jsonb cannot
  -- hold a NaN, so the type test is the whole of that guarantee. Fractional
  -- counts such as 2.5 are real and are allowed.
  if jsonb_typeof(p_record -> 'servings_per_package') is distinct from 'number'
  then
    return false;
  end if;
  if (p_record ->> 'servings_per_package')::numeric <= 0 then
    return false;
  end if;
  -- Representable as a double, for the same reason as the amounts above: a
  -- count of Infinity servings divides a real package into nothing.
  if (p_record ->> 'servings_per_package')::numeric
     > 1.7976931348623157e308::numeric then
    return false;
  end if;

  -- Bound to one serving row, never to whichever row happens to be first.
  if jsonb_typeof(p_record -> 'serving_option_id') is distinct from 'string'
     or length(trim(p_record ->> 'serving_option_id')) = 0 then
    return false;
  end if;

  -- The relation this record exists to state is mass to volume: a package
  -- weighed, a serving measured. A count on either side cannot establish it.
  if not public.package_nutrition_amount_is_valid(
       p_record -> 'serving_amount', 'volume') then
    return false;
  end if;
  if not public.package_nutrition_amount_is_valid(
       p_record -> 'package_amount', 'mass') then
    return false;
  end if;

  -- "About 2 servings" is a printed fact and is carried as one. It is not a
  -- reason to refuse the record, and it is not something to drop either.
  if jsonb_typeof(p_record -> 'is_approximate') is distinct from 'boolean' then
    return false;
  end if;

  if jsonb_typeof(p_record -> 'source') is distinct from 'string'
     or (p_record ->> 'source') not in ('manual', 'photos', 'mixed') then
    return false;
  end if;

  -- Only as-packaged. A net weight including liquid says nothing about a
  -- drained cup, and a dry package says nothing about a cooked one, so no
  -- other basis may be stored for something that converts automatically.
  if jsonb_typeof(p_record -> 'basis') is distinct from 'string'
     or (p_record ->> 'basis') <> 'as_packaged' then
    return false;
  end if;

  -- Additional keys inside an otherwise valid version-1 record are left
  -- alone: they are bounded by the size cap, they are preserved verbatim on
  -- writes that do not mention them, and nothing here reads them.
  return true;
end;
$$;

comment on function public.package_nutrition_is_valid(jsonb) is
  'True for SQL NULL, or for a complete version-1 package_nutrition record '
  'within 4 KiB. Never raises and never returns null, so the check constraint '
  'it backs denies rather than erroring.';

alter table public.foods
  add column if not exists package_nutrition jsonb;

alter table public.foods
  drop constraint if exists foods_package_nutrition_valid,
  add constraint foods_package_nutrition_valid
    check (public.package_nutrition_is_valid(package_nutrition));

comment on column public.foods.package_nutrition is
  'One reviewed claim joining the net package amount to the nutrition '
  'serving: how many of the selected serving are in a package, with snapshots '
  'of both amounts as they stood when it was confirmed. Stored whole so the '
  'count and the serving it counts cannot drift apart in sync. Whether a '
  'stored record is still live is decided by the client, by comparing the '
  'current package and serving facts against those snapshots.';

-- ── Both sync functions restated in full ───────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Last defined entire in 20260910090000_modifier_foods.sql, and
-- everything it did is carried forward unchanged: the modifier flag, the
-- deliberate absence of `coalesce` on the minor nutrients, and the delete of
-- the old serving rows *before* the food is upserted, which is what lets a
-- modifier be turned back into an ordinary food.
--
-- What is new is that key presence now decides. An old client's payload does
-- not mention either column, and its writes must leave both alone rather than
-- resetting them to a default -- so `?` is asked, not `->>`. An explicit
-- `null` is a different answer from silence: it is the user removing the
-- relation.

create or replace function public.upsert_food(p_food jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_food_id uuid := (p_food ->> 'id')::uuid;
  v_is_modifier boolean :=
    coalesce((p_food ->> 'is_modifier')::boolean, false);
  -- Silence and an explicit null are different answers, and only `?` can
  -- tell them apart.
  v_has_mass_display boolean := p_food ? 'mass_display_mode';
  v_mass_display text :=
    coalesce(p_food ->> 'mass_display_mode', 'automatic');
  v_has_package_nutrition boolean := p_food ? 'package_nutrition';
  -- `->` gives back the jsonb null for an explicit null, which is not the
  -- SQL null the column wants.
  v_package_nutrition jsonb :=
    nullif(p_food -> 'package_nutrition', 'null'::jsonb);
  v_option jsonb;
  v_snapshot jsonb;
  v_existing_found boolean;
  v_existing_package_nutrition jsonb;
begin
  -- What this row already says, read under the caller's own policies -- a
  -- food in another household simply is not found, and the insert below
  -- would refuse it anyway.
  --
  -- Deliberately not `for update`: locking a row demands the UPDATE policy
  -- for something the caller may only be entitled to read, and the
  -- `on conflict do update` below takes its own lock in any case. This read
  -- only decides whether the incoming record needs checking, so the worst a
  -- concurrent write can do is leave stale evidence that some transaction
  -- had already validated -- never store a relation nothing checked.
  select true, f.package_nutrition
    into v_existing_found, v_existing_package_nutrition
  from public.foods f
  where f.id = v_food_id;
  -- ── A newly submitted relation must describe this food ───────────────────
  --
  -- Only when the payload actually carries one. A write that says nothing
  -- about the relation is not a claim about it, and must not be able to fail
  -- on account of one -- otherwise an old client that deletes the named
  -- serving could never save this food again.
  if v_has_package_nutrition and v_package_nutrition is not null then
    if not public.package_nutrition_is_valid(v_package_nutrition) then
      raise exception
        'package_nutrition is not a complete version 1 record'
        using errcode = 'check_violation';
    end if;

    -- Only when the relation is actually changing, or the food is new.
    -- Sending back exactly what is already stored is not a claim about
    -- anything: it is what every ordinary edit does. An old client may have
    -- moved or removed the serving the stored record names, and refusing
    -- that resend would leave the food uneditable for ever, over a relation
    -- the user was never shown. The record stays as stale evidence and the
    -- client decides, which is the whole of the plan's staleness rule.
    if coalesce(v_existing_found, false)
       and v_existing_package_nutrition is not distinct from v_package_nutrition
    then
      null;
    else

    select o into v_option
    from jsonb_array_elements(
      coalesce(p_food -> 'serving_options', '[]'::jsonb)
    ) as o
    where o ->> 'id' = v_package_nutrition ->> 'serving_option_id'
    limit 1;

    if v_option is null then
      raise exception
        'package_nutrition names serving % , which this food does not have',
        v_package_nutrition ->> 'serving_option_id'
        using errcode = 'check_violation';
    end if;

    -- The snapshot is what the user reviewed. If it disagrees with the
    -- serving being saved alongside it, the two arrived out of step and the
    -- relation is about a serving that no longer exists in that form.
    v_snapshot := v_package_nutrition -> 'serving_amount';

    if (v_option ->> 'amount_kind') is distinct from (v_snapshot ->> 'kind')
       or (v_option ->> 'amount_unit') is distinct from (v_snapshot ->> 'unit')
    then
      raise exception
        'package_nutrition was reviewed against a different serving measure'
        using errcode = 'check_violation';
    end if;

    -- Relative, with an absolute floor, so the same number written by two
    -- clients at different precisions still agrees.
    if abs(
         (v_option ->> 'amount_canonical')::numeric
         - (v_snapshot ->> 'canonical_amount')::numeric
       ) > 1e-9 * greatest(
            1.0,
            abs((v_option ->> 'amount_canonical')::numeric),
            abs((v_snapshot ->> 'canonical_amount')::numeric)
          )
    then
      raise exception
        'package_nutrition was reviewed against a different serving amount'
        using errcode = 'check_violation';
    end if;

    end if;
  end if;

  -- Before the upsert, deliberately: with the composite modifier foreign key
  -- in place, upserting first would cascade a cleared flag into serving rows
  -- that still hold negatives.
  delete from public.food_serving_options where food_id = v_food_id;

  insert into public.foods (
    id, household_id, name, brand, store_tag, barcode, grams_per_millilitre,
    source, macros_overridden, is_default, is_zero_calorie, is_modifier,
    is_deleted,
    walmart_item_id, pack_canonical, pack_kind, pack_unit,
    menu_group, menu_order,
    mass_display_mode, package_nutrition,
    updated_at
  )
  values (
    v_food_id,
    (p_food ->> 'household_id')::uuid,
    p_food ->> 'name',
    p_food ->> 'brand',
    p_food ->> 'store_tag',
    p_food ->> 'barcode',
    (p_food ->> 'grams_per_millilitre')::numeric,
    coalesce(p_food ->> 'source', 'manual'),
    coalesce((p_food ->> 'macros_overridden')::boolean, false),
    coalesce((p_food ->> 'is_default')::boolean, false),
    coalesce((p_food ->> 'is_zero_calorie')::boolean, false),
    v_is_modifier,
    coalesce((p_food ->> 'is_deleted')::boolean, false),
    p_food ->> 'walmart_item_id',
    (p_food ->> 'pack_canonical')::numeric,
    p_food ->> 'pack_kind',
    p_food ->> 'pack_unit',
    p_food ->> 'menu_group',
    (p_food ->> 'menu_order')::integer,
    -- Defaults apply on insert only. A food this server has never seen has
    -- no preference to preserve.
    case when v_has_mass_display then v_mass_display else 'automatic' end,
    case when v_has_package_nutrition then v_package_nutrition else null end,
    coalesce((p_food ->> 'updated_at')::timestamptz, now())
  )
  on conflict (id) do update set
    household_id         = excluded.household_id,
    name                 = excluded.name,
    brand                = excluded.brand,
    store_tag            = excluded.store_tag,
    barcode              = excluded.barcode,
    grams_per_millilitre = excluded.grams_per_millilitre,
    source               = excluded.source,
    macros_overridden    = excluded.macros_overridden,
    is_default           = excluded.is_default,
    is_zero_calorie      = excluded.is_zero_calorie,
    is_modifier          = excluded.is_modifier,
    is_deleted           = excluded.is_deleted,
    walmart_item_id      = excluded.walmart_item_id,
    pack_canonical       = excluded.pack_canonical,
    pack_kind            = excluded.pack_kind,
    pack_unit            = excluded.pack_unit,
    menu_group           = excluded.menu_group,
    menu_order           = excluded.menu_order,
    -- Omitted means "I have nothing to say about this", which an older build
    -- says about both of these on every write it makes.
    mass_display_mode    = case
                             when v_has_mass_display then v_mass_display
                             else foods.mass_display_mode
                           end,
    package_nutrition    = case
                             when v_has_package_nutrition
                               then v_package_nutrition
                             else foods.package_nutrition
                           end,
    updated_at           = excluded.updated_at;

  insert into public.food_serving_options (
    id, food_id, label, amount_canonical, amount_kind, amount_unit,
    kcal, protein_g, carb_g, fat_g,
    fiber_g, sodium_mg, cholesterol_mg,
    is_modifier, sort_order
  )
  select
    (o ->> 'id')::uuid, v_food_id, o ->> 'label',
    (o ->> 'amount_canonical')::numeric, o ->> 'amount_kind',
    o ->> 'amount_unit',
    coalesce((o ->> 'kcal')::numeric, 0),
    coalesce((o ->> 'protein_g')::numeric, 0),
    coalesce((o ->> 'carb_g')::numeric, 0),
    coalesce((o ->> 'fat_g')::numeric, 0),
    -- Deliberately no `coalesce`. A serving whose payload is silent about
    -- fibre is silent, not zero, and this is the line where that would be
    -- lost for good.
    (o ->> 'fiber_g')::numeric,
    (o ->> 'sodium_mg')::numeric,
    (o ->> 'cholesterol_mg')::numeric,
    -- From the food, never from the serving.
    v_is_modifier,
    coalesce((o ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(
    coalesce(p_food -> 'serving_options', '[]'::jsonb)
  ) as o;
end;
$$;

create or replace function public.changed_foods(p_since timestamptz default null)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', f.id,
    'household_id', f.household_id,
    'name', f.name,
    'brand', f.brand,
    'store_tag', f.store_tag,
    'barcode', f.barcode,
    'grams_per_millilitre', f.grams_per_millilitre,
    'source', f.source,
    'macros_overridden', f.macros_overridden,
    'is_default', f.is_default,
    'is_zero_calorie', f.is_zero_calorie,
    'is_modifier', f.is_modifier,
    'is_deleted', f.is_deleted,
    'walmart_item_id', f.walmart_item_id,
    'pack_canonical', f.pack_canonical,
    'pack_kind', f.pack_kind,
    'pack_unit', f.pack_unit,
    'menu_group', f.menu_group,
    'menu_order', f.menu_order,
    'mass_display_mode', f.mass_display_mode,
    'package_nutrition', f.package_nutrition,
    'updated_at', f.updated_at,
    'serving_options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'food_id', o.food_id, 'label', o.label,
        'amount_canonical', o.amount_canonical, 'amount_kind', o.amount_kind,
        'amount_unit', o.amount_unit, 'kcal', o.kcal,
        'protein_g', o.protein_g, 'carb_g', o.carb_g, 'fat_g', o.fat_g,
        'fiber_g', o.fiber_g, 'sodium_mg', o.sodium_mg,
        'cholesterol_mg', o.cholesterol_mg,
        'sort_order', o.sort_order
      ) order by o.sort_order)
      from public.food_serving_options o where o.food_id = f.id
    ), '[]'::jsonb)
  )
  from public.foods f
  where p_since is null or f.updated_at >= p_since
  order by f.updated_at;
$$;

-- Paged pulls carry the same food payload as legacy pulls.
create or replace function public.changed_foods_page(
  p_since timestamptz default null,
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 500
)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', f.id,
    'household_id', f.household_id,
    'name', f.name,
    'brand', f.brand,
    'store_tag', f.store_tag,
    'barcode', f.barcode,
    'grams_per_millilitre', f.grams_per_millilitre,
    'source', f.source,
    'macros_overridden', f.macros_overridden,
    'is_default', f.is_default,
    'is_zero_calorie', f.is_zero_calorie,
    'is_modifier', f.is_modifier,
    'is_deleted', f.is_deleted,
    'walmart_item_id', f.walmart_item_id,
    'pack_canonical', f.pack_canonical,
    'pack_kind', f.pack_kind,
    'pack_unit', f.pack_unit,
    'menu_group', f.menu_group,
    'menu_order', f.menu_order,
    'mass_display_mode', f.mass_display_mode,
    'package_nutrition', f.package_nutrition,
    'updated_at', f.updated_at,
    'serving_options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'food_id', o.food_id, 'label', o.label,
        'amount_canonical', o.amount_canonical, 'amount_kind', o.amount_kind,
        'amount_unit', o.amount_unit, 'kcal', o.kcal,
        'protein_g', o.protein_g, 'carb_g', o.carb_g, 'fat_g', o.fat_g,
        'fiber_g', o.fiber_g, 'sodium_mg', o.sodium_mg,
        'cholesterol_mg', o.cholesterol_mg,
        'sort_order', o.sort_order
      ) order by o.sort_order)
      from public.food_serving_options o where o.food_id = f.id
    ), '[]'::jsonb)
  )
  from public.foods f
  where (p_since is null or f.updated_at >= p_since)
    -- Keyset: everything sorted after the last row the caller saw.
    -- `(updated_at, id)` because `updated_at` alone is not unique, and a
    -- cursor that cannot move is a page that repeats for ever.
    and (
      p_after_updated_at is null
      or f.updated_at > p_after_updated_at
      or (f.updated_at = p_after_updated_at and f.id > p_after_id)
    )
  order by f.updated_at, f.id
  limit greatest(1, least(p_limit, 1000));
$$;
