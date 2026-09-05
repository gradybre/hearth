-- A recipe's little hand-drawn sketch (spec §5.2, §6.1).
--
-- Markup in a column, not a picture in a bucket. A sketch is a few hundred
-- bytes of path data; it stays crisp at any size, it syncs with the recipe
-- rather than through a second upload path with its own retry loop, and —
-- because it carries no colours of its own — it takes the theme's at render
-- time, which is what lets one icon look right in both light and dark.
--
-- Additive and nullable. No icon is the ordinary state, not a failure, and
-- every recipe written before today is in it.
--
-- The length cap is here as well as in the client because a limit only the
-- client enforces is a limit the next client forgets. Four kilobytes is a
-- generous sketch and a poor traced photograph, which is the line worth
-- drawing: this column is read on every row of the recipe library.
--
-- Rendering it is the client's problem and the client refuses anything
-- outside a small whitelist (`SketchIcon`). This constraint is about size,
-- not about safety — no database check can decide whether markup is safe to
-- draw, so nothing here pretends to.
--
-- No RLS change. `recipes` is already household-scoped and default-deny, and
-- its policies cover every column on it (CLAUDE.md rule 2, spec §8.2).

alter table public.recipes
  add column if not exists icon_svg text
    check (icon_svg is null or length(icon_svg) <= 4096);

comment on column public.recipes.icon_svg is
  'A hand-drawn sketch of the dish as SVG markup, drawn by the recipe-ai '
  'function and validated by the client before it is stored or rendered. '
  'Decorative: null is ordinary (spec §5.2, §6.1).';

-- ── Both functions restated in full ─────────────────────────────────────────
--
-- `create or replace` replaces the whole body, so anything not repeated here
-- is deleted. Patching them by hand is exactly how a column ends up missing
-- on the hosted database while every local check passes (CLAUDE.md rule 8).
-- Last defined entire in 20260905120000_recipe_kind.sql.

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
    tags, kind, source, photo_url, icon_svg, notes, created_by, is_deleted,
    updated_at
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
    coalesce(p_recipe ->> 'kind', 'cooked'),
    coalesce(p_recipe ->> 'source', 'manual'),
    p_recipe ->> 'photo_url',
    p_recipe ->> 'icon_svg',
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
    kind         = excluded.kind,
    source       = excluded.source,
    photo_url    = excluded.photo_url,
    icon_svg     = excluded.icon_svg,
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
    quantity_kind, quantity_unit, prep_note, is_optional, needs_no_match,
    sort_order
  )
  select
    (i ->> 'id')::uuid, v_recipe_id, (i ->> 'section_id')::uuid,
    (i ->> 'food_id')::uuid, i ->> 'raw_text', i ->> 'name',
    (i ->> 'quantity_canonical')::numeric, i ->> 'quantity_kind',
    i ->> 'quantity_unit', i ->> 'prep_note',
    coalesce((i ->> 'is_optional')::boolean, false),
    coalesce((i ->> 'needs_no_match')::boolean, false),
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
  where p_since is null or r.updated_at >= p_since
  order by r.updated_at;
$$;
