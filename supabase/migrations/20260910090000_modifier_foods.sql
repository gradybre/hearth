-- A menu row published as a deduction (spec §5.2).
--
-- Freddy's prints "Make any Sandwich a Lettuce Wrap" as -180 kcal, -3 g
-- protein, -25 g carb, -6 g fat, +1 g fibre, -270 mg sodium. It is a
-- modification rather than something you order, and the seed that added
-- Freddy's dropped it because `food_serving_options` refuses a negative.
--
-- Note the mixed signs: fibre goes *up* when the bun comes off. A single
-- "negate everything" flag would be wrong, so the storage has to be genuinely
-- signed.
--
-- ── Why the flag is on both tables ─────────────────────────────────────────
--
-- A check constraint cannot see another table, so `foods.is_modifier` is
-- invisible to a check on `food_serving_options`. The flag is therefore
-- denormalised onto the child and then made structurally unable to disagree,
-- with a composite foreign key into a unique index on (id, is_modifier).
--
-- `on update cascade` is what makes the invariant hold in both directions.
-- Un-flagging a food rewrites its serving rows, the signed check fires on the
-- negatives still in them, and the parent update fails. "A modifier's flag and
-- its servings agree" stops being something to test and becomes something that
-- cannot be represented.
--
-- Rejected: a trigger, which `pg_constraint` cannot see, needs a second
-- trigger on `foods` to close the un-flag hole, and costs a query per row. And
-- a check calling a `stable` function, which Postgres accepts and then never
-- re-evaluates -- a negative survives un-flagging under a constraint that
-- reports itself as passing.
--
-- No RLS change, and none is needed: both tables already have their policies,
-- and this adds a column rather than a new surface. `foods_update_household`
-- still requires a household, so the flag on a global food is a seed's to set
-- (CLAUDE.md rule 2).

alter table public.foods
  add column if not exists is_modifier boolean not null default false;

comment on column public.foods.is_modifier is
  'A menu row published as a deduction rather than as something you order -- '
  '"make it a lettuce wrap", -180 kcal. Its serving options may hold negative '
  'values; nothing else may. Never logged on its own, never matched into a '
  'recipe: it is what you log against.';

-- A modifier that was also a default would be auto-matched into cooked
-- recipes, which is the one place a deduction must never reach.
alter table public.foods
  drop constraint if exists foods_modifier_is_not_default,
  add constraint foods_modifier_is_not_default
    check (not (is_default and is_modifier));

create unique index if not exists foods_id_is_modifier_key
  on public.foods (id, is_modifier);

alter table public.food_serving_options
  add column if not exists is_modifier boolean not null default false;

comment on column public.food_serving_options.is_modifier is
  'Carried from the food it belongs to and never authored on its own. It '
  'exists so the signed checks below can see it, and the composite foreign '
  'key keeps it honest.';

alter table public.food_serving_options
  drop constraint if exists food_serving_options_modifier_fkey,
  add constraint food_serving_options_modifier_fkey
    foreign key (food_id, is_modifier)
    references public.foods (id, is_modifier)
    on delete cascade on update cascade;

-- ── The seven checks, swapped for signed ones ──────────────────────────────
--
-- Dropped by discovery rather than by name. The originals were auto-named,
-- and a column that had ever been dropped and re-added would carry `_check1`
-- instead -- so the migration finds whatever is actually there rather than
-- guessing at the hosted database from the local one.
do $$
declare
  v_name text;
begin
  for v_name in
    select conname
    from pg_constraint
    where conrelid = 'public.food_serving_options'::regclass
      and contype = 'c'
      and conname ~ ('^food_serving_options_(kcal|protein_g|carb_g|fat_g'
                     '|fiber_g|sodium_mg|cholesterol_mg)_check[0-9]*$')
  loop
    execute format(
      'alter table public.food_serving_options drop constraint %I', v_name);
  end loop;
end;
$$;

alter table public.food_serving_options
  drop constraint if exists food_serving_options_kcal_signed,
  drop constraint if exists food_serving_options_protein_g_signed,
  drop constraint if exists food_serving_options_carb_g_signed,
  drop constraint if exists food_serving_options_fat_g_signed,
  drop constraint if exists food_serving_options_fiber_g_signed,
  drop constraint if exists food_serving_options_sodium_mg_signed,
  drop constraint if exists food_serving_options_cholesterol_mg_signed,
  add constraint food_serving_options_kcal_signed
    check (kcal >= 0 or is_modifier),
  add constraint food_serving_options_protein_g_signed
    check (protein_g >= 0 or is_modifier),
  add constraint food_serving_options_carb_g_signed
    check (carb_g >= 0 or is_modifier),
  add constraint food_serving_options_fat_g_signed
    check (fat_g >= 0 or is_modifier),
  add constraint food_serving_options_fiber_g_signed
    check (fiber_g >= 0 or is_modifier),
  add constraint food_serving_options_sodium_mg_signed
    check (sodium_mg >= 0 or is_modifier),
  add constraint food_serving_options_cholesterol_mg_signed
    check (cholesterol_mg >= 0 or is_modifier);

-- ── Both functions restated in full ─────────────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Patching them by hand is exactly how a column ends up missing on
-- the hosted database while every local check passes (CLAUDE.md rule 8).
-- Last defined entire in 20260906090000_menu_sections.sql.
--
-- One thing has moved, and it is not cosmetic. The delete of the old serving
-- rows now runs *before* the food is upserted. With the composite foreign key
-- in place, upserting first and deleting second means that un-ticking the
-- modifier switch cascades the new `is_modifier = false` into serving rows
-- that still hold negatives, the signed checks fire, and the whole transaction
-- dies -- so a user who changed their mind would get an opaque sync failure
-- and a food that could never be saved again. Deleting first means there is
-- nothing left to cascade into.

create or replace function public.upsert_food(p_food jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_food_id uuid := (p_food ->> 'id')::uuid;
  v_is_modifier boolean :=
    coalesce((p_food ->> 'is_modifier')::boolean, false);
begin
  -- Before the upsert, deliberately. See the note above.
  delete from public.food_serving_options where food_id = v_food_id;

  insert into public.foods (
    id, household_id, name, brand, store_tag, barcode, grams_per_millilitre,
    source, macros_overridden, is_default, is_zero_calorie, is_modifier,
    is_deleted,
    walmart_item_id, pack_canonical, pack_kind, pack_unit,
    menu_group, menu_order,
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
    -- From the food, never from the serving. The column exists to carry the
    -- food's answer to a place a check constraint can see it, and a payload
    -- that disagreed would be refused by the composite foreign key anyway.
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
