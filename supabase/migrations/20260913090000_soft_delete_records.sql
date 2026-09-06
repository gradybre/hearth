-- A deletion has to reach the other phone (spec §7.1, R03).
--
-- Five tables removed rows outright — meal_plan_entries, shopping_list_items,
-- collections, plan_templates, ingredient_matches — and a pull only ever sees
-- rows that exist. There is nothing in a plain select that says "this used to
-- be here", so a meal your partner deleted stayed on your phone for ever.
--
-- Recipes and foods have never had this problem, because they have always
-- soft-deleted: the row stays, `is_deleted` turns true, and the ordinary pull
-- carries it across like any other change. This gives the other five the same
-- treatment rather than inventing a second mechanism beside it — no tombstone
-- table to keep, no retention policy to get wrong, and no separate reconciling
-- pass whose cost grows with every meal ever logged.
--
-- Physical deletes remain in exactly one place, and deliberately: the two
-- membership tables (`recipe_favorites`, `recipe_collections`) are fetched
-- whole on every pass and reconciled by replacement, so absence there is
-- already read correctly as removal.

alter table public.meal_plan_entries
  add column if not exists is_deleted boolean not null default false;
alter table public.shopping_list_items
  add column if not exists is_deleted boolean not null default false;
alter table public.collections
  add column if not exists is_deleted boolean not null default false;
alter table public.plan_templates
  add column if not exists is_deleted boolean not null default false;
alter table public.ingredient_matches
  add column if not exists is_deleted boolean not null default false;

-- A deleted line must not hold its slot on the list for ever.
--
-- `(shopping_list_id, item_key)` is unique, and the upsert for this table
-- resolves on the primary key — so re-adding milk after deleting it writes a
-- *new* row, which the old constraint would refuse on behalf of a line nobody
-- can see any more. Made partial so a tombstone stops occupying the name.
alter table public.shopping_list_items
  drop constraint if exists shopping_list_items_key_unique;
create unique index if not exists shopping_list_items_key_unique
  on public.shopping_list_items (shopping_list_id, item_key)
  where not is_deleted;

-- `ingredient_matches` is deliberately left whole. Its unique constraint is
-- the upsert's conflict target, so it cannot be made partial without breaking
-- the write — and it does not need to be: an upsert resolving on that
-- constraint updates the tombstone in place, and the payload carries
-- `is_deleted` explicitly, so answering the same wording again revives the
-- row it already had rather than fighting for the name.

-- Rows that are gone stay out of the way of the queries that look for rows
-- that are not.
create index if not exists meal_plan_entries_live_idx
  on public.meal_plan_entries (meal_plan_day_id) where not is_deleted;
create index if not exists shopping_list_items_live_idx
  on public.shopping_list_items (shopping_list_id) where not is_deleted;
