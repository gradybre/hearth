-- Close the three holes the resurrection guard shipped with (spec §7.1, R03).
--
-- Its own migration rather than an edit to 20260914090000, which is already
-- applied. `supabase migration list` compares versions, not content, so an
-- amended file would have said local and hosted agreed while the hosted
-- database carried none of this — the same silence CLAUDE.md rule 8 exists
-- for, wearing a different hat.
--
-- 1. **Nothing already deleted was protected.** The refusal needs
--    `deleted_at`, that column is only ever written on the live-to-deleted
--    transition, and a row that is already deleted never makes that
--    transition again. Every recipe and food deleted since the app was built,
--    and everything the previous migration soft-deleted, would have stayed
--    resurrectable for ever — not a startup window, a permanent gap.
--
-- 2. **A client could name the deletion time itself.** There are no column
--    grants in this schema, so `deleted_at` is writable through the REST API
--    like any other column and RLS is row-level only. A deletion stating the
--    year 9999 pins a row beyond anything the app can do about it — and worse,
--    the value could be parked on a row that is still *alive*, where no branch
--    fired and it simply persisted until the next ordinary deletion adopted
--    it. Nothing legitimate has ever sent it, so it is derived now, never
--    accepted. Spec §8.1: the client key is public, so this is a boundary.
--
-- 3. **A row can arrive already deleted.** Create a recipe offline, delete it
--    offline, then sync: the outbox supersedes the create with the delete, so
--    the server sees one INSERT with `is_deleted` already true — the one write
--    a before-update trigger never sees.

-- The triggers come off first: the backfill below is an update, and the new
-- function deliberately holds `deleted_at` steady on any update that changes
-- neither flag. That is what stops a value being parked on a live row, and it
-- would equally stop this.
drop trigger if exists recipes_refuse_resurrection on public.recipes;
drop trigger if exists foods_refuse_resurrection on public.foods;
drop trigger if exists meal_plan_entries_refuse_resurrection
  on public.meal_plan_entries;
drop trigger if exists shopping_list_items_refuse_resurrection
  on public.shopping_list_items;
drop trigger if exists collections_refuse_resurrection on public.collections;
drop trigger if exists plan_templates_refuse_resurrection
  on public.plan_templates;
drop trigger if exists ingredient_matches_refuse_resurrection
  on public.ingredient_matches;

-- Everything already deleted, given a time before the rule starts caring.
--
-- `updated_at` is the best available estimate of when it happened, and it
-- errs the safe way: it is in the past, so a genuine Undo still wins, and an
-- edit queued before it still loses.
update public.recipes set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.foods set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.meal_plan_entries set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.shopping_list_items set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.collections set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.plan_templates set deleted_at = updated_at
  where is_deleted and deleted_at is null;
update public.ingredient_matches set deleted_at = updated_at
  where is_deleted and deleted_at is null;

create or replace function public.refuse_resurrection()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Arriving already deleted. A recipe created and then deleted while
  -- offline reaches the server as one insert, because the outbox supersedes
  -- the create with the delete — and an insert is the one write a
  -- before-update trigger would never see.
  if tg_op = 'INSERT' then
    new.deleted_at := case
      when new.is_deleted then coalesce(new.updated_at, now())
      else null
    end;
    return new;
  end if;

  -- Going out: remember whose clock said so, and when. Taken from the
  -- writer's stated `updated_at` rather than `now()` precisely so that the
  -- comparison below stays within one clock.
  --
  -- Derived, never accepted. There are no column grants in this schema, so
  -- `deleted_at` is writable through the REST API like any other column, and
  -- a client that could name it could name a date in the year 9999 and pin a
  -- row deleted beyond any reach the app has. Nothing legitimate ever sends
  -- it (spec §8.1: the client key is public, so this is a boundary, not a
  -- convenience).
  if new.is_deleted and not old.is_deleted then
    new.deleted_at := coalesce(new.updated_at, now());
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
    return new;
  end if;

  -- Neither: hold what the row already had. Otherwise a client could park a
  -- `deleted_at` on a row that is still alive — no branch above would fire,
  -- the value would simply persist, and the next ordinary deletion would
  -- adopt it. A far-future one would make the row unrecoverable by anything
  -- the app can do.
  new.deleted_at := old.deleted_at;
  return new;
end;
$$;

-- Insert as well as update now, and still named to sort before
-- `..._touch_updated_at`: before triggers fire in name order, and this one
-- has to read the writer's `updated_at` before touch replaces it with the
-- server's.
create trigger recipes_refuse_resurrection
  before insert or update on public.recipes
  for each row execute function public.refuse_resurrection();
create trigger foods_refuse_resurrection
  before insert or update on public.foods
  for each row execute function public.refuse_resurrection();
create trigger meal_plan_entries_refuse_resurrection
  before insert or update on public.meal_plan_entries
  for each row execute function public.refuse_resurrection();
create trigger shopping_list_items_refuse_resurrection
  before insert or update on public.shopping_list_items
  for each row execute function public.refuse_resurrection();
create trigger collections_refuse_resurrection
  before insert or update on public.collections
  for each row execute function public.refuse_resurrection();
create trigger plan_templates_refuse_resurrection
  before insert or update on public.plan_templates
  for each row execute function public.refuse_resurrection();
create trigger ingredient_matches_refuse_resurrection
  before insert or update on public.ingredient_matches
  for each row execute function public.refuse_resurrection();
