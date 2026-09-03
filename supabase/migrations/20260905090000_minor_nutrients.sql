-- Fibre, sodium and cholesterol on a serving (spec §5.6).
--
-- Lifted from §12's deferred list at Brendan's request; the spec was amended
-- in the same change rather than left contradicting this.
--
-- Nullable, and null means **unknown** — unlike kcal/protein/carb/fat, which
-- are `not null default 0` because they are always known. A food with no
-- fibre data is not a food with no fibre, and a `default 0` here would erase
-- that distinction on the way into the database, where no later care could
-- recover it. Hence no defaults and no not-null.
--
-- No check that they are >= 0 either, matching how the four are guarded: the
-- four carry `>= 0` because a negative calorie is meaningless, and so is a
-- negative fibre — so they do get the same guard, but written to allow null.

alter table public.food_serving_options
  add column if not exists fiber_g numeric check (fiber_g >= 0),
  add column if not exists sodium_mg numeric check (sodium_mg >= 0),
  add column if not exists cholesterol_mg numeric check (cholesterol_mg >= 0);

comment on column public.food_serving_options.fiber_g is
  'Grams of dietary fibre, or null when the source did not say. Null is '
  'unknown, never zero (spec §5.6).';
comment on column public.food_serving_options.sodium_mg is
  'Milligrams of sodium, or null. Open Food Facts reports grams per 100 g and '
  'a label prints milligrams; the adapters convert to mg before storing.';
comment on column public.food_serving_options.cholesterol_mg is
  'Milligrams of cholesterol, or null.';

-- No RLS change. `food_serving_options` is already default-deny with policies
-- keyed on `food_is_visible`, and those cover every column on the table
-- (CLAUDE.md rule 2, spec §8.2). Stated rather than assumed.

-- ── Both functions restated in full ─────────────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Patching them by hand is exactly how a column ends up missing
-- on the hosted database while every local check passes (CLAUDE.md rule 8).
-- Last defined entire in 20260904090000_walmart_product.sql.

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
