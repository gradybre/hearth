-- The pull half of sync (spec §7.1).
--
-- Returns whole aggregates in exactly the shape the client pushes, so one
-- parser serves both directions. Fetching the four recipe tables separately
-- and stitching them client-side would mean a recipe could arrive with
-- ingredients from one moment and steps from another.
--
-- SECURITY INVOKER, so a caller sees precisely the rows RLS grants them —
-- their household's, and nothing else.

create or replace function public.changed_recipes(p_since timestamptz default null)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'household_id', r.household_id,
    'title', r.title,
    'servings', r.servings,
    'prep_seconds', r.prep_seconds,
    'cook_seconds', r.cook_seconds,
    'cuisine', r.cuisine,
    'tags', to_jsonb(r.tags),
    'source', r.source,
    'photo_url', r.photo_url,
    'notes', r.notes,
    'created_by', r.created_by,
    'is_deleted', r.is_deleted,
    'updated_at', r.updated_at,
    'sections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'recipe_id', s.recipe_id, 'name', s.name,
        'sort_order', s.sort_order
      ) order by s.sort_order)
      from public.recipe_sections s where s.recipe_id = r.id
    ), '[]'::jsonb),
    'ingredients', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'recipe_id', i.recipe_id, 'section_id', i.section_id,
        'food_id', i.food_id, 'raw_text', i.raw_text, 'name', i.name,
        'quantity_canonical', i.quantity_canonical,
        'quantity_kind', i.quantity_kind, 'quantity_unit', i.quantity_unit,
        'prep_note', i.prep_note, 'is_optional', i.is_optional,
        'sort_order', i.sort_order
      ) order by i.sort_order)
      from public.recipe_ingredients i where i.recipe_id = r.id
    ), '[]'::jsonb),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', st.id, 'recipe_id', st.recipe_id, 'section_id', st.section_id,
        'step_number', st.step_number, 'body', st.body,
        'timer_seconds', st.timer_seconds
      ) order by st.step_number)
      from public.recipe_steps st where st.recipe_id = r.id
    ), '[]'::jsonb)
  )
  from public.recipes r
  where p_since is null or r.updated_at >= p_since
  order by r.updated_at;
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
