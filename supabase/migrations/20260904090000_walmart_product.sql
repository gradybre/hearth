-- A food can carry the Walmart product actually bought (spec §5.7).
--
-- Walmart's add-to-cart URL is open to anyone — no key, no approval — but it
-- is keyed by item id, and Hearth holds names. Resolving one to the other
-- needs the catalog API, which really is partner-gated, so the ids come from
-- the household instead: pasted once per food they buy regularly.
--
-- pack_* is how much is in one of those, so "2 lb of beef" can become a
-- number of packets rather than a quantity of 1. Optional, and stored as the
-- canonical trio every other quantity here uses.

alter table public.foods
  add column if not exists walmart_item_id text,
  add column if not exists pack_canonical numeric,
  add column if not exists pack_kind text
    check (pack_kind in ('volume', 'mass', 'count')),
  add column if not exists pack_unit text;

comment on column public.foods.walmart_item_id is
  'The Walmart item id — the trailing number of a product URL, which is what '
  'identifies the product; the slug is decorative (spec §5.7).';
comment on column public.foods.pack_canonical is
  'How much is in one pack, for rounding a needed amount up to whole packs. '
  'Optional: a wrong pack size does not fail, it silently orders the wrong '
  'number, so absent beats guessed.';

-- ── Both functions restated in full ─────────────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Patching them by hand is exactly how a column ends up missing
-- on the hosted database while every local check passes (CLAUDE.md rule 8).
-- Last defined entire in 20260831210000_zero_calorie_foods.sql.

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
    updated_at           = excluded.updated_at;

  delete from public.food_serving_options where food_id = v_food_id;

  insert into public.food_serving_options (
    id, food_id, label, amount_canonical, amount_kind, amount_unit,
    kcal, protein_g, carb_g, fat_g, sort_order
  )
  -- Unchanged from the original definition. Repeated verbatim because
  -- `create or replace` replaces the whole body, so anything not restated
  -- here would simply be deleted.
  select
    (o ->> 'id')::uuid, v_food_id, o ->> 'label',
    (o ->> 'amount_canonical')::numeric, o ->> 'amount_kind',
    o ->> 'amount_unit',
    coalesce((o ->> 'kcal')::numeric, 0),
    coalesce((o ->> 'protein_g')::numeric, 0),
    coalesce((o ->> 'carb_g')::numeric, 0),
    coalesce((o ->> 'fat_g')::numeric, 0),
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
    'updated_at', f.updated_at,
    'serving_options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'food_id', o.food_id, 'label', o.label,
        'amount_canonical', o.amount_canonical, 'amount_kind', o.amount_kind,
        'amount_unit', o.amount_unit, 'kcal', o.kcal,
        'protein_g', o.protein_g, 'carb_g', o.carb_g, 'fat_g', o.fat_g,
        'sort_order', o.sort_order
      ) order by o.sort_order)
      from public.food_serving_options o where o.food_id = f.id
    ), '[]'::jsonb)
  )
  from public.foods f
  where p_since is null or f.updated_at >= p_since
  order by f.updated_at;
$$;
