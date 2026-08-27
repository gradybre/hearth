-- Recipes: the shared household library, its component sections, and the
-- per-user organisation on top of it (spec §4, §5.2).

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  -- Yield is required: nutrition is shown per serving by default, which is
  -- meaningless without it (spec §5.2).
  servings numeric not null check (servings > 0),
  prep_seconds integer check (prep_seconds >= 0),
  cook_seconds integer check (cook_seconds >= 0),
  cuisine text,
  tags text[] not null default '{}',
  source text not null default 'manual'
    check (source in ('manual', 'imported', 'ai_generated')),
  photo_url text,
  notes text,
  created_by uuid references auth.users (id) on delete set null,
  -- Soft delete, so past logs keep resolving (spec §4).
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recipes_household_idx on public.recipes (household_id);
create index recipes_title_idx on public.recipes (lower(title));

create trigger recipes_touch_updated_at
  before update on public.recipes
  for each row execute function public.touch_updated_at();

-- Does this recipe belong to the caller's household? Used by every child
-- table's policies, so the scoping rule lives in exactly one place.
create or replace function public.recipe_is_mine(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.recipes r
    where r.id = p_recipe_id
      and r.household_id = public.current_household_id()
  )
$$;

-- A named component group — "Sauce", "Marinade" — owning both its ingredients
-- and its steps. Simple recipes have one section named 'Main', which the UI
-- renders without a header (spec §5.2).
create table public.recipe_sections (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  name text not null default 'Main',
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index recipe_sections_recipe_idx
  on public.recipe_sections (recipe_id, sort_order);

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  section_id uuid not null references public.recipe_sections (id) on delete cascade,
  -- Null until the ingredient is matched to a food. Its absence is what makes
  -- a recipe "incomplete" rather than blocking the save (spec §5.3).
  food_id uuid references public.foods (id) on delete set null,
  -- The line as typed or imported, kept so the user can see what the parser
  -- was working from.
  raw_text text,
  name text not null,
  -- Quantity stored canonically; null for "salt to taste" (spec §4).
  quantity_canonical numeric,
  quantity_kind text check (quantity_kind in ('volume', 'mass', 'count')),
  -- The unit the line was authored in — a display hint, never the source of
  -- truth for the value.
  quantity_unit text,
  prep_note text,
  -- Excluded from macro totals and the shopping list, deliberately, and not
  -- counted as a data gap (spec §5.2).
  is_optional boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  -- A quantity needs both its number and its dimension, or neither.
  constraint quantity_is_complete check (
    (quantity_canonical is null and quantity_kind is null)
    or (quantity_canonical is not null and quantity_kind is not null)
  )
);

create index recipe_ingredients_recipe_idx
  on public.recipe_ingredients (recipe_id, sort_order);
create index recipe_ingredients_section_idx
  on public.recipe_ingredients (section_id, sort_order);
create index recipe_ingredients_food_idx
  on public.recipe_ingredients (food_id) where food_id is not null;

create table public.recipe_steps (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  section_id uuid not null references public.recipe_sections (id) on delete cascade,
  step_number integer not null check (step_number > 0),
  body text not null,
  -- Drives an embedded cook-along timer; several run at once (spec §5.2).
  timer_seconds integer check (timer_seconds > 0),
  created_at timestamptz not null default now()
);

create index recipe_steps_recipe_idx
  on public.recipe_steps (recipe_id, step_number);

-- Favouriting is personal, not household-wide (spec §4).
create table public.recipe_favorites (
  user_id uuid not null references auth.users (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

-- "Cookbooks": user-organisable groupings, shared with the household.
create table public.collections (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger collections_touch_updated_at
  before update on public.collections
  for each row execute function public.touch_updated_at();

-- A recipe can live in several collections (spec §5.2).
create table public.recipe_collections (
  collection_id uuid not null references public.collections (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (collection_id, recipe_id)
);

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.recipes enable row level security;
alter table public.recipe_sections enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.recipe_steps enable row level security;
alter table public.recipe_favorites enable row level security;
alter table public.collections enable row level security;
alter table public.recipe_collections enable row level security;

-- Recipes are household-scoped: readable and writable by either member.
-- Editing edits the shared copy, not a fork (spec §4).
create policy recipes_all_household
  on public.recipes for all
  to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy recipe_sections_all
  on public.recipe_sections for all
  to authenticated
  using (public.recipe_is_mine(recipe_id))
  with check (public.recipe_is_mine(recipe_id));

create policy recipe_ingredients_all
  on public.recipe_ingredients for all
  to authenticated
  using (public.recipe_is_mine(recipe_id))
  with check (public.recipe_is_mine(recipe_id));

create policy recipe_steps_all
  on public.recipe_steps for all
  to authenticated
  using (public.recipe_is_mine(recipe_id))
  with check (public.recipe_is_mine(recipe_id));

-- Favourites are user-scoped even though the recipe is shared: your partner
-- does not see what you starred (spec §4).
create policy recipe_favorites_all
  on public.recipe_favorites for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and public.recipe_is_mine(recipe_id)
  );

create policy collections_all
  on public.collections for all
  to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy recipe_collections_all
  on public.recipe_collections for all
  to authenticated
  using (public.recipe_is_mine(recipe_id))
  with check (
    public.recipe_is_mine(recipe_id)
    and exists (
      select 1
      from public.collections c
      where c.id = collection_id
        and c.household_id = public.current_household_id()
    )
  );
