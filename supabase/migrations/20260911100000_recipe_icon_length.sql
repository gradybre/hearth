-- The 4 KB cap on a sketch, as a constraint that is reliably there.
--
-- `20260911090000_recipe_icon.sql` wrote the column and its cap together:
--
--   alter table public.recipes
--     add column if not exists icon_svg text
--       check (icon_svg is null or length(icon_svg) <= 4096);
--
-- Postgres skips the *whole* clause when the column already exists — the
-- check included — and reports success either way. On any database that had
-- the column, the cap silently was not there, `supabase db reset` still
-- passed, and every commit still said the migration was applied: exactly the
-- "local passes, hosted differs" shape CLAUDE.md rule 8 exists for.
--
-- That migration is already applied and is deliberately left alone, because
-- an edited applied migration never runs again. This one states the cap as a
-- constraint of its own instead — dropped before it is added, so re-running
-- it is harmless, and *named*, so `schema_guards.sql` can assert it exists
-- rather than infer it from a row that happened to be too long. A behaviour
-- test passes for the wrong reason when the constraint it relies on has
-- quietly gone.
--
-- The number matches `SketchIcon.maxMarkupLength`. A limit only the client
-- enforces is a limit the next client forgets, and this column is read on
-- every row of the recipe library.

alter table public.recipes
  drop constraint if exists recipes_icon_svg_length;

alter table public.recipes
  add constraint recipes_icon_svg_length
  check (icon_svg is null or length(icon_svg) <= 4096);

comment on constraint recipes_icon_svg_length on public.recipes is
  'A sketch is a few hundred bytes of path data; four kilobytes of it is a '
  'traced photograph. Matches SketchIcon.maxMarkupLength (spec §5.2).';
