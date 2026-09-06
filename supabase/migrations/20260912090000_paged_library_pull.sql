-- Read a library a page at a time (spec §7.1, R04).
--
-- `changed_recipes` and `changed_foods` took only `p_since` and returned
-- everything at once — so PostgREST's `max_rows` truncated them, the client
-- could not tell, and the watermark advanced past whatever was cut off. The
-- plain-select tables were fixed in Dart; these two need the server's help,
-- because a `setof jsonb` has nowhere for a client to put a cursor.
--
-- **New functions rather than new parameters.** `create or replace` cannot
-- change a signature, so adding defaulted parameters would create an overload
-- and make `changed_recipes(p_since => x)` ambiguous — and dropping the old
-- one would break any phone still running an older build for as long as it
-- took to update. A separate name costs a few lines and no rollout window.
--
-- Ordered by `(updated_at, id)`: `updated_at` alone is not unique, and a
-- cursor that cannot move is a page that repeats for ever. Ascending, so a
-- row written during a pull sorts to the end — where the reader is still
-- heading — rather than shifting a page boundary under rows already read.
--
-- The limit is clamped rather than trusted: a caller asking for a million
-- rows would be asking PostgREST to truncate again, silently, which is the
-- defect this exists to remove.
--
-- Restated in full from their last whole definitions —
-- 20260911090000_recipe_icon.sql and 20260910090000_modifier_foods.sql —
-- because `create or replace` replaces the entire body and patching by hand
-- is how a column goes missing on the hosted database while every local check
-- passes (CLAUDE.md rule 8).
--
-- The old single-argument functions are deliberately left in place. They are
-- what an older client calls, and nothing here removes them.

create or replace function public.changed_recipes_page(
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
    'id', r.id,
    'household_id', r.household_id,
    'title', r.title,
    'servings', r.servings,
    'prep_seconds', r.prep_seconds,
    'cook_seconds', r.cook_seconds,
    'cuisine', r.cuisine,
    'tags', to_jsonb(r.tags),
    'kind', r.kind,
    'source', r.source,
    'photo_url', r.photo_url,
    'icon_svg', r.icon_svg,
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
        'needs_no_match', i.needs_no_match,
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
  where (p_since is null or r.updated_at >= p_since)
    -- Keyset: everything sorted after the last row the caller saw.
    -- `(updated_at, id)` because `updated_at` alone is not unique, and a
    -- cursor that cannot move is a page that repeats for ever.
    and (
      p_after_updated_at is null
      or r.updated_at > p_after_updated_at
      or (r.updated_at = p_after_updated_at and r.id > p_after_id)
    )
  order by r.updated_at, r.id
  limit greatest(1, least(p_limit, 1000));
$$;

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
