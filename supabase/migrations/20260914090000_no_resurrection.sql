-- A deletion is not undone by a write that predates it (spec §7.1, R03).
--
-- Every soft-deleting table has the same hole, and recipes and foods have had
-- it since they were built: `upsert_recipe` sets `is_deleted = excluded.
-- is_deleted` outright, so an edit sitting unsent in one phone's outbox
-- clears the flag on a row the other phone deleted. D3a made this reach
-- further rather than less far — all five record payloads now state
-- `is_deleted` explicitly, so every replayed upsert is a resurrection
-- attempt. One rule, seven tables.
--
-- **Why not compare against `updated_at`.** Every one of these tables has a
-- `touch_updated_at` trigger, so the stored `updated_at` is the *server's*
-- clock, while the incoming one is the writer's. Comparing across the two
-- means a phone whose clock is two seconds behind cannot undo its own
-- deletion — the Undo would look older than the tombstone it is undoing.
--
-- So the tombstone records the deleting writer's own stated time, and the
-- comparison is client clock against client clock. On one device that is
-- strictly increasing, so an Undo always wins. Across two it rests on the
-- same assumption the rest of sync already rests on: that two phones agree
-- about the time to within far less than the gap between a deletion and
-- somebody noticing it.

alter table public.recipes add column if not exists deleted_at timestamptz;
alter table public.foods add column if not exists deleted_at timestamptz;
alter table public.meal_plan_entries
  add column if not exists deleted_at timestamptz;
alter table public.shopping_list_items
  add column if not exists deleted_at timestamptz;
alter table public.collections add column if not exists deleted_at timestamptz;
alter table public.plan_templates
  add column if not exists deleted_at timestamptz;
alter table public.ingredient_matches
  add column if not exists deleted_at timestamptz;

create or replace function public.refuse_resurrection()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Going out: remember whose clock said so, and when. Taken from the
  -- writer's stated `updated_at` rather than `now()` precisely so that the
  -- comparison below stays within one clock. A caller that names a time
  -- itself is believed; nothing else has better information.
  if new.is_deleted and not old.is_deleted then
    new.deleted_at := coalesce(new.deleted_at, new.updated_at, now());
    return new;
  end if;

  -- Coming back: only by a write made *after* the deletion. An older one is
  -- an edit that was queued before the household deleted the row and has
  -- been sitting in an outbox ever since; applying it would undo a
  -- deliberate deletion with an accident.
  --
  -- The whole row is still written. Only the flag is held: a tombstone whose
  -- other columns took a stale value is invisible either way, and refusing
  -- the write outright would strand it in the outbox for ever.
  if old.is_deleted and not new.is_deleted then
    if old.deleted_at is not null and new.updated_at <= old.deleted_at then
      new.is_deleted := true;
      new.deleted_at := old.deleted_at;
    else
      new.deleted_at := null;
    end if;
  end if;

  return new;
end;
$$;

-- Named to sort before `..._touch_updated_at`: before triggers fire in name
-- order, and this one has to read the writer's `updated_at` before touch
-- replaces it with the server's.
create trigger recipes_refuse_resurrection
  before update on public.recipes
  for each row execute function public.refuse_resurrection();
create trigger foods_refuse_resurrection
  before update on public.foods
  for each row execute function public.refuse_resurrection();
create trigger meal_plan_entries_refuse_resurrection
  before update on public.meal_plan_entries
  for each row execute function public.refuse_resurrection();
create trigger shopping_list_items_refuse_resurrection
  before update on public.shopping_list_items
  for each row execute function public.refuse_resurrection();
create trigger collections_refuse_resurrection
  before update on public.collections
  for each row execute function public.refuse_resurrection();
create trigger plan_templates_refuse_resurrection
  before update on public.plan_templates
  for each row execute function public.refuse_resurrection();
create trigger ingredient_matches_refuse_resurrection
  before update on public.ingredient_matches
  for each row execute function public.refuse_resurrection();
