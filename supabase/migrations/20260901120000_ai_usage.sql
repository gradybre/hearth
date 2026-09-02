-- The monthly AI spend ceiling (spec §3, §8.1).
--
-- §8 asks for an enforced ceiling in the Edge Function — warn at 75%, refuse
-- past 100% — and names what it is really guarding against: "a dev-time retry
-- loop, the bigger real risk than normal two-user usage". Two people importing
-- recipes will never approach it; a loop that re-asks the model will, and it
-- will do it overnight.
--
-- Anthropic's own billing limit stays the hard backstop. This is the soft one,
-- and the difference matters: a billing limit stops the spending after it has
-- happened, and this stops the call.

create table if not exists public.ai_usage (
  -- The first day of the month, so a month is a key rather than a range.
  month date primary key,
  calls integer not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  -- Accumulated from token counts using the function's own price constants.
  -- Stored rather than derived so a later price change does not silently
  -- rewrite what a past month cost.
  cost_usd numeric(10, 4) not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.ai_usage enable row level security;

-- Readable by any signed-in user: §8 asks for usage to be observable, and
-- there is nothing private in a count of API calls for a two-person
-- household.
create policy ai_usage_read on public.ai_usage
  for select
  to authenticated
  using (true);

-- No insert, update or delete policy, deliberately. Only the Edge Function
-- writes here, through the secret key, which bypasses RLS. A client that
-- could edit this table could raise its own ceiling.

comment on table public.ai_usage is
  'Monthly Claude API usage, written only by the recipe-ai Edge Function.';

-- Adds one call''s usage and returns the month''s running totals.
--
-- The addition happens in SQL rather than as read-then-write in TypeScript so
-- two calls landing together cannot lose a count — the whole point of a
-- ceiling is that it is not approximate.
create or replace function public.record_ai_usage(
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_cost_usd numeric
)
returns public.ai_usage
language sql
security definer
set search_path = public
as $$
  insert into public.ai_usage as u (month, calls, input_tokens, output_tokens, cost_usd, updated_at)
  values (date_trunc('month', now())::date, 1, p_input_tokens, p_output_tokens, p_cost_usd, now())
  on conflict (month) do update
    set calls         = u.calls + 1,
        input_tokens  = u.input_tokens + excluded.input_tokens,
        output_tokens = u.output_tokens + excluded.output_tokens,
        cost_usd      = u.cost_usd + excluded.cost_usd,
        updated_at    = now()
  returning u.*;
$$;

-- What the month has cost so far, for the check made *before* a call.
create or replace function public.ai_usage_this_month()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select cost_usd from public.ai_usage where month = date_trunc('month', now())::date),
    0
  );
$$;

revoke all on function public.record_ai_usage(bigint, bigint, numeric) from public, anon, authenticated;
revoke all on function public.ai_usage_this_month() from public, anon, authenticated;
