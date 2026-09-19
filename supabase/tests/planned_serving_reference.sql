-- Disposable test transaction. No household rows survive this test.
begin;
do $$
declare
  v_user uuid := '10000000-0000-0000-0000-000000002901';
  v_day uuid := '10000000-0000-0000-0000-000000002902';
  v_entry uuid := '10000000-0000-0000-0000-000000002903';
  v_food uuid := '10000000-0000-0000-0000-000000002904';
  v_selected text := '10000000-0000-0000-0000-000000002905';
  v_read text;
begin
  if not exists (select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'meal_plan_entries'
      and column_name = 'serving_option_id' and is_nullable = 'YES') then
    raise exception 'selected serving reference must be additive and nullable';
  end if;
  insert into auth.users(id, email) values(v_user, 'quantity-plan-test@example.invalid');
  -- The auth trigger provisions public.users.
  insert into public.meal_plan_days(id, user_id, day) values(v_day, v_user, '2026-09-19');
  insert into public.meal_plan_entries(id, meal_plan_day_id, meal_slot, ref_type, ref_id, servings, serving_option_id)
  values(v_entry, v_day, 'breakfast', 'food', v_food, 6, v_selected);
  -- An old client upserts an existing entry with no knowledge of the new key.
  insert into public.meal_plan_entries(id, meal_plan_day_id, meal_slot, ref_type, ref_id, servings)
  values(v_entry, v_day, 'breakfast', 'food', v_food, 6)
  on conflict(id) do update set servings = excluded.servings, serving_option_id = excluded.serving_option_id;
  select serving_option_id into v_read from public.meal_plan_entries where id = v_entry;
  if v_read is distinct from v_selected then raise exception 'old omission erased selected serving'; end if;
  insert into public.meal_plan_entries(id, meal_plan_day_id, meal_slot, ref_type, ref_id, servings, serving_option_id)
  values(v_entry, v_day, 'breakfast', 'food', v_food, 1, '')
  on conflict(id) do update set servings = excluded.servings, serving_option_id = excluded.serving_option_id;
  select serving_option_id into v_read from public.meal_plan_entries where id = v_entry;
  if nullif(v_read, '') is not null then raise exception 'explicit clear failed'; end if;
  begin
    update public.meal_plan_entries set serving_option_id = repeat('a', 129) where id = v_entry;
    raise exception 'oversize serving reference accepted';
  exception when check_violation then null;
  end;
  if exists(select 1 from pg_proc where oid = 'public.preserve_entry_serving_option()'::regprocedure and prosecdef) then
    raise exception 'serving trigger must use invoker rights';
  end if;
end $$;
rollback;
