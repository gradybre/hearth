-- Who is asking (spec §11).
--
-- This function was written into 20260917120000_nest_link.sql *after* that
-- migration had already been pushed. Supabase tracks a migration by its
-- version, not by its contents, so `supabase migration list` went on
-- reporting local and remote in agreement while the hosted database had never
-- seen this function — and `supabase db query` without `--linked` answers from
-- the local one, which made the check that should have caught it agree too.
--
-- The symptom was a thermostat that could not be linked: `nest` asks the
-- database who the caller is before stamping `linked_by`, got a 404 from
-- PostgREST, and told the user to sign in again. Nothing about that pointed
-- here.
--
-- Rule 8's real content is that a migration is not done until it is pushed.
-- The corollary this cost: an applied migration is history and is never edited
-- again. A new file is the only way to add something.
--
-- `create or replace` so a fresh local reset, which also runs the older file,
-- is unbothered by meeting it twice.

create or replace function public.current_app_user()
returns uuid
language sql
stable
as $$
  select auth.uid();
$$;

grant execute on function public.current_app_user() to authenticated;
