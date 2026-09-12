-- Where a restaurant's menu came from, and when (review N08).
--
-- One row per restaurant rather than one per import. What somebody wants to
-- know standing in front of a menu is whose numbers these are and how old they
-- are — the source, the date on the document, how many rows it had and when it
-- was last read. A history of every attempt answers a question nobody asked.
--
-- Household-scoped, deliberately. Spec §5.2 seeds chains globally and those
-- are server-owned; provenance for what a household pasted in belongs to that
-- household, and no row here ever describes a seeded catalogue.

create table if not exists public.menu_imports (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households (id) on delete cascade,

  -- The normalised brand, which is what the menu itself is grouped by. Keyed
  -- on the normalised form so "Chopt" and "chopt " cannot describe two menus.
  restaurant_key text not null,

  -- As typed, for showing.
  restaurant text not null,

  -- A URL, a file name, or whatever was said about where the numbers are from.
  source text,

  -- The date printed on the document, which is not the date it was read: a
  -- sheet published in March and pasted in September is nine months old
  -- however fresh the import is.
  document_date date,

  item_count integer not null default 0,
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (household_id, restaurant_key)
);

create trigger menu_imports_touch_updated_at
  before update on public.menu_imports
  for each row execute function public.touch_updated_at();

-- Rule 2: RLS enabled with its policy in the same change that creates the
-- table, never "policies later".
alter table public.menu_imports enable row level security;

create policy menu_imports_all
  on public.menu_imports for all
  to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());
