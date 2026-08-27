-- Identity: households, profiles, and the helpers every other policy leans on.
--
-- Spec §8.2: RLS is the security boundary, not an add-on, because the client
-- ships a public key. Every table gets RLS enabled and explicit policies in
-- the same migration that creates it — a table with no policy is unreachable,
-- which is the intended failure mode.

-- ── Shared helpers ──────────────────────────────────────────────────────────

-- Keeps updated_at honest without the client having to remember.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Share codes are read aloud and typed by hand, so the alphabet omits
-- characters that get confused: I, L, O, 0, 1 (spec §5.1).
create or replace function public.generate_share_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
  i integer;
begin
  loop
    code := '';
    for i in 1..8 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    exit when not exists (
      select 1 from public.households where share_code = code
    );
  end loop;
  return code;
end;
$$;

-- ── Tables ──────────────────────────────────────────────────────────────────

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our household',
  owner_id uuid not null references auth.users (id) on delete restrict,
  share_code text not null unique default public.generate_share_code(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.households is
  'A household owns the shared library. A solo user is a household of one '
  '(spec §5.1).';

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text,
  household_id uuid references public.households (id) on delete restrict,
  -- Per-user display preference; quantities are stored canonically and
  -- converted at render time (spec §4).
  units_preference text not null default 'imperial'
    check (units_preference in ('imperial', 'metric')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_household_id_idx on public.profiles (household_id);

-- ── The household lookup every policy uses ──────────────────────────────────

-- SECURITY DEFINER on purpose: a policy on `profiles` that queried `profiles`
-- through RLS would recurse. Definer rights read the row directly.
-- search_path is pinned empty so the body cannot be hijacked by a caller's
-- search_path.
create or replace function public.current_household_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select household_id
  from public.profiles
  where id = (select auth.uid())
$$;

comment on function public.current_household_id() is
  'The calling user''s household, or null. The basis of every '
  'household-scoped policy (spec §8.2).';

-- ── Triggers ────────────────────────────────────────────────────────────────

create trigger households_touch_updated_at
  before update on public.households
  for each row execute function public.touch_updated_at();

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Solo by default: a new user gets their own household immediately, so the
-- app is usable before anyone links (spec §5.1).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_household_id uuid;
begin
  insert into public.households (owner_id)
  values (new.id)
  returning id into new_household_id;

  insert into public.profiles (id, email, household_id)
  values (new.id, new.email, new_household_id);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.households enable row level security;
alter table public.profiles enable row level security;

-- Households: you see and edit only your own.
create policy households_select_own
  on public.households for select
  to authenticated
  using (id = public.current_household_id());

create policy households_insert_own
  on public.households for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

create policy households_update_owner
  on public.households for update
  to authenticated
  using (id = public.current_household_id() and owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- No delete policy: households are never deleted from the client. Unlinking
-- is a server-side operation, not a DELETE.

-- Profiles: your own row, plus your household partner's (so their name can be
-- shown). Logs and plans are user-scoped elsewhere and stay private.
create policy profiles_select_self_or_household
  on public.profiles for select
  to authenticated
  using (
    id = (select auth.uid())
    or (
      household_id is not null
      and household_id = public.current_household_id()
    )
  );

create policy profiles_insert_self
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy profiles_update_self
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
