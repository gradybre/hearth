-- Joining a household by share code (spec §5.1).
--
-- SECURITY DEFINER because the joiner cannot, by definition, see the target
-- household through RLS before they belong to it. The function is the only
-- door: it takes a code, not a household id, so it cannot be used to probe or
-- join an arbitrary household.

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

    -- Weekly lists are keyed (household_id, week_start_date); a week the
    -- target already has stays behind rather than being overwritten.
    update public.shopping_lists l
      set household_id = v_target_id
      where l.household_id = v_current_id
        and not exists (
          select 1
          from public.shopping_lists existing
          where existing.household_id = v_target_id
            and existing.week_start_date = l.week_start_date
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

comment on function public.join_household(text) is
  'Join a household by share code, carrying the caller''s library with them. '
  'Returns the joined household id.';

revoke all on function public.join_household(text) from public;
grant execute on function public.join_household(text) to authenticated;

-- Deliberately NOT implemented here: unlinking, which spec §5.1 says should
-- duplicate the shared library into each person's new solo household. That is
-- a deep copy across recipes, sections, ingredients, steps, collections, and
-- foods with a full id remapping — too much to get right as a side note, and
-- shipping a half-correct version of a data-duplicating operation is worse
-- than not having it. It needs its own change.
--
-- Since 20260903120000_recipe_photos.sql that copy also has to cover storage:
-- a duplicated recipe gets a new id, and its photo lives at a path keyed by
-- the old one, so unlinking must copy the objects too or one household walks
-- away with recipes whose pictures it can no longer read.
