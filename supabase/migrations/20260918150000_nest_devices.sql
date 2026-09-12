-- More than one thermostat (spec §11).
--
-- The first cut called `devices.list`, took `thermostats[0]` and pinned it.
-- A house with one thermostat cannot tell the difference; a house with
-- Downstairs and Upstairs silently gets whichever Google happened to return
-- first, and the other one does not exist as far as Hearth is concerned.
--
-- So the link keeps every thermostat it was given, and the screen shows them
-- all.

alter table private.nest_link
  add column if not exists devices jsonb not null default '[]'::jsonb;

comment on column private.nest_link.devices is
  'Every thermostat shared with Hearth: [{"name": "...", "label": "..."}].';

-- Google's ceiling is 100 requests an hour *per device*, so the count has to
-- be per device too.
--
-- It was a pair of columns on the link row, which was right while a household
-- had one thermostat and wrong the moment it had two: polling both would have
-- spent one household budget at twice the rate, and Hearth would have started
-- refusing its own requests at half the allowance Google actually gives.
create table if not exists private.nest_call_budget (
  -- The SDM resource name, which is what Google counts against.
  device_name text primary key,
  household_id uuid not null
    references public.households (id) on delete cascade,
  calls_this_hour integer not null default 0,
  hour_started_at timestamptz not null default now()
);

create index if not exists nest_call_budget_household_idx
  on private.nest_call_budget (household_id);

alter table private.nest_call_budget enable row level security;
revoke all on private.nest_call_budget from public;
revoke all on private.nest_call_budget from anon, authenticated;

-- Claims one request against one device's hour, or nothing if it is spent.
--
-- One statement, for the same reason `nest_link_take_call` was: two phones
-- asking together must not both read the same count and both find room.
-- Upserts, because a device Hearth has never called has no row yet and
-- refusing the first call of its life would be an odd way to begin.
create or replace function public.nest_take_device_call(
  p_household uuid,
  p_device text,
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
  insert into private.nest_call_budget (
    device_name, household_id, calls_this_hour, hour_started_at
  )
  values (p_device, p_household, 1, now())
  on conflict (device_name) do update
    set hour_started_at = case
          when private.nest_call_budget.hour_started_at
                 < now() - interval '1 hour'
            then now()
            else private.nest_call_budget.hour_started_at end,
        calls_this_hour = case
          when private.nest_call_budget.hour_started_at
                 < now() - interval '1 hour'
            then 1
            else private.nest_call_budget.calls_this_hour + 1 end
    where private.nest_call_budget.hour_started_at < now() - interval '1 hour'
       or private.nest_call_budget.calls_this_hour < p_limit
  returning calls_this_hour into taken;

  -- Null means the ceiling held: nothing was spent, and the caller serves
  -- what it already has rather than asking Google.
  return taken;
end;
$$;

-- Records every thermostat the account shared, not merely the first.
create or replace function public.nest_link_save_devices(
  p_household uuid,
  p_devices jsonb
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.nest_link
     set devices = p_devices,
         -- Kept in step so an older build, which reads these two columns and
         -- knows nothing about the list, still controls something real
         -- rather than nothing at all.
         device_name = p_devices -> 0 ->> 'name',
         device_label = p_devices -> 0 ->> 'label'
   where household_id = p_household;
$$;

revoke all on function public.nest_take_device_call(uuid, text, integer)
  from public, anon, authenticated;
revoke all on function public.nest_link_save_devices(uuid, jsonb)
  from public, anon, authenticated;
