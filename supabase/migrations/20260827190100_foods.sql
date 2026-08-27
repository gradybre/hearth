-- Foods: the household library, plus the global catalogue and the personal
-- food profile (spec §4, §5.5).

-- ── Foods ───────────────────────────────────────────────────────────────────

create table public.foods (
  id uuid primary key default gen_random_uuid(),
  -- Null means a global food: world-readable, written server-side only
  -- (spec §8.2).
  household_id uuid references public.households (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  brand text,
  -- Costco / Publix / Walmart, used to group the shopping list (spec §5.7).
  store_tag text,
  barcode text,
  -- Density supplied by the source when it gives both a volume serving and
  -- its weight. Beats the generic table because it describes this food.
  grams_per_millilitre numeric check (grams_per_millilitre > 0),
  source text not null default 'manual'
    check (source in ('open_food_facts', 'usda', 'manual', 'ai_estimate')),
  -- True once the user has corrected the source's numbers; their correction
  -- wins for all future use (spec §4).
  macros_overridden boolean not null default false,
  -- Soft delete only, so historical logs keep resolving (spec §4).
  is_deleted boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index foods_household_idx on public.foods (household_id);
create index foods_barcode_idx on public.foods (barcode)
  where barcode is not null;
create index foods_name_idx on public.foods (lower(name));

create trigger foods_touch_updated_at
  before update on public.foods
  for each row execute function public.touch_updated_at();

-- One way a food can be portioned, with the macros for that portion.
-- A child table rather than a jsonb blob so a serving can be referenced and
-- queried directly (spec §5.5).
create table public.food_serving_options (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods (id) on delete cascade,
  label text not null,
  -- Stored canonically: ml for volume, g for mass, items for count (spec §4).
  amount_canonical numeric not null check (amount_canonical > 0),
  amount_kind text not null check (amount_kind in ('volume', 'mass', 'count')),
  -- The unit this serving was authored in, a display hint only.
  amount_unit text,
  kcal numeric not null default 0 check (kcal >= 0),
  protein_g numeric not null default 0 check (protein_g >= 0),
  carb_g numeric not null default 0 check (carb_g >= 0),
  fat_g numeric not null default 0 check (fat_g >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index food_serving_options_food_idx
  on public.food_serving_options (food_id, sort_order);

-- Is this food readable by the caller? Used by child-table policies.
create or replace function public.food_is_visible(p_food_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.foods f
    where f.id = p_food_id
      and (
        f.household_id is null
        or f.household_id = public.current_household_id()
      )
  )
$$;

-- Is this food writable by the caller? Global foods are never client-writable.
create or replace function public.food_is_mine(p_food_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.foods f
    where f.id = p_food_id
      and f.household_id is not null
      and f.household_id = public.current_household_id()
  )
$$;

-- ── Remembered ingredient matches ───────────────────────────────────────────

-- Correcting a match is remembered so the same string never has to be fixed
-- twice (spec §5.3).
create table public.ingredient_matches (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  ingredient_string text not null,
  food_id uuid not null references public.foods (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, ingredient_string)
);

create trigger ingredient_matches_touch_updated_at
  before update on public.ingredient_matches
  for each row execute function public.touch_updated_at();

-- ── Food profile (user-scoped, private) ─────────────────────────────────────

create table public.food_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  calories_per_meal_target numeric check (calories_per_meal_target >= 0),
  protein_target_g numeric check (protein_target_g >= 0),
  preferred_meal_types text[] not null default '{}',
  dietary_preferences text[] not null default '{}',
  dislikes text[] not null default '{}',
  allergies text[] not null default '{}',
  default_macro_targets jsonb,
  -- Derived from what the user actually logs and asks for (spec §5.8).
  learned_signals jsonb not null default '{}'::jsonb,
  -- The questionnaire is skippable and resumable (spec §5.8).
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger food_profiles_touch_updated_at
  before update on public.food_profiles
  for each row execute function public.touch_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.foods enable row level security;
alter table public.food_serving_options enable row level security;
alter table public.ingredient_matches enable row level security;
alter table public.food_profiles enable row level security;

-- Foods: your household's, plus the world-readable global catalogue.
create policy foods_select_household_or_global
  on public.foods for select
  to authenticated
  using (
    household_id is null
    or household_id = public.current_household_id()
  );

-- Writes are household-only. A client can never create or edit a global food;
-- that is a server-side job (spec §8.2).
create policy foods_insert_household
  on public.foods for insert
  to authenticated
  with check (
    household_id is not null
    and household_id = public.current_household_id()
  );

create policy foods_update_household
  on public.foods for update
  to authenticated
  using (
    household_id is not null
    and household_id = public.current_household_id()
  )
  with check (
    household_id is not null
    and household_id = public.current_household_id()
  );

-- No delete policy: foods are soft-deleted via is_deleted (spec §4).

create policy food_serving_options_select
  on public.food_serving_options for select
  to authenticated
  using (public.food_is_visible(food_id));

create policy food_serving_options_insert
  on public.food_serving_options for insert
  to authenticated
  with check (public.food_is_mine(food_id));

create policy food_serving_options_update
  on public.food_serving_options for update
  to authenticated
  using (public.food_is_mine(food_id))
  with check (public.food_is_mine(food_id));

create policy food_serving_options_delete
  on public.food_serving_options for delete
  to authenticated
  using (public.food_is_mine(food_id));

create policy ingredient_matches_all
  on public.ingredient_matches for all
  to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

-- The food profile is private to its user, not shared with the household
-- (spec §4).
create policy food_profiles_all
  on public.food_profiles for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
