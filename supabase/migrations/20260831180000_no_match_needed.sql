-- "No match needed" — lines that were never going to have macros (spec §5.3).
--
-- A pinch of salt has nothing to match and never will, but it counted among a
-- recipe's unmatched ingredients all the same. A warning that is always on
-- stops being read, so every recipe was quietly training its reader to ignore
-- the one thing that flags real gaps.
--
-- Deliberately not `is_optional`. That column carries what the recipe's own
-- words said and prints as "optional" on the recipe page; salt in a bread
-- recipe is not optional, and saying so to quiet a warning would misreport
-- the recipe.

alter table public.recipe_ingredients
  add column if not exists needs_no_match boolean not null default false;

comment on column public.recipe_ingredients.needs_no_match is
  'A line that will never have a food behind it: salt, pepper, a spice. '
  'Distinct from is_optional, which is what the recipe itself said.';

-- ── The household's standing answer for a wording ───────────────────────────
--
-- Reuses `ingredient_matches` rather than adding a table beside it, because
-- "what does this wording resolve to?" is one question and this table already
-- answers it, with `unique (household_id, ingredient_string)` already keeping
-- a wording to one answer. Two tables could disagree about the same string.
--
-- `food_id` therefore has to give up its NOT NULL, which has held since the
-- first migration. The CHECK below is what replaces it, and it goes in the
-- same change rather than being left for later.
--
-- Three states, all meaningful:
--   food_id set              → this wording is that food
--   needs_no_match           → this wording needs no food at all
--   neither                  → this household looked and said it needs an
--                              ordinary match, which is how one of the
--                              seasonings Hearth ships knowing about gets
--                              turned back off. The seed list is shipped, not
--                              written into anybody's data, so disagreeing
--                              with it has to be recordable.

alter table public.ingredient_matches
  add column if not exists needs_no_match boolean not null default false;

alter table public.ingredient_matches
  alter column food_id drop not null;

alter table public.ingredient_matches
  drop constraint if exists ingredient_matches_one_answer;

alter table public.ingredient_matches
  add constraint ingredient_matches_one_answer
  check (not (food_id is not null and needs_no_match));

comment on column public.ingredient_matches.needs_no_match is
  'True when this wording resolves to nothing rather than to a food '
  '(spec §5.3). Never true at the same time as food_id.';

-- No RLS changes: both tables are already household-scoped and default-deny,
-- and the existing policies cover every column on them (CLAUDE.md rule 2).

-- Both halves of the recipe sync name their columns explicitly, so both have
-- to learn the new one. A column added to the table and not to these would
-- round-trip as false and silently unmark every seasoning on the next pull.

-- Both functions below are the original definitions verbatim, patched in
-- exactly one place each. `create or replace` replaces the whole body, so
-- anything not restated here would simply be deleted — including the
-- DELETEs that clear a recipe's old rows before the new ones go in, which
-- a hand-retyped version of this dropped.

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
