"""Generates the Chopt and Cava seed migration from their published guides.

Chopt: chopt_nutrition_allergen_guide.pdf, "UPDATED SPRING 2026".
Cava:  KT5_26_AN_STND_RECAN11148_DIGITAL.pdf, "Nutrition and Allergen Guide".

Chopt's text stream serialises column-major — every name in one block, then
every serving size, then blocks of numbers — so transcribing it from the text
would be aligning six lists by eye. The pages were rendered and read as
images instead, which is how a table is meant to be read.

Ids are uuid5 under a fixed namespace, so re-running produces the same rows
and the migration stays idempotent.
"""

import io
import uuid

# name, kcal, protein, carb, fat, fibre g, sodium mg, cholesterol mg
# Portions come from the section, since each sheet states one per section.
CHOPT = [
    ("Salads", "1 salad", [
        ("Kale Caesar", 300, 15, 27, 14, 7, 685, 25),
        ("Kale Caesar with Grilled Chicken", 430, 39, 27, 16, 7, 990, 88),
        ("Santa Fe", 450, 22, 30, 30, 12, 403, 65),
        ("Southwest Steak", 445, 32, 54, 12, 15, 685, 60),
        ("The Chopt Greek", 395, 10, 33, 21, 6, 1070, 25),
        ("Sweet Apple Orchard", 410, 13, 58, 16, 11, 136, 31),
        ("Mexican Caesar", 265, 11, 25, 15, 8, 475, 30),
        ("Mexican Caesar with Grilled Chicken", 395, 36, 25, 18, 8, 780, 93),
        ("Classic Cobb", 600, 60, 17, 35, 10, 1838, 373),
        ("Crispy Chicken Ranch", 575, 44, 45, 25, 8, 915, 140),
        ("Shrimp Spring Roll", 260, 18, 16, 2, 7, 675, 135),
    ]),
    ("Wraps", "1 wrap", [
        ("Mission Hearty Grains Whole Wheat Tortilla", 290, 9, 50, 6, 5, 510, 0),
        ("Protein Wrap", 170, 15, 36, 11, 33, 640, 0),
        ("Chicken Club Wrap", 650, 52, 61, 24, 12, 1932, 88),
        ("Turkey Club Wrap", 635, 50, 59, 23, 10, 2000, 80),
        ("Turkey Pesto Wrap", 640, 43, 57, 26, 6, 1172, 84),
        ("Hummus Crunch Wrap", 735, 20, 108, 25, 17, 1501, 0),
        ("Salmon Avocado Wrap", 815, 35, 93, 33, 12, 1473, 60),
        ("Chicken Avocado Wrap", 740, 29, 94, 28, 12, 1308, 78),
    ]),
    ("Bowls", "1 bowl", [
        ("Chicken Tinga with Brown Rice", 680, 33, 77, 28, 14, 1188, 100),
        ("Chicken Tinga with Cauliflower Rice", 515, 33, 45, 25, 15, 798, 100),
        ("Mediterranean Hummus with Brown Rice", 700, 29, 72, 32, 7, 1646, 103),
        ("Mediterranean Hummus with Cauliflower Rice", 535, 29, 40, 29, 8, 1257, 103),
        ("Harvest with Brown Rice", 840, 30, 109, 32, 11, 1101, 109),
        ("Harvest with Cauliflower Rice", 675, 30, 77, 29, 12, 712, 109),
        ("Beet Harvest Bowl with Brown Rice", 740, 29, 96, 27, 10, 856, 109),
        ("Beet Harvest Bowl with Cauliflower Rice", 575, 29, 64, 24, 11, 467, 109),
        ("Salmon Avocado Bowl with Brown Rice", 625, 27, 62, 29, 8, 1168, 60),
        ("Salmon Avocado Bowl with Cauliflower Rice", 460, 27, 30, 26, 9, 778, 60),
        ("Chicken Avocado Bowl with Brown Rice", 550, 21, 62, 24, 8, 1003, 78),
        ("Chicken Avocado Bowl with Cauliflower Rice", 385, 21, 31, 21, 9, 613, 78),
    ]),
    ("Sandwiches", "1 sandwich", [
        ("Turkey Club", 620, 38, 57, 22, 7, 1676, 73),
        ("Chicken Club", 640, 40, 57, 24, 7, 1601, 81),
        ("Caprese (Vegetarian)", 665, 27, 56, 37, 5, 1149, 47),
        ("Chicken Caprese", 795, 52, 56, 40, 5, 1454, 110),
        ("Chipotle Turkey", 785, 50, 55, 41, 7, 1648, 128),
        ("Chipotle Chicken", 805, 52, 55, 42, 7, 1573, 136),
        ("Spicy Avotuna", 990, 56, 57, 60, 6, 2376, 155),
    ]),
    ("Sandwich Ingredients", "1 portion", [
        ("Orwashers Ciabatta", 260, 10, 47, 4, 4, 680, 0),
        ("Lemon Aioli", 170, 0, 2, 17, 0, 275, 16),
        ("Tuna Salad", 450, 31, 2, 34, 0, 870, 95),
        ("Bacon Cabbage Slaw", 100, 3, 5, 7, 1, 390, 10),
        ("Kale Jalapeno Slaw", 40, 1, 2, 3, 1, 69, 0),
        ("Pesto", 65, 1, 1, 7, 0, 53, 2),
        ("Spicy Pickled Peppers", 15, 0, 3, 0, 0, 460, 0),
    ]),
    ("Greens", "1 portion", [
        ("Chopt Blend", 70, 6, 13, 1.5, 6, 95, 0),
        ("Romaine", 45, 3, 8, 1, 5, 20, 0),
        ("Kale", 90, 6, 12, 0, 6, 60, 0),
        ("Arugula", 30, 6, 6, 0, 0, 60, 0),
        ("Spinach", 25, 3, 4, 0, 3, 84, 0),
        ("Cabbage & Cilantro Blend", 70, 4, 17, 0, 7, 70, 0),
    ]),
    ("Core Choppings", "1 portion", [
        ("Grape Tomatoes", 10, 1, 2, 0, 1, 0, 0),
        ("Corn", 45, 1, 10, 0, 1, 0, 0),
        ("Jalapeno Peppers", 10, 0, 2, 0, 1, 0, 0),
        ("Red Bell Peppers", 10, 0, 3, 0, 1, 1, 0),
        ("English Cucumber", 10, 0, 2, 0, 0, 0, 0),
        ("Seasonal Apples", 25, 0, 7, 0, 1, 0, 0),
        ("Edamame", 60, 6, 4, 2.5, 3, 0, 0),
        ("Carrots", 20, 0, 5, 0, 1, 35, 0),
        ("Roasted Broccoli", 70, 2, 7, 4, 3, 530, 0),
        ("Roasted Sweet Potatoes", 130, 2, 20, 5, 3, 270, 0),
        ("Simpli Olives", 90, 0, 2, 9, 2, 480, 0),
        ("Mama Lil's Spicy Peppers", 50, 1, 6, 3.5, 1, 190, 0),
        ("Pickled Red Onions", 15, 0, 3, 0, 0, 230, 0),
        ("Purple Beets", 30, 1, 7, 0, 2, 25, 0),
        ("Scallions", 5, 0, 1, 0, 0, 0, 0),
        ("Celery", 5, 0, 1, 0, 1, 35, 0),
    ]),
    ("Cheese & Dairy", "1 portion", [
        ("Goat Cheese", 115, 6, 4, 8, 0, 106, 31),
        ("Pepperjack", 250, 16, 2, 20, 0, 380, 65),
        ("Blue Cheese", 100, 6, 1, 8, 0, 320, 20),
        ("Feta", 70, 4, 1, 6, 0, 260, 25),
        ("Cotija Cheese", 100, 6, 1, 9, 0, 400, 30),
        ("Aged Parmesan", 120, 8, 4, 8, 0, 510, 25),
        ("Cage-Free Egg", 110, 9, 1, 8, 0, 90, 265),
        ("Cage-Free Egg Whites", 30, 7, 1, 0, 0, 105, 0),
    ]),
    ("Grains & Beans", "1 portion", [
        ("Brown Rice", 240, 5, 48, 2, 3, 900, 0),
        ("Cauliflower Rice", 40, 3, 7, 1, 4, 25, 0),
        ("Hummus", 150, 3, 8, 12, 2, 208, 0),
        ("Chickpeas", 40, 2, 7, 0.5, 2, 60, 0),
        ("Black Beans", 70, 5, 14, 0, 5, 0, 0),
    ]),
    ("Crunch", "1 portion", [
        ("Tortilla Chips", 110, 2, 14, 5, 2, 55, 0),
        ("Parmesan Crisps", 90, 6, 4, 5, 1, 150, 20),
        ("Roasted Almonds", 80, 3, 3, 7, 2, 0, 0),
        ("Artisan Croutons", 110, 2, 13, 5, 1, 135, 0),
        ("Dried Cranberries", 130, 0, 35, 0, 2, 0, 0),
        ("Crispy Wontons", 70, 2, 8, 4, 0, 10, 0),
        ("Pita Chips", 130, 3, 19, 5, 1, 270, 0),
        ("Crispy Shallots", 20, 0, 3, 1, 1, 0, 0),
    ]),
    ("The Goods", "1 portion", [
        ("Grilled Chicken", 130, 25, 0, 3, 0, 305, 63),
        ("Panko Fried Chicken", 190, 23, 15, 3.5, 0, 250, 75),
        ("Shrimp", 80, 15, 1, 1, 0, 610, 135),
        ("All-Natural Smoked Bacon", 125, 15, 0, 8, 0, 1100, 25),
        ("Chickpea Falafel", 140, 6, 20, 4.5, 5, 510, 0),
        ("Roasted Tofu", 60, 5, 1, 5, 0, 0, 0),
        ("Avocado Half", 80, 1, 4.5, 7.5, 3.5, 2.5, 0),
        ("Braised Chicken Tinga", 100, 15, 3, 3, 0, 310, 70),
        ("Warm Roasted Chicken Thigh", 145, 15, 1, 9, 0, 305, 78),
        ("Norwegian Salmon", 220, 21, 0, 14, 0, 470, 60),
        ("Seared Steak", 140, 19, 0, 6, 0, 410, 30),
        ("Roasted Turkey", 110, 23, 0, 1.5, 0, 380, 55),
    ]),
    ("Dressings - Classic", "30 g", [
        ("Chopt Vinaigrette", 130, 0, 1, 15, 0, 350, 0),
        ("Balsamic Vinaigrette", 140, 0, 3, 14, 0, 160, 0),
        ("White Balsamic Vinaigrette", 140, 0, 2, 14, 0, 200, 0),
        ("Buttermilk Ranch", 140, 1, 2, 14, 0, 180, 15),
        ("Creamy Caesar", 150, 1, 1, 15, 0, 210, 20),
    ]),
    ("Dressings - Creative", "30 g", [
        ("Mexican Caesar Dressing", 170, 1, 1, 18, 0, 200, 15),
        ("Sweet & Smoky Chipotle Vinaigrette", 130, 0, 4, 12, 0, 220, 0),
        ("Smoky Bacon Russian", 210, 2, 3, 11, 0, 450, 15),
        ("Chipotle Ranch", 135, 0.5, 3, 13, 0, 200, 7.5),
        ("Fiery Feta", 140, 1, 1, 15, 0, 220, 10),
        ("Creamy Sesame", 120, 0, 3, 12, 0, 320, 10),
    ]),
    ("Dressings - Light", "30 g", [
        ("Mexican Goddess", 90, 0, 2, 9, 1, 30, 0),
        ("Yogurt Dill", 20, 2, 1, 1, 0, 630, 0),
        ("Honey Dijon", 40, 1, 4, 2, 0, 210, 5),
        ("Lemon Tahini", 90, 2, 3, 8, 0, 190, 0),
        ("Miso Carrot", 70, 1, 4, 6, 0, 320, 0),
    ]),
]

# Cava's table states no serving size at all — every row is one portion as
# served, which is what "1 serving" says without inventing a weight.
CAVA = [
    ("Curated Bowls", "1 serving", [
        ("Spicy Lamb + Avocado Bowl", 800, 43, 49, 52, 17, 1670, 105),
        ("Steak + Harissa Bowl", 620, 37, 39, 35, 7, 1830, 105),
        ("Harissa Avocado Bowl", 830, 41, 62, 49, 12, 2010, 155),
        ("Chicken + Rice Bowl", 700, 40, 44, 42, 7, 1810, 165),
        ("Greek Salad Bowl", 580, 37, 19, 40, 8, 1810, 165),
        ("Falafel Crunch Bowl", 860, 24, 88, 56, 18, 2210, 15),
        ("Strawberry Steak Salad", 420, 32, 26, 22, 5, 830, 95),
        ("Salmon + Yogurt Dill", 710, 35, 49, 43, 5, 1870, 110),
        ("Salmon + Strawberry Sesame Bowl", 700, 36, 46, 43, 7, 1860, 110),
        ("Pomegranate Glazed Salmon Bowl", 1040, 36, 80, 65, 9, 2120, 105),
    ]),
    ("Curated Pitas", "1 serving", [
        ("Spicy Chicken + Avocado", 930, 48, 80, 48, 13, 2290, 155),
        ("Steak + Feta Pita", 820, 44, 68, 42, 9, 1800, 105),
        ("Greek Chicken", 720, 48, 64, 30, 8, 2230, 170),
    ]),
    ("Bases", "1 serving", [
        ("Brown Rice", 310, 7, 48, 10, 5, 770, 0),
        ("Saffron Basmati Rice", 290, 5, 54, 7, 2, 770, 0),
        ("Black Lentils", 270, 18, 37, 7, 15, 520, 0),
        ("Super Greens", 35, 3, 6, 0.5, 4, 35, 0),
        ("Arugula", 20, 2, 3, 0.5, 1, 25, 0),
        ("Baby Spinach", 20, 3, 3, 0, 2, 70, 0),
        ("Romaine", 20, 1, 4, 0, 3, 10, 0),
        ("Power Greens", 30, 2, 4, 0, 2, 35, 0),
    ]),
    ("Mains", "1 serving", [
        ("Braised Lamb", 210, 24, 2, 12, 1, 450, 65),
        ("Grilled Chicken", 250, 28, 3, 13, 1, 670, 150),
        ("Falafel", 350, 6, 24, 26, 5, 810, 0),
        ("Grilled Steak", 170, 23, 1, 9, 0, 280, 85),
        ("Harissa Honey Chicken", 260, 26, 7, 14, 2, 670, 135),
        ("Roasted Vegetables", 100, 3, 14, 4.5, 5, 600, 0),
        ("Spicy Lamb Meatballs", 300, 24, 3, 21, 1, 680, 90),
        ("Glazed Salmon", 320, 23, 5, 23, 0, 630, 90),
    ]),
    ("Toppings", "1 serving", [
        ("Shredded Romaine", 5, 0, 1, 0, 0, 0, 0),
        ("Pita Crisps", 70, 1, 6, 11, 0, 25, 0),
        ("Sumac Cabbage Slaw", 30, 1, 3, 1.5, 1, 170, 0),
        ("Tomato + Onion", 20, 0, 2, 1.5, 0, 125, 0),
        ("Persian Cucumber", 15, 0, 1, 1, 0, 110, 0),
        ("Tomato + Cucumber", 5, 0, 1, 0, 0, 0, 0),
        ("Kalamata Olives", 35, 0, 2, 3, 2, 360, 0),
        ("Fiery Broccoli", 35, 1, 2, 2.5, 1, 170, 0),
        ("Pickled Onions", 20, 0, 5, 0, 0, 0, 0),
        ("Salt-Brined Pickles", 5, 0, 0, 0, 0, 180, 0),
        ("Crumbled Feta", 35, 3, 0, 2.5, 0, 125, 10),
        ("Fire-Roasted Corn", 45, 1, 5, 2.5, 1, 105, 0),
        ("Avocado", 110, 1, 6, 10, 4, 0, 0),
    ]),
    ("Dips + Spreads", "1 serving", [
        ("Tzatziki", 30, 2, 1, 2.5, 0, 60, 10),
        ("Hummus", 50, 2, 4, 2.5, 2, 90, 0),
        ("Roasted Eggplant", 50, 0, 2, 5, 1, 160, 0),
        ("Crazy Feta", 70, 4, 1, 6, 0, 230, 15),
        ("Harissa", 70, 1, 5, 6, 1, 250, 0),
        ("Red Pepper Hummus", 40, 2, 5, 1.5, 2, 105, 0),
    ]),
    ("Dressings", "1 serving", [
        ("Balsamic Date Vinaigrette", 60, 0, 7, 4, 1, 250, 0),
        ("Yogurt Dill", 30, 2, 1, 2, 0, 190, 5),
        ("Lemon Herb Tahini", 70, 2, 4, 6, 2, 140, 0),
        ("Strawberry Sesame", 60, 1, 3, 5, 1, 130, 0),
        ("Greek Vinaigrette", 130, 0, 1, 14, 0, 230, 0),
        ("Skhug", 80, 0, 1, 9, 0, 150, 0),
        ("Hot Harissa Vinaigrette", 70, 0, 1, 7, 0, 270, 0),
        ("Garlic Dressing", 180, 0, 0, 20, 0, 90, 0),
    ]),
    ("Sides", "1 serving", [
        ("Whole Pita", 320, 13, 54, 6, 6, 700, 0),
        ("Side Quarter Pita", 80, 3, 14, 1.5, 2, 180, 0),
        ("Pita Chips", 280, 10, 41, 8, 5, 630, 0),
        ("Harissa BBQ Pita Chips", 280, 10, 43, 10, 5, 850, 0),
        ("Greyston Chocolate Chip Blondie", 140, 2, 22, 5, 0, 10, 35),
        ("Greyston Brownie", 150, 2, 17, 9, 1, 10, 45),
        ("Whisked! Apricot Honey (DMV)", 220, 3, 34, 9, 1, 150, 40),
        ("Whisked! Salted Dark Chocolate Oat Cookie", 240, 4, 31, 13, 3, 115, 35),
    ]),
]

GRAM = 1.0
NAMESPACE = uuid.UUID("2f1a7c30-9b41-4d5e-8a62-c0de00000000")


def det(key):
    return str(uuid.uuid5(NAMESPACE, key))


def sql(text):
    return text.replace("'", "''")


def portion(label):
    """The canonical amount and kind for a stated serving size."""
    if label == "30 g":
        return 30 * GRAM, "mass", "g"
    # Every other portion these sheets state is one of something served.
    return 1.0, "count", "item"


food_rows = []
serving_rows = []
for restaurant, menu in (("Chopt", CHOPT), ("Cava", CAVA)):
    order = 0
    for section, serving_label, items in menu:
        for row in items:
            name, kcal, protein, carb, fat, fibre, sodium, chol = row
            key = "%s/%s/%s" % (restaurant.lower(), section, name)
            food_id = det("menu/food/" + key)
            serving_id = det("menu/serving/" + key)
            canonical, kind, unit = portion(serving_label)

            food_rows.append(
                "    ('%s'::uuid, '%s', '%s', '%s', %d)"
                % (food_id, sql(name), restaurant, sql(section), order)
            )
            serving_rows.append(
                "    ('%s'::uuid, '%s'::uuid, '%s', %r, '%s', '%s',\n"
                "     %r, %r, %r, %r, %r, %r, %r, 0)"
                % (
                    serving_id, food_id, sql(serving_label), canonical, kind,
                    unit, float(kcal), float(protein), float(carb), float(fat),
                    float(fibre), float(sodium), float(chol),
                )
            )
            order += 1

HEADER = """\
-- Chopt and Cava, from their published guides (spec §5.2).
--
-- Sources, both supplied by Brendan:
--   * chopt_nutrition_allergen_guide.pdf — "UPDATED SPRING 2026"
--   * KT5_26_AN_STND_RECAN11148_DIGITAL.pdf — Cava "Nutrition and Allergen
--     Guide"
--
-- Chopt's text stream serialises **column-major**: every name in one block,
-- then every serving size, then blocks of numbers. Transcribing from it would
-- have been aligning six lists by eye, which is the Fajita-Vegetables-Barbacoa
-- trap from the Chipotle sheet at forty times the scale. The pages were
-- rendered to images and read as tables instead. Cava's guide is row-major and
-- was read from its text.
--
-- Sections and their order are each sheet's own, so the builder lays out a
-- menu the way the restaurant prints it (spec §5.2).
--
-- Portions: Chopt states one per section — "1 salad", "1 portion", "30g".
-- Cava's table states none at all, so every Cava row is "1 serving", which
-- says what it is without inventing a weight nobody published.
--
-- Global foods, like Chipotle's: the numbers are the restaurant's, not any
-- household's. No RLS change is needed and none is made — the existing foods
-- policies already read `household_id is null` and already refuse client
-- writes to a row belonging to no household (CLAUDE.md rule 2, spec §8.2).
--
-- Drinks and kids' menus are deliberately absent, as they are for Chipotle.
--
-- Generated. Ids are uuid5 under a fixed namespace, so this file is
-- reproducible and the upserts below are idempotent.

insert into public.foods (
  id, household_id, name, brand, menu_group, menu_order,
  source, is_deleted, updated_at
)
select v.id, null, v.name, v.brand, v.menu_group, v.menu_order,
       'restaurant', false, now()
from (values
%s
) as v (id, name, brand, menu_group, menu_order)
on conflict (id) do update set
  name       = excluded.name,
  brand      = excluded.brand,
  menu_group = excluded.menu_group,
  menu_order = excluded.menu_order,
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
path = "supabase/migrations/20260907090000_chopt_and_cava.sql"
io.open(path, "w", encoding="utf-8").write(out)
print("wrote %s with %d foods" % (path, len(food_rows)))
