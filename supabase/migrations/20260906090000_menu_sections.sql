-- Where an item sits on a restaurant's menu (spec §5.2).
--
-- A menu is not an alphabetical list. Meats sit together, salsas sit
-- together, and somebody looking for guacamole looks under the toppings — so
-- a builder that sorts A to Z asks people to read the whole thing every time.
--
-- Two columns because one cannot do it. `menu_group` names the section;
-- `menu_order` is the position on the sheet, which orders the items inside a
-- section *and* the sections themselves, by where each one first appears.
-- Without the integer the sections could only be alphabetised, which is the
-- problem again one level up.
--
-- Null on everything that is not a restaurant food, and null is fine on one
-- too: an ungrouped item is listed after the sections that have names, not
-- hidden.
--
-- No RLS change. `foods` is already default-deny with policies covering every
-- column on it (CLAUDE.md rule 2, spec §8.2).

alter table public.foods
  add column if not exists menu_group text,
  add column if not exists menu_order integer;

comment on column public.foods.menu_group is
  'The section of a restaurant menu this item sits in — Proteins, Salsas, '
  'Toppings (spec §5.2). Null for anything not off a menu.';
comment on column public.foods.menu_order is
  'Its position on the sheet. Orders items within a section, and sections '
  'against each other by where each first appears.';

-- ── Both functions restated in full ─────────────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Patching them by hand is exactly how a column ends up missing
-- on the hosted database while every local check passes (CLAUDE.md rule 8).
-- Last defined entire in 20260905090000_minor_nutrients.sql.

create or replace function public.upsert_food(p_food jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_food_id uuid := (p_food ->> 'id')::uuid;
begin
  insert into public.foods (
    id, household_id, name, brand, store_tag, barcode, grams_per_millilitre,
    source, macros_overridden, is_default, is_zero_calorie, is_deleted,
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
    is_deleted           = excluded.is_deleted,
    walmart_item_id      = excluded.walmart_item_id,
    pack_canonical       = excluded.pack_canonical,
    pack_kind            = excluded.pack_kind,
    pack_unit            = excluded.pack_unit,
    menu_group           = excluded.menu_group,
    menu_order           = excluded.menu_order,
    updated_at           = excluded.updated_at;

  delete from public.food_serving_options where food_id = v_food_id;

  insert into public.food_serving_options (
    id, food_id, label, amount_canonical, amount_kind, amount_unit,
    kcal, protein_g, carb_g, fat_g,
    fiber_g, sodium_mg, cholesterol_mg,
    sort_order
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
