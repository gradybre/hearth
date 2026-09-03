"""Generates the Chipotle seed migration from the published sheet.

Every number here is transcribed from
US-Nutrition-Facts-Paper-Menu-3-2025.pdf (Last-Modified 5 March 2025), whose
page 1 summary independently confirms the page 2/3 table for every component
that appears on both.

Ids are uuid5 under a fixed namespace, so re-running this produces the same
rows and the migration stays idempotent.
"""

import io
import uuid

OZ = 28.349523125
FLOZ = 29.5735295625

# name, amount, unit, kcal, protein, carb, fat, fibre g, sodium mg, chol mg
ROWS = [
    ("Flour Tortilla (burrito)", 1, "item", 320, 8, 50, 9, 3, 600, 0),
    ("Flour Tortilla (taco)", 1, "item", 80, 2, 13, 2.5, None, 160, 0),
    ("Crispy Corn Tortilla", 1, "item", 70, 1, 10, 3, 1, 0, 0),
    ("Cilantro-Lime Brown Rice", 4, "oz", 210, 4, 36, 6, 2, 190, 0),
    ("Cilantro-Lime White Rice", 4, "oz", 210, 4, 40, 4, 1, 350, 0),
    ("Black Beans", 4, "oz", 130, 8, 22, 1.5, 7, 210, 0),
    ("Pinto Beans", 4, "oz", 130, 8, 21, 1.5, 8, 210, 0),
    ("Fajita Vegetables", 2, "oz", 20, 1, 5, 0, 1, 150, 0),
    ("Barbacoa", 4, "oz", 170, 24, 2, 7, 1, 530, 65),
    ("Chicken", 4, "oz", 180, 32, 0, 7, 0, 310, 125),
    ("Carnitas", 4, "oz", 210, 23, 0, 12, 0, 450, 65),
    ("Steak", 4, "oz", 150, 21, 1, 6, 1, 330, 80),
    ("Sofritas", 4, "oz", 150, 8, 9, 10, 3, 560, 0),
    ("Fresh Tomato Salsa", 4, "oz", 25, 0, 4, 0, 1, 550, 0),
    ("Roasted Chili-Corn Salsa", 4, "oz", 80, 3, 16, 1.5, 3, 330, 0),
    ("Tomatillo-Green Chili Salsa", 2, "fl_oz", 15, 0, 4, 0, 0, 260, 0),
    ("Tomatillo-Red Chili Salsa", 2, "fl_oz", 30, 0, 4, 0, 1, 500, 0),
    ("Cheese", 1, "oz", 110, 6, 1, 8, 0, 190, 30),
    ("Sour Cream", 2, "oz", 110, 2, 2, 9, 0, 30, 40),
    ("Guacamole", 4, "oz", 230, 2, 8, 22, 6, 370, 0),
    ("Guacamole (large)", 8, "oz", 460, 4, 16, 44, 12, 740, 0),
    ("Queso Blanco (entree)", 2, "oz", 120, 5, 4, 9, 0, 250, 30),
    ("Queso Blanco (side)", 4, "oz", 240, 10, 7, 18, 0, 490, 60),
    ("Queso Blanco (large)", 8, "oz", 480, 20, 14, 37, None, 980, 120),
    ("Supergreens Salad Mix", 3, "oz", 15, 1, 3, 0, 2, 15, 0),
    ("Romaine Lettuce", 1, "oz", 5, 0, 1, 0, 1, 0, 0),
    ("Chips (regular)", 4, "oz", 540, 7, 73, 25, 7, 390, 0),
    ("Chips (large)", 6, "oz", 810, 11, 110, 38, 11, 590, 0),
    ("Chipotle-Honey Vinaigrette", 2, "fl_oz", 220, 1, 18, 16, 1, 850, 0),
]

KIND = {"oz": "mass", "fl_oz": "volume", "item": "count"}
FACTOR = {"oz": OZ, "fl_oz": FLOZ, "item": 1.0}
LABEL_UNIT = {"oz": "oz", "fl_oz": "fl oz", "item": "ea"}

NAMESPACE = uuid.UUID("2f1a7c30-9b41-4d5e-8a62-c0de00000000")


def det(name: str) -> str:
    return str(uuid.uuid5(NAMESPACE, name))


def num(value) -> str:
    return "null" if value is None else repr(float(value))


def sql(text: str) -> str:
    return text.replace("'", "''")


food_rows = []
serving_rows = []
for order, row in enumerate(ROWS):
    name, amount, unit, kcal, protein, carb, fat, fibre, sodium, chol = row
    food_id = det("chipotle/food/" + name)
    serving_id = det("chipotle/serving/" + name)
    label = "%g %s" % (amount, LABEL_UNIT[unit])
    canonical = round(amount * FACTOR[unit], 6)

    food_rows.append("    ('%s'::uuid, '%s', %d)" % (food_id, sql(name), order))
    serving_rows.append(
        "    ('%s'::uuid, '%s'::uuid, '%s', %r, '%s', '%s',\n"
        "     %s, %s, %s, %s, %s, %s, %s, %d)"
        % (
            serving_id,
            food_id,
            sql(label),
            canonical,
            KIND[unit],
            unit,
            num(kcal),
            num(protein),
            num(carb),
            num(fat),
            num(fibre),
            num(sodium),
            num(chol),
            order,
        )
    )

HEADER = """\
-- Chipotle's build-your-own components, from their published sheet (spec §5.2).
--
-- Source: US-Nutrition-Facts-Paper-Menu-3-2025.pdf, Last-Modified
-- Wed, 05 Mar 2025 17:52:11 GMT. Checked for a newer revision first — every
-- plausible successor URL 404s, and this is still the sheet in use. The date
-- is recorded here so a refresh has something to compare against.
--
-- The sheet self-validates: page 1's summary independently confirms every
-- number on the page 2/3 table for the components that appear on both. Its one
-- trap is a column layout that merges "Fajita Vegetables" and "Barbacoa" into a
-- single extracted line; page 1 disambiguates them, and that is the reason this
-- is reviewed data in a migration rather than something a parser reads at run
-- time.
--
-- **Global foods** (`household_id` null): the numbers are Chipotle's, not any
-- household's, and both members see them without either owning them.
--
-- No RLS change is needed, which is stated rather than assumed (rule 2). The
-- existing foods policies already read `household_id is null` and already
-- write only where `household_id = current_household_id()`, so these rows are
-- world-readable and unwritable from the client — exactly §8.2's intent for a
-- global row, satisfied by policies that already exist. `changed_foods` runs
-- with invoker rights, so they reach a device through the ordinary pull.
--
-- Drinks are deliberately absent: about forty soda and tea rows that are not
-- build-your-own components, and the zero-calorie ones are already served by
-- `is_zero_calorie`.
--
-- Generated. Ids are uuid5 under a fixed namespace, so this file is
-- reproducible and the upserts below are idempotent.

alter table public.foods
  drop constraint if exists foods_source_check;

alter table public.foods
  add constraint foods_source_check
  check (source in (
    'open_food_facts', 'usda', 'manual', 'ai_estimate', 'restaurant'
  ));

comment on column public.foods.source is
  'Where the numbers came from. ''restaurant'' means a chain''s own published '
  'sheet, and such a food is never auto-matched to a cooking recipe''s '
  'ingredient — see IngredientMatcher.matchable (spec §5.2).';

insert into public.foods (
  id, household_id, name, brand, source, is_deleted, updated_at
)
select v.id, null, v.name, 'Chipotle', 'restaurant', false, now()
from (values
%s
) as v (id, name, sort_order)
on conflict (id) do update set
  name       = excluded.name,
  brand      = excluded.brand,
  source     = excluded.source,
  is_deleted = false,
  updated_at = now();

insert into public.food_serving_options (
  id, food_id, label, amount_canonical, amount_kind, amount_unit,
  kcal, protein_g, carb_g, fat_g, fiber_g, sodium_mg, cholesterol_mg,
  sort_order
)
select * from (values
%s
) as v (
  id, food_id, label, amount_canonical, amount_kind, amount_unit,
  kcal, protein_g, carb_g, fat_g, fiber_g, sodium_mg, cholesterol_mg,
  sort_order
)
on conflict (id) do update set
  label            = excluded.label,
  amount_canonical = excluded.amount_canonical,
  amount_kind      = excluded.amount_kind,
  amount_unit      = excluded.amount_unit,
  kcal             = excluded.kcal,
  protein_g        = excluded.protein_g,
  carb_g           = excluded.carb_g,
  fat_g            = excluded.fat_g,
  fiber_g          = excluded.fiber_g,
  sodium_mg        = excluded.sodium_mg,
  cholesterol_mg   = excluded.cholesterol_mg,
  sort_order       = excluded.sort_order;
"""

out = HEADER % (",\n".join(food_rows), ",\n".join(serving_rows))
path = "supabase/migrations/20260905150000_chipotle_components.sql"
io.open(path, "w", encoding="utf-8").write(out)
print("wrote %s with %d foods" % (path, len(food_rows)))
