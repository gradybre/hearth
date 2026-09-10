-- Reserve before the call, settle after it (spec §3, §8.1; B02).
--
-- `ai_usage_this_month` is a read, and a read is a fact about the past. Twenty
-- requests arriving in the same second all read the same pre-call total, all
-- found room under the ceiling, and all spent it — which is exactly the
-- dev-time retry loop §8 names as the real risk, and the one thing the ceiling
-- exists to stop. A read cannot be made safe by checking it harder; the
-- spending has to be visible to the next request before the model is called.
--
-- So a reservation: a conservative upper bound on what a call could cost,
-- written under the month's row lock in the same statement that checks the
-- ceiling, and given back when the call settles. The check-and-insert is one
-- function rather than two round trips for the same reason `record_ai_usage`
-- adds in SQL rather than read-then-write — the whole point of a ceiling is
-- that it is not approximate.

-- Money claimed but not yet spent.
create table if not exists public.ai_reservations (
  id uuid primary key default gen_random_uuid(),
  -- The month it counts against, matching `ai_usage.month`.
  month date not null default date_trunc('month', now())::date,
  -- Which mode asked. Not used by the arithmetic; it is what makes a stuck
  -- reservation diagnosable at all, since the request that took it is gone.
  mode text not null,
  amount_usd numeric(10, 4) not null check (amount_usd >= 0),
  created_at timestamptz not null default now(),
  -- A reservation is settled or released by the request that took it, so the
  -- only ones that reach this age belong to an isolate that died mid-call — a
  -- deploy, an eviction, a hard timeout. Without an expiry that money is
  -- committed until the month turns over, and one crash would quietly halve
  -- the budget for four weeks. The Edge Function passes five minutes:
  -- `ask` abandons its request to Claude at 90 seconds and the page fetch in
  -- front of it has its own deadline, so nothing honest is still running.
  expires_at timestamptz not null
);

create index if not exists ai_reservations_month_idx
  on public.ai_reservations (month);

alter table public.ai_reservations enable row level security;

-- Readable by any signed-in user, on the same argument as `ai_usage`: §8 asks
-- for usage to be observable, and there is nothing private in a count of API
-- calls for a two-person household.
create policy ai_reservations_read on public.ai_reservations
  for select
  to authenticated
  using (true);

-- No insert, update or delete policy, deliberately — and the grants come off
-- as well, because RLS is row-level and this is a table where the rows
-- themselves are the mechanism. A client that could insert a zero-dollar
-- reservation could not do much; a client that could DELETE from here could
-- clear the reservations holding the ceiling up, and one that could write
-- `ai_usage` could lower the month's total outright. Only the Edge Function
-- writes here, through the secret key, which bypasses RLS.
revoke insert, update, delete on public.ai_reservations from anon, authenticated;

comment on table public.ai_reservations is
  'In-flight AI spend, claimed before a call and released after it. Written '
  'only by the recipe-ai Edge Function.';

-- Claims room for one call, or refuses it.
--
-- Everything happens under one lock on the month's `ai_usage` row: the sweep,
-- the sum, the comparison and the insert. That is what makes the answer true
-- by the time the caller reads it — two requests cannot both see the same
-- headroom, because the second one waits for the first one's reservation.
--
-- `p_ceiling_usd` is the ceiling *for this mode*, not the household's: a
-- decorative icon is passed half of it (ICON_CEILING_FRACTION), so the same
-- arithmetic stops the sketches at 50% and everything else at 100%, and the
-- decorative limit is inside the lock too.
--
-- The refusal carries the numbers back rather than just `false`, because the
-- caller has to choose between two different sentences with them: a budget
-- that is spent and a picture that has yielded early are not the same fact.
create or replace function public.reserve_ai_spend(
  p_amount_usd numeric,
  p_mode text,
  p_ceiling_usd numeric,
  p_ttl_seconds integer default 300
)
returns table (
  reservation_id uuid,
  spent_usd numeric,
  reserved_usd numeric,
  allowed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month date := date_trunc('month', now())::date;
  v_spent numeric;
  v_reserved numeric;
  v_id uuid;
begin
  -- Expiry is swept here rather than on a timer: this function already holds
  -- the lock, the table is tiny, and a scheduled job is one more thing that
  -- can stop running without anybody noticing.
  delete from public.ai_reservations where expires_at <= now();

  -- The month's row is the lock everything queues on, so it has to exist
  -- before the first call of the month rather than after it.
  insert into public.ai_usage (month) values (v_month)
    on conflict (month) do nothing;
  select u.cost_usd into v_spent
    from public.ai_usage u
    where u.month = v_month
    for update;

  select coalesce(sum(r.amount_usd), 0) into v_reserved
    from public.ai_reservations r
    where r.month = v_month;

  -- Spent plus outstanding, against the same `>= 1` the function has always
  -- used — the threshold is unchanged, what it is measured over is not. A
  -- ceiling of zero or less refuses rather than meaning "unlimited": a
  -- guardrail that reads a misconfiguration as permission is not one.
  if p_ceiling_usd <= 0 or (v_spent + v_reserved) >= p_ceiling_usd then
    return query select null::uuid, v_spent, v_reserved, false;
    return;
  end if;

  insert into public.ai_reservations (month, mode, amount_usd, expires_at)
  values (
    v_month,
    p_mode,
    greatest(p_amount_usd, 0),
    now() + make_interval(secs => greatest(p_ttl_seconds, 1))
  )
  returning id into v_id;

  -- The totals as they stood *before* this reservation: the caller shows the
  -- household what the month has cost, and money that is still only claimed
  -- has not been spent.
  return query select v_id, v_spent, v_reserved, true;
end;
$$;

-- Records what a call really cost and gives its reservation back.
--
-- One function rather than two calls because the two must not be able to
-- happen apart: a settlement that recorded the spend and left the reservation
-- standing would double-count against the ceiling for five minutes, and one
-- that released without recording would lose the money altogether.
--
-- `ai_usage` first and the reservation second, matching the order
-- `reserve_ai_spend` takes them in. Two functions taking the same two locks
-- the other way round is a deadlock waiting for a busy month.
--
-- A reservation that has already expired is simply not there to delete, and
-- the usage is recorded anyway: the money was spent whatever the bookkeeping
-- says.
create or replace function public.settle_ai_spend(
  p_reservation_id uuid,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_cost_usd numeric
)
returns public.ai_usage
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ai_usage;
begin
  select * into v_row
    from public.record_ai_usage(p_input_tokens, p_output_tokens, p_cost_usd);

  delete from public.ai_reservations where id = p_reservation_id;

  return v_row;
end;
$$;

-- Gives back money that was never spent.
--
-- A 429 from Anthropic, a refused link, a photo that was too large: none of
-- them reached the model. Without this they would hold their reservation for
-- the full five minutes and make somebody else's import wait for money nobody
-- spent.
-- Answers whether there was anything to give back rather than returning void,
-- because PostgREST replies to a void function with 204 and no body — and the
-- caller parses every answer as JSON.
create or replace function public.release_ai_spend(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.ai_reservations where id = p_reservation_id;
  return found;
end;
$$;

-- Same as the two functions above them: only the Edge Function's secret key
-- may call these. A client that could reserve, settle or release could raise
-- its own ceiling by writing a negative cost or clearing the ledger.
revoke all on function public.reserve_ai_spend(numeric, text, numeric, integer)
  from public, anon, authenticated;
revoke all on function
  public.settle_ai_spend(uuid, bigint, bigint, numeric)
  from public, anon, authenticated;
revoke all on function public.release_ai_spend(uuid)
  from public, anon, authenticated;
