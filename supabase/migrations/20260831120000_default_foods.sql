-- Default foods (spec §5.3).
--
-- A household's standing choices: mark the ground beef you actually buy, and
-- a recipe line calling for ground beef matches it without being asked. The
-- matching itself is client-side (`FoodConcept`), because it is a reading of
-- what a name says rather than a query — this column is only the mark.
--
-- Deliberately not unique per anything. Whole, 2% and non-fat milk are all
-- defaults at once; the variant in the name is what tells them apart, and a
-- line naming no variant is answered by a short menu rather than a guess.
--
-- Additive, so no policy changes: `foods` is already household-scoped and
-- default-deny, and the existing policies cover every column on it
-- (CLAUDE.md rule 2, spec §8.2).

alter table public.foods
  add column if not exists is_default boolean not null default false;

comment on column public.foods.is_default is
  'One of the household''s standing choices, auto-matched to recipe lines '
  'naming the same thing (spec §5.3).';

-- Both halves of sync name their columns explicitly, so both have to learn
-- the new one. A column added to the table and not to these would round-trip
-- as false and silently un-mark every default on the next pull.

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
    source, macros_overridden, is_default, is_deleted, updated_at
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
