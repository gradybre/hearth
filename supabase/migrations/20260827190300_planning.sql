-- Planner and logging. Everything here is USER-scoped, not household-scoped:
-- plans, logs, and targets are private to each person, and portions are fully
-- independent (spec §4, §5.6).

create table public.meal_plan_days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day)
);

create index meal_plan_days_user_day_idx on public.meal_plan_days (user_id, day);

create trigger meal_plan_days_touch_updated_at
  before update on public.meal_plan_days
  for each row execute function public.touch_updated_at();

create or replace function public.meal_plan_day_is_mine(p_day_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.meal_plan_days d
    where d.id = p_day_id
      and d.user_id = (select auth.uid())
  )
$$;

create table public.meal_plan_entries (
  id uuid primary key default gen_random_uuid(),
  meal_plan_day_id uuid not null
    references public.meal_plan_days (id) on delete cascade,
  meal_slot text not null
    check (meal_slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  -- Deliberately not a foreign key: an entry points at either a food or a
  -- recipe. Referential integrity is handled in the app, and history does not
  -- depend on it — a logged entry answers from macro_snapshot, so a
  -- soft-deleted target can never corrupt the past (spec §4).
  ref_type text not null check (ref_type in ('food', 'recipe')),
  ref_id uuid not null,
  servings numeric not null check (servings > 0),
  is_planned boolean not null default true,
  is_logged boolean not null default false,
  logged_at timestamptz,
  -- Macros AND portion frozen at log time. This is the mechanism behind
  -- "frozen log history": editing or deleting a recipe or food later must
  -- never rewrite what was eaten (spec §4).
  macro_snapshot jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- The non-negotiable, enforced in the schema rather than trusted to the
  -- client: a logged entry always carries its snapshot and its timestamp.
  constraint logged_entries_are_frozen check (
    (
      is_logged = false
      and macro_snapshot is null
      and logged_at is null
    )
    or (
      is_logged = true
      and macro_snapshot is not null
      and logged_at is not null
    )
  ),
  -- An entry has to be on the plan, eaten, or both — never neither.
  constraint entry_is_planned_or_logged check (is_planned or is_logged)
);

create index meal_plan_entries_day_idx
  on public.meal_plan_entries (meal_plan_day_id, meal_slot);
create index meal_plan_entries_ref_idx
  on public.meal_plan_entries (ref_type, ref_id);

create trigger meal_plan_entries_touch_updated_at
  before update on public.meal_plan_entries
  for each row execute function public.touch_updated_at();

-- Fixed daily targets, set per week and changeable week to week (spec §5.6).
create table public.macro_targets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The week starts Monday (spec §5.6); the constraint stops a stray Sunday
  -- from silently creating a second, overlapping week.
  week_start_date date not null
    check (extract(isodow from week_start_date) = 1),
  kcal numeric not null check (kcal >= 0),
  protein_g numeric not null check (protein_g >= 0),
  carb_g numeric not null check (carb_g >= 0),
  fat_g numeric not null check (fat_g >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, week_start_date)
);

create trigger macro_targets_touch_updated_at
  before update on public.macro_targets
  for each row execute function public.touch_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.meal_plan_days enable row level security;
alter table public.meal_plan_entries enable row level security;
alter table public.macro_targets enable row level security;

-- Private per user. A household partner must not see these rows at all.
create policy meal_plan_days_all
  on public.meal_plan_days for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy meal_plan_entries_all
  on public.meal_plan_entries for all
  to authenticated
  using (public.meal_plan_day_is_mine(meal_plan_day_id))
  with check (public.meal_plan_day_is_mine(meal_plan_day_id));

create policy macro_targets_all
  on public.macro_targets for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
