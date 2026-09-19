-- Which serving a planned portion counts (plan R12).
--
-- `servings` has always been a count, and until now the thing it counted was
-- implicit: the food's first serving row. That is fine while every portion is
-- typed in that row's own unit, and wrong the moment a weight is typed against
-- a food whose package relationship answers in cups. Thirty ounces of a 10 oz
-- jar holding two 1 cup servings is six of *that* row — and six of whichever
-- row happens to be listed first is a different meal.
--
-- So the reference is stored beside the count. Null is the ordinary state and
-- means exactly what every existing row means; a value names one
-- food_serving_options id.
--
-- Deliberately not a foreign key, and deliberately text rather than uuid. A
-- plan entry's ref_id is not a foreign key either, for the reason stated in
-- 20260827190300_planning.sql: history must not depend on the target still
-- existing. A serving row deleted next month leaves a planned entry the client
-- reports as uncostable, which is honest, where a cascade would silently
-- rewrite the portion and a restrict would refuse the deletion.
--
-- No RLS change and none is needed: one column on a table that already has its
-- policy, and the trigger below is `security invoker`, so a caller can still
-- only write rows its own policy allows.

alter table public.meal_plan_entries
  add column if not exists serving_option_id text;

-- Named and added separately, deliberately: `add column if not exists … check
-- (…)` skips the constraint along with the column when the column is already
-- there, and reports success. A constraint added by name is either present or
-- it is not.
alter table public.meal_plan_entries
  drop constraint if exists meal_plan_entries_serving_option_id_check,
  add constraint meal_plan_entries_serving_option_id_check
    check (serving_option_id is null or length(serving_option_id) <= 128);

comment on column public.meal_plan_entries.serving_option_id is
  'Which of the food''s servings `servings` counts. Null means the food''s '
  'first serving, which is what every row written before this column meant. '
  'An empty string is the sentinel a client sends to clear the reference '
  'explicitly, and is read back as none.';

-- ── Old clients must not erase a reference they cannot see ─────────────────
--
-- A client built before this column exists sends an UPDATE that simply does
-- not mention it, and PostgreSQL fills the unmentioned column with the row''s
-- own value — which is fine for a plain UPDATE and emphatically not fine for
-- the `insert … on conflict do update set … = excluded.…` shape this app
-- pushes with, where the absent key arrives as an explicit NULL and overwrites
-- whatever was stored.
--
-- Losing it is not cosmetic: the portion left behind is a count of a row
-- nobody named, which reads back against the food''s first serving and doubles
-- or halves the meal. So a NULL arriving on an UPDATE is treated as silence
-- and the stored value is kept. A current client that means ‘none’ says so
-- with '', which is not null and therefore travels.
--
-- Inserts are untouched: a row this server has never seen has nothing to
-- preserve, and null there is the ordinary default.
create or replace function public.preserve_entry_serving_option()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.serving_option_id is null then
    new.serving_option_id := old.serving_option_id;
  end if;
  return new;
end;
$$;

comment on function public.preserve_entry_serving_option() is
  'Keeps a plan entry''s serving reference when an update says nothing about '
  'it. An older client omits the column entirely; an explicit clear is sent '
  'as the empty string, which passes through.';

drop trigger if exists meal_plan_entries_preserve_serving_option
  on public.meal_plan_entries;

-- Before the existing touch_updated_at trigger by name, which is what orders
-- same-event triggers in PostgreSQL. Neither reads the other''s column, so the
-- order is not load-bearing — it is stated only so it cannot drift silently.
create trigger meal_plan_entries_preserve_serving_option
  before update on public.meal_plan_entries
  for each row execute function public.preserve_entry_serving_option();
