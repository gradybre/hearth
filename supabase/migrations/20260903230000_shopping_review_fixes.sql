-- Two corrections from a code review of the shopping list (spec §5.7).
--
-- 1. A line the recipes could only say two ways at once — 2 tbsp of butter
--    and 50 g, with no density to reconcile them — kept only its first amount
--    across a save. On reload it read as measurable and half the requirement
--    was gone. The rest now rides alongside as JSON.
--
-- 2. 20260903210000 re-keyed item_key without merging rows that the re-key
--    made collide. The unique (shopping_list_id, item_key) would have refused
--    that migration outright on any project holding "sun-dried tomatoes" and
--    "sun dried tomatoes" as separate unmatched lines in one list. It went
--    through here only because no such pair existed. The merge is added now,
--    idempotent, so a project migrated later gets the same end state.

alter table public.shopping_list_items
  add column if not exists planned_rest jsonb not null default '[]'::jsonb;

comment on column public.shopping_list_items.planned_rest is
  'Planned amounts beyond the first, as [{canonical, kind, unit}]. Non-empty '
  'only when the recipes said the same thing in units that cannot be '
  'reconciled (spec §5.7).';

do $$
declare
  v_merged int;
begin
  with ranked as (
    select id,
           row_number() over (
             partition by shopping_list_id, item_key
             order by updated_at desc, id desc
           ) as rank
    from public.shopping_list_items
  )
  delete from public.shopping_list_items i
   using ranked r
   where i.id = r.id and r.rank > 1;
  get diagnostics v_merged = row_count;

  raise notice 'shopping items: % duplicate keys merged away', v_merged;
end;
$$;
