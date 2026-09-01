-- Foods that really are zero (spec §5.5).
--
-- All-zero macros are usually a half-filled import, and `Food.needsAttention`
-- is right to say so. But black coffee, sparkling water and a zero-calorie
-- sweetener genuinely are zero, and without a way to say which, that warning
-- could never be cleared — it would sit on the coffee for ever, and a warning
-- that cannot be cleared is one that stops being read.
--
-- Only ever set deliberately. Inferring it from "somebody saved this food"
-- would give the same answer for a food saved without noticing the numbers
-- were missing, which is the exact case the warning exists for.
--
-- Additive, so no policy changes: `foods` is already household-scoped and
-- default-deny, and the existing policies cover every column on it
-- (CLAUDE.md rule 2, spec §8.2).

alter table public.foods
  add column if not exists is_zero_calorie boolean not null default false;

comment on column public.foods.is_zero_calorie is
  'Confirmed to carry no macros, as opposed to missing them (spec §5.5).';

-- Both halves of sync name their columns explicitly, so both learn the new
-- one. Copied verbatim from the current definitions and patched in exactly
-- one place each: `create or replace` replaces the whole body, so anything
-- not restated here would simply be deleted.

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
