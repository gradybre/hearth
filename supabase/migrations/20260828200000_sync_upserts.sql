-- Whole-aggregate upserts for sync (spec §7.1).
--
-- A recipe is one record to the user and four tables to Postgres. Pushing it
-- as four client calls means a dropped connection can leave a recipe whose
-- ingredients are half the old set and half the new — a recipe that never
-- existed on either device. These functions take the whole thing and replace
-- its children in one statement, so it lands whole or not at all.
--
-- SECURITY INVOKER (the default) on purpose: RLS must still apply. These are a
-- convenience for atomicity, not a way around the policies — a household can
-- only write its own rows here exactly as it can through the tables.

create or replace function public.upsert_recipe(p_recipe jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_recipe_id uuid := (p_recipe ->> 'id')::uuid;
begin
  insert into public.recipes (
    id, household_id, title, servings, prep_seconds, cook_seconds, cuisine,
    tags, source, photo_url, notes, created_by, is_deleted, updated_at
  )
  values (
    v_recipe_id,
    (p_recipe ->> 'household_id')::uuid,
    p_recipe ->> 'title',
    (p_recipe ->> 'servings')::numeric,
    (p_recipe ->> 'prep_seconds')::integer,
    (p_recipe ->> 'cook_seconds')::integer,
    p_recipe ->> 'cuisine',
    coalesce(
      (select array_agg(value #>> '{}') from jsonb_array_elements(p_recipe -> 'tags')),
      '{}'
    ),
    coalesce(p_recipe ->> 'source', 'manual'),
    p_recipe ->> 'photo_url',
    p_recipe ->> 'notes',
    (p_recipe ->> 'created_by')::uuid,
    coalesce((p_recipe ->> 'is_deleted')::boolean, false),
    coalesce((p_recipe ->> 'updated_at')::timestamptz, now())
  )
  on conflict (id) do update set
    household_id = excluded.household_id,
    title        = excluded.title,
    servings     = excluded.servings,
    prep_seconds = excluded.prep_seconds,
    cook_seconds = excluded.cook_seconds,
    cuisine      = excluded.cuisine,
    tags         = excluded.tags,
    source       = excluded.source,
    photo_url    = excluded.photo_url,
    notes        = excluded.notes,
    created_by   = excluded.created_by,
    is_deleted   = excluded.is_deleted,
    updated_at   = excluded.updated_at;

  -- Children are replaced, never merged: the client sends the whole recipe,
  -- so anything absent has been removed. Steps and ingredients go first
  -- because they reference the sections.
  delete from public.recipe_steps where recipe_id = v_recipe_id;
  delete from public.recipe_ingredients where recipe_id = v_recipe_id;
  delete from public.recipe_sections where recipe_id = v_recipe_id;

  insert into public.recipe_sections (id, recipe_id, name, sort_order)
  select
    (s ->> 'id')::uuid, v_recipe_id, s ->> 'name',
    coalesce((s ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(coalesce(p_recipe -> 'sections', '[]'::jsonb)) as s;

  insert into public.recipe_ingredients (
    id, recipe_id, section_id, food_id, raw_text, name, quantity_canonical,
    quantity_kind, quantity_unit, prep_note, is_optional, sort_order
  )
  select
    (i ->> 'id')::uuid, v_recipe_id, (i ->> 'section_id')::uuid,
    (i ->> 'food_id')::uuid, i ->> 'raw_text', i ->> 'name',
    (i ->> 'quantity_canonical')::numeric, i ->> 'quantity_kind',
    i ->> 'quantity_unit', i ->> 'prep_note',
    coalesce((i ->> 'is_optional')::boolean, false),
    coalesce((i ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(coalesce(p_recipe -> 'ingredients', '[]'::jsonb)) as i;

  insert into public.recipe_steps (
    id, recipe_id, section_id, step_number, body, timer_seconds
  )
  select
    (st ->> 'id')::uuid, v_recipe_id, (st ->> 'section_id')::uuid,
    (st ->> 'step_number')::integer, st ->> 'body',
    (st ->> 'timer_seconds')::integer
  from jsonb_array_elements(coalesce(p_recipe -> 'steps', '[]'::jsonb)) as st;
end;
$$;

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
    source, macros_overridden, is_deleted, updated_at
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
    is_deleted           = excluded.is_deleted,
    updated_at           = excluded.updated_at;

  delete from public.food_serving_options where food_id = v_food_id;

  insert into public.food_serving_options (
    id, food_id, label, amount_canonical, amount_kind, amount_unit,
    kcal, protein_g, carb_g, fat_g, sort_order
  )
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
