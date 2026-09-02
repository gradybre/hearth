-- A good week, saved so it can be had again (spec §5.6, §10 phase 5).
--
-- Private per user, exactly like the meal plans it is made of (§5.1): a
-- partner's week is their own, and a template is only a week with the dates
-- taken off.

create table public.plan_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  -- Entries as JSON rather than as a child table. They are opaque to the
  -- server — nothing queries inside them, nothing joins to them, and the
  -- alternative is a second table whose rows have no meaning apart from their
  -- parent. Each entry is {weekday, slot, ref_type, ref_id, servings}, placed
  -- by weekday rather than by date so a template outlives the week it came
  -- from.
  entries jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_templates_name_not_blank check (length(btrim(name)) > 0)
);

create index plan_templates_user_id_idx on public.plan_templates (user_id);

create trigger plan_templates_touch_updated_at
  before update on public.plan_templates
  for each row execute function public.touch_updated_at();

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.plan_templates enable row level security;

create policy plan_templates_all
  on public.plan_templates for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
