-- Finishing a Nest link without anybody copying a code (spec §11).
--
-- The first design had Google redirect to `https://www.google.com` — which is
-- what Google's own Device Access guide prescribes — and asked the user to
-- copy the `?code=` out of the address bar. On a Mac that is ten fiddly
-- seconds. On an iPhone it does not work at all: `google.com` is a universal
-- link claimed by the Google app, so iOS hands the redirect to that app, which
-- has nothing to do with it, and the flow dead-ends with the code never
-- visible to anybody.
--
-- So the redirect comes to a function of Hearth's own instead, on a Supabase
-- domain no app claims. That function has to answer an unauthenticated GET
-- from a browser — Google will not send a JWT — which makes the nonce below
-- the only thing standing between a stray request and somebody's thermostat.
--
-- Hence: 256 bits of randomness, stored as a hash rather than as itself (for
-- the ten minutes it is alive it *is* a bearer token, and a database dump
-- should not contain a live one), single-use by an atomic test-and-set rather
-- than a read followed by a write, and ten minutes to live — long enough for a
-- Google password prompt plus two-factor plus the device picker, short enough
-- that an abandoned attempt is not a standing invitation.

create table if not exists private.nest_link_start (
  -- sha256 of the nonce, hex. Never the nonce.
  token_hash text primary key,
  household_id uuid not null
    references public.households (id) on delete cascade,
  started_by uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_at timestamptz
);

create index if not exists nest_link_start_household_idx
  on private.nest_link_start (household_id);

alter table private.nest_link_start enable row level security;
revoke all on private.nest_link_start from public;
revoke all on private.nest_link_start from anon, authenticated;

comment on table private.nest_link_start is
  'Single-use nonces for the Nest consent redirect. Hashed, short-lived, and '
  'reachable only by the Edge Functions through the secret key.';

-- Opens an attempt.
--
-- Expired rows are swept here rather than by a scheduled job, on the same
-- reasoning `reserve_ai_spend` records: a job is one more thing that can stop
-- running without anybody noticing, and the cheapest place to tidy is the
-- place that already has the lock.
--
-- Starting a second attempt for a household drops the first. You cannot have
-- two live nonces for one house, so a half-finished attempt left open in
-- another tab cannot be completed behind you.
create or replace function public.nest_start_link(
  p_household uuid,
  p_user uuid,
  p_token_hash text,
  p_minutes integer
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  ends_at timestamptz;
begin
  delete from private.nest_link_start
   where expires_at < now()
      or household_id = p_household;

  ends_at := now() + make_interval(mins => p_minutes);

  insert into private.nest_link_start (
    token_hash, household_id, started_by, expires_at
  )
  values (p_token_hash, p_household, p_user, ends_at);

  return ends_at;
end;
$$;

-- Spends one, exactly once.
--
-- A test-and-set in a single statement, not a read then a write: two requests
-- arriving together would both read an unclaimed row and both proceed.
--
-- Zero rows means expired, already used, or never existed — and the caller
-- must not tell those apart in what it says, because the difference is only
-- ever useful to somebody guessing.
create or replace function public.nest_claim_link(p_token_hash text)
returns table (household_id uuid, started_by uuid)
language sql
security definer
set search_path = ''
as $$
  update private.nest_link_start
     set claimed_at = now()
   where token_hash = p_token_hash
     and claimed_at is null
     and expires_at > now()
  returning private.nest_link_start.household_id,
            private.nest_link_start.started_by;
$$;

revoke all on function public.nest_start_link(uuid, uuid, text, integer)
  from public, anon, authenticated;
revoke all on function public.nest_claim_link(text)
  from public, anon, authenticated;
