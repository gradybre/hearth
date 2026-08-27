-- Shopping list. Household-scoped: the list is a shared artefact even though
-- the plans it is built from are private (spec §4, §5.7).
--
-- The tables land now so the schema is complete and RLS is defined alongside
-- them; the feature itself is Phase 4.

create table public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  week_start_date date not null
    check (extract(isodow from week_start_date) = 1),
  status text not null default 'draft'
    check (status in ('draft', 'ready', 'shopped', 'archived')),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, week_start_date)
);

create trigger shopping_lists_touch_updated_at
  before update on public.shopping_lists
  for each row execute function public.touch_updated_at();

create or replace function public.shopping_list_is_mine(p_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.shopping_lists l
    where l.id = p_list_id
      and l.household_id = public.current_household_id()
  )
$$;

create table public.shopping_list_items (
  id uuid primary key default gen_random_uuid(),
  shopping_list_id uuid not null
    references public.shopping_lists (id) on delete cascade,
  -- Either a matched food or a free-typed name; a manual item ("paper
  -- towels") has no food (spec §5.7).
  food_id uuid references public.foods (id) on delete set null,
  raw_name text,
  -- v1 aggregates and displays in recipe units, stored canonically. Null when
  -- the quantity could not be reconciled and is carried in the display text.
  quantity_canonical numeric,
  quantity_kind text check (quantity_kind in ('volume', 'mass', 'count')),
  quantity_unit text,
  store_tag text,
  -- Pantry check-off crosses off the whole line; it is not an inventory
  -- (spec §5.7).
  checked boolean not null default false,
  is_manual boolean not null default false,
  source_recipe_ids uuid[] not null default '{}',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint item_has_a_name check (food_id is not null or raw_name is not null)
);

create index shopping_list_items_list_idx
  on public.shopping_list_items (shopping_list_id, sort_order);

create trigger shopping_list_items_touch_updated_at
  before update on public.shopping_list_items
  for each row execute function public.touch_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.shopping_lists enable row level security;
alter table public.shopping_list_items enable row level security;

create policy shopping_lists_all
  on public.shopping_lists for all
  to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy shopping_list_items_all
  on public.shopping_list_items for all
  to authenticated
  using (public.shopping_list_is_mine(shopping_list_id))
  with check (public.shopping_list_is_mine(shopping_list_id));
