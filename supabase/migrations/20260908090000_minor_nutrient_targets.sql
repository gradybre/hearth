-- Targets for the three minor nutrients (spec §5.6).
--
-- Nullable, and **null means "use the Daily Value"** rather than "no target".
-- That is what lets the bars work out of the box: the FDA's numbers for a
-- 2,000-calorie diet stand in until somebody sets their own, because 612 mg of
-- sodium means nothing until it sits next to 2,300.
--
-- Nullable also means every week whose targets were set before today still
-- reads, with no backfill and no invented numbers on it.
--
-- No `not null default` on purpose. A default would be a number this household
-- never chose, indistinguishable afterwards from one they did — and the
-- editor needs to know which it is to show "Daily Value" against an untouched
-- field.
--
-- No sync functions to restate: `macro_targets` is pushed and pulled as a
-- plain table upsert, not through a `upsert_*` routine, so there is no body
-- here that could silently drop a column (CLAUDE.md rule 8's trap does not
-- apply, which is worth saying rather than leaving to be rediscovered).
--
-- No RLS change. `macro_targets` is already user-scoped and default-deny
-- (spec §8.2); these columns are covered by the policies already on it.

alter table public.macro_targets
  add column if not exists fiber_g numeric check (fiber_g >= 0),
  add column if not exists sodium_mg numeric check (sodium_mg >= 0),
  add column if not exists cholesterol_mg numeric check (cholesterol_mg >= 0);

comment on column public.macro_targets.fiber_g is
  'Grams of fibre to reach in a day. Null means the Daily Value, 28 g. A '
  'floor, unlike the two below (spec §5.6).';
comment on column public.macro_targets.sodium_mg is
  'Milligrams of sodium to stay under. Null means the Daily Value, 2300 mg.';
comment on column public.macro_targets.cholesterol_mg is
  'Milligrams of cholesterol to stay under. Null means the Daily Value, '
  '300 mg.';
