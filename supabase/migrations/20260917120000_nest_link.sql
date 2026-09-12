-- The household's link to its Google Nest (spec §11).
--
-- Hearth ships a publishable key by design (§8.1), so anything the client can
-- reach is public. A Google refresh token is not data about the household; it
-- is a live bearer credential for the house's heating, and the one thing in
-- this project that must never be reachable with that key.
--
-- So it does not live in `public` at all.
--
-- `ai_reservations` is the nearest precedent and is deliberately not the model
-- here. That table holds *counts*, its select policy is `using (true)`, and
-- the argument written into its migration is that there is nothing private in
-- a count of API calls. This is the opposite case: the right policy set for
-- these rows is the empty one, and `supabase/tests/schema_guards.sql` — which
-- scans `nspname = 'public'` — would correctly fail a public table with no
-- policy. The guard is right; the table is in the wrong schema. A `private`
-- schema PostgREST does not expose is the answer, with RLS on and no policies
-- as the second lock, and new guard blocks so `private` is not simply a place
-- the existing checks cannot see.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table if not exists private.nest_link (
  -- One link per household: the thermostat is a fact about the house, and a
  -- primary key is how that stops being a convention.
  household_id uuid primary key
    references public.households (id) on delete cascade,

  -- Which Device Access project the token was issued against. The Edge
  -- Function's secret is the source of truth at link time; this records what a
  -- given token actually belongs to, so rebuilding that project turns a
  -- mystery 403 into something diagnosable.
  project_id text not null,

  -- The credential. Null once revoked — see the unlink note below.
  refresh_token text,

  -- The hour's access token, cached rather than refreshed per invocation.
  -- An Edge Function isolate is per-request and may be recycled, so refreshing
  -- on every cold start is a refresh-token reuse storm, and reuse storms are
  -- one of the ways Google decides to revoke. Protected identically to the
  -- refresh token because it is in the same schema behind the same locks.
  access_token text,
  access_token_expires_at timestamptz,

  -- The thermostat, once `devices.list` has found it.
  device_name text,
  device_label text,

  -- Whose Google account this is. Not bookkeeping: when the link breaks, this
  -- is the person who has to re-consent, and the screen says so by name.
  linked_by uuid not null,
  linked_at timestamptz not null default now(),

  -- The last answer from Google, so a link that has quietly died is visible on
  -- screen as "reconnect" rather than as a spinner.
  last_ok_at timestamptz,
  last_error text,

  -- What took the credential away, which is the difference between two
  -- completely different sentences on screen: 'unlinked' is something somebody
  -- did, 'invalid_grant' is something Google did.
  revoked_at timestamptz,
  revoked_reason text,

  -- Requests made this hour, against Google's 100-per-hour device ceiling.
  -- On the server because two phones cannot coordinate a rate limit between
  -- themselves.
  calls_this_hour integer not null default 0,
  hour_started_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  -- A row either holds a credential or records that it no longer does. Both
  -- at once, or neither, is a state nothing here knows how to read.
  constraint nest_link_token_or_tombstone
    check ((revoked_at is null) = (refresh_token is not null))
);

create trigger nest_link_touch_updated_at
  before update on private.nest_link
  for each row execute function public.touch_updated_at();

-- Rule 2, with the policy set that is correct for this table: none.
--
-- RLS on and no policies is default-deny for every role that is not the
-- service key. It is belt to the schema's braces — PostgREST does not expose
-- `private`, so nothing here is addressable with the publishable key in the
-- first place — and the belt is worth wearing because the list of exposed
-- schemas is a hosted setting that lives outside this repository.
alter table private.nest_link enable row level security;
revoke all on private.nest_link from public;
revoke all on private.nest_link from anon, authenticated;

comment on table private.nest_link is
  'A household''s Google Nest credential. Reachable only through the '
  'nest_link_* functions with the service key; never through PostgREST.';

-- ── The only doors in ────────────────────────────────────────────────────────
--
-- The functions live in `public` while the table does not, and the asymmetry
-- is load-bearing: PostgREST can only call a function in an exposed schema,
-- and the Edge Function reaches Postgres through PostgREST. Execute is
-- revoked from everyone, so the only caller is the secret key.

create or replace function public.nest_link_read(p_household uuid)
returns private.nest_link
language sql
security definer
set search_path = ''
as $$
  select * from private.nest_link where household_id = p_household;
$$;

create or replace function public.nest_link_save(
  p_household uuid,
  p_project_id text,
  p_refresh_token text,
  p_linked_by uuid,
  p_device_name text,
  p_device_label text
)
returns private.nest_link
language sql
security definer
set search_path = ''
as $$
  insert into private.nest_link as l (
    household_id, project_id, refresh_token, linked_by,
    device_name, device_label, linked_at, last_ok_at,
    last_error, revoked_at, revoked_reason
  )
  values (
    p_household, p_project_id, p_refresh_token, p_linked_by,
    p_device_name, p_device_label, now(), now(),
    null, null, null
  )
  on conflict (household_id) do update set
    project_id = excluded.project_id,
    refresh_token = excluded.refresh_token,
    linked_by = excluded.linked_by,
    device_name = excluded.device_name,
    device_label = excluded.device_label,
    linked_at = excluded.linked_at,
    last_ok_at = excluded.last_ok_at,
    -- Re-linking clears the tombstone. It is the same household's link coming
    -- back, not a second row, which is what the primary key already says.
    last_error = null,
    revoked_at = null,
    revoked_reason = null,
    access_token = null,
    access_token_expires_at = null
  returning l.*;
$$;

create or replace function public.nest_link_save_access_token(
  p_household uuid,
  p_access_token text,
  p_expires_at timestamptz
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.nest_link
     set access_token = p_access_token,
         access_token_expires_at = p_expires_at
   where household_id = p_household;
$$;

create or replace function public.nest_link_pin_device(
  p_household uuid,
  p_device_name text,
  p_device_label text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.nest_link
     set device_name = p_device_name,
         device_label = p_device_label
   where household_id = p_household;
$$;

-- One statement, so two phones asking at once cannot both read the same count
-- and both find room under the ceiling — the same argument `reserve_ai_spend`
-- makes about a read being a fact about the past.
--
-- Returns the count *after* this call, so the caller knows whether it has just
-- crossed the line rather than having to ask again.
create or replace function public.nest_link_take_call(
  p_household uuid,
  p_limit integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  taken integer;
begin
  update private.nest_link
     set hour_started_at = case
           when hour_started_at < now() - interval '1 hour'
             then now() else hour_started_at end,
         calls_this_hour = case
           when hour_started_at < now() - interval '1 hour'
             then 1 else calls_this_hour + 1 end
   where household_id = p_household
     and (
       hour_started_at < now() - interval '1 hour'
       or calls_this_hour < p_limit
     )
  returning calls_this_hour into taken;

  -- Null means the ceiling held: no row was updated, so nothing was spent.
  return taken;
end;
$$;

create or replace function public.nest_link_note_result(
  p_household uuid,
  p_ok boolean,
  p_error text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.nest_link
     set last_ok_at = case when p_ok then now() else last_ok_at end,
         last_error = case when p_ok then null else p_error end
   where household_id = p_household;
$$;

-- Unlinking destroys the credential and keeps the record.
--
-- Rule 3's soft-delete exists so a deletion can travel to the other phone, and
-- an absence cannot. That argument does not reach this row: it never leaves
-- the server, both phones read it through the Edge Function, and the other
-- phone learns of an unlink on its next call because the server says so.
--
-- What does reach it is the opposite pressure. A button labelled "Disconnect"
-- that leaves a working bearer credential in the database is a lie. So the
-- secret is destroyed outright and the row survives as a tombstone — which is
-- also the only thing that can tell "Brendan disconnected it" from "Google
-- stopped accepting it", two facts that need two different sentences.
create or replace function public.nest_link_clear(
  p_household uuid,
  p_reason text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.nest_link
     set refresh_token = null,
         access_token = null,
         access_token_expires_at = null,
         revoked_at = now(),
         revoked_reason = p_reason
   where household_id = p_household;
$$;

revoke all on function public.nest_link_read(uuid) from public, anon, authenticated;
revoke all on function public.nest_link_save(uuid, text, text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.nest_link_save_access_token(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.nest_link_pin_device(uuid, text, text) from public, anon, authenticated;
revoke all on function public.nest_link_take_call(uuid, integer) from public, anon, authenticated;
revoke all on function public.nest_link_note_result(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.nest_link_clear(uuid, text) from public, anon, authenticated;

-- Who is asking.
--
-- The Edge Function needs the caller's own id to stamp `linked_by`, and gets
-- it the same way it gets the household: by asking the database with the
-- caller's JWT rather than parsing the token itself. There is no JWT-decoding
-- code anywhere in this project and this is what keeps it that way.
create or replace function public.current_app_user()
returns uuid
language sql
stable
as $$
  select auth.uid();
$$;

grant execute on function public.current_app_user() to authenticated;
