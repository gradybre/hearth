-- Personal target decisions from a Monday onward (Phase 2 UX-052).
-- Existing macro_targets rows remain exact-week choices. No history is
-- inferred or backfilled; only a reviewed Save starts a schedule.
create table public.ongoing_macro_targets (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  week_start_date date not null check (extract(isodow from week_start_date) = 1),
  is_stopped boolean not null,
  kcal numeric,
  protein_g numeric,
  carb_g numeric,
  fat_g numeric,
  fiber_g numeric,
  sodium_mg numeric,
  cholesterol_mg numeric,
  updated_at timestamptz not null default now(),
  unique (user_id, week_start_date),
  constraint ongoing_macro_targets_values check (
    (is_stopped and kcal is null and protein_g is null and carb_g is null
      and fat_g is null and fiber_g is null and sodium_mg is null
      and cholesterol_mg is null)
    or
    (not is_stopped
      and kcal is not null and protein_g is not null
      and carb_g is not null and fat_g is not null
      and kcal >= 0 and kcal < 'Infinity'::numeric
      and protein_g >= 0 and protein_g < 'Infinity'::numeric
      and carb_g >= 0 and carb_g < 'Infinity'::numeric
      and fat_g >= 0 and fat_g < 'Infinity'::numeric
      and (fiber_g is null or (fiber_g >= 0 and fiber_g < 'Infinity'::numeric))
      and (sodium_mg is null or (sodium_mg >= 0 and sodium_mg < 'Infinity'::numeric))
      and (cholesterol_mg is null or (cholesterol_mg >= 0 and cholesterol_mg < 'Infinity'::numeric)))
  )
);

create index ongoing_macro_targets_user_updated_idx
  on public.ongoing_macro_targets (user_id, updated_at);

create trigger ongoing_macro_targets_touch_updated_at
  before insert or update on public.ongoing_macro_targets
  for each row execute function public.touch_updated_at();

alter table public.ongoing_macro_targets enable row level security;

create policy ongoing_macro_targets_select
  on public.ongoing_macro_targets for select to authenticated
  using ((select auth.uid()) = user_id);
create policy ongoing_macro_targets_insert
  on public.ongoing_macro_targets for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy ongoing_macro_targets_update
  on public.ongoing_macro_targets for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- A stop is a synchronised boundary. Deleting it would resurrect an older
-- target set on one device while another still remembers the stop.
revoke delete on public.ongoing_macro_targets from anon, authenticated;
grant select, insert, update on public.ongoing_macro_targets to authenticated;

comment on table public.ongoing_macro_targets is
  'Private effective-dated nutrition targets. Exact-week macro_targets take precedence; an explicit stop prevents older targets resuming.';
