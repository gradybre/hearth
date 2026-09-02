-- The shopping list gets a date range and three amounts per line (spec §5.7).
--
-- The tables have been here since phase 1, complete with RLS, waiting for the
-- feature. Two things about them turned out to be wrong once Brendan
-- described how he actually shops, and both are written back into the spec in
-- this same change rather than left to diverge:
--
--   * **A week is not the unit of shopping.** The shop happens on a Friday for
--     a stretch that covers the weekend and the week after. week_start_date
--     even carried a check constraint pinning it to a Monday.
--   * **One aggregated quantity is not enough.** A line has to show its own
--     arithmetic — buy 1 lb, need 2 lb, have 1 lb — and each of those three is
--     decided by someone different: the recipes, the shopper, and the freezer.
--
-- Safe as a rename: the feature was never built, so no row has ever existed.

-- ── A range, not a week ─────────────────────────────────────────────────────

alter table public.shopping_lists
  drop constraint if exists shopping_lists_household_id_week_start_date_key;

alter table public.shopping_lists
  drop constraint if exists shopping_lists_week_start_date_check;

alter table public.shopping_lists
  rename column week_start_date to from_date;

alter table public.shopping_lists
  add column to_date date;

update public.shopping_lists set to_date = from_date + 6 where to_date is null;

alter table public.shopping_lists
  alter column to_date set not null,
  add constraint shopping_lists_range check (to_date >= from_date);

-- ── Three amounts, not one ──────────────────────────────────────────────────

alter table public.shopping_list_items
  rename column quantity_canonical to planned_canonical;
alter table public.shopping_list_items
  rename column quantity_kind to planned_kind;
alter table public.shopping_list_items
  rename column quantity_unit to planned_unit;

alter table public.shopping_list_items
  -- What was decided to buy instead, because 1.5 lb of beef is two packets.
  -- Null means "whatever the recipes said". Survives a rebuild.
  add column wanted_canonical numeric,
  add column wanted_kind text check (wanted_kind in ('volume', 'mass', 'count')),
  add column wanted_unit text,

  -- What is already in the cupboard. Belongs to this list, not to a fridge —
  -- it does not carry to the next one, because Hearth cannot see what was
  -- eaten in between and a stale "you already have this" is how something
  -- gets left off a list.
  add column on_hand_canonical numeric,
  add column on_hand_kind text check (on_hand_kind in ('volume', 'mass', 'count')),
  add column on_hand_unit text,

  -- True when a contributing recipe line had no amount at all ("salt to
  -- taste"), so the total understates what is needed and the line should say
  -- so rather than look precise.
  add column has_unquantified boolean not null default false,

  -- What duplicates are matched on: a food id where one is attached, the
  -- normalised name otherwise. A line survives a rebuild by being recognised
  -- rather than by being in the same place, which is what lets a tick, an
  -- edited amount and a hand-made order outlive a change to the plan.
  add column item_key text;

update public.shopping_list_items
  set item_key = coalesce(food_id::text, lower(trim(raw_name)))
  where item_key is null;

alter table public.shopping_list_items
  alter column item_key set not null,
  add constraint shopping_list_items_key_unique unique (shopping_list_id, item_key);

comment on column public.shopping_list_items.planned_canonical is
  'What the recipes call for. The plan owns this; a rebuild replaces it.';
comment on column public.shopping_list_items.wanted_canonical is
  'What the shopper decided to buy instead. Survives a rebuild.';
comment on column public.shopping_list_items.on_hand_canonical is
  'What is already had. Survives a rebuild, but never carries to a new list.';

-- ── The one thing that depended on the old column ───────────────────────────
--
-- `join_household` carries a household's rows across when someone joins
-- another one, and it matched shopping lists on (household_id,
-- week_start_date) — a uniqueness the range replaces. Caught by the schema
-- guards rather than by anybody running it, which is what they are for.
--
-- The rule it encodes is unchanged: a list the target household already has
-- for the same period stays behind rather than being overwritten. Only what
-- "the same period" means has moved.

create or replace function public.join_household(p_share_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target_id uuid;
  v_current_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select id into v_target_id
  from public.households
  where share_code = upper(regexp_replace(coalesce(p_share_code, ''), '\s', '', 'g'));

  if v_target_id is null then
    raise exception 'No household matches that code'
      using errcode = 'no_data_found';
  end if;

  select household_id into v_current_id
  from public.profiles
  where id = v_user_id;

  if v_current_id = v_target_id then
    -- Already a member; nothing to do, and not an error worth a red screen.
    return v_target_id;
  end if;

  -- Carry the joiner's own library across rather than stranding it in a
  -- household they have left. Spec §5.1 covers the reverse direction
  -- ("retroactive visibility" of the owner's recipes) but is silent on the
  -- joiner's existing data; leaving it behind would silently hide recipes
  -- they created, so it moves with them. FLAGGED for confirmation.
  if v_current_id is not null then
    update public.recipes
      set household_id = v_target_id
      where household_id = v_current_id;

    update public.foods
      set household_id = v_target_id
      where household_id = v_current_id;

    update public.collections
      set household_id = v_target_id
      where household_id = v_current_id;

    -- Remembered matches are keyed (household_id, ingredient_string): move
    -- only the strings the target has no opinion on yet, so an existing
    -- correction in the destination household always wins.
    update public.ingredient_matches m
      set household_id = v_target_id
      where m.household_id = v_current_id
        and not exists (
          select 1
          from public.ingredient_matches existing
          where existing.household_id = v_target_id
            and existing.ingredient_string = m.ingredient_string
        );

    -- Lists are keyed (household_id, from_date, to_date); a period the target
    -- already has a list for stays behind rather than being overwritten.
    update public.shopping_lists l
      set household_id = v_target_id
      where l.household_id = v_current_id
        and not exists (
          select 1
          from public.shopping_lists existing
          where existing.household_id = v_target_id
            and existing.from_date = l.from_date
            and existing.to_date = l.to_date
        );
  end if;

  update public.profiles
    set household_id = v_target_id
    where id = v_user_id;

  -- The old household row is deliberately left in place, even with no members.
  -- Deleting it would cascade into anything not carried across above, and
  -- silently destroying a user's data is never the right default.

  return v_target_id;
end;
$$;
