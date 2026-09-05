"""Generates the Freddy's seed migration from their published nutrition page.

Source: https://www.freddys.com/nutrition-and-allergens, read 4 September 2026.

Unlike Chopt and Cava, this one needed no reading at all. Freddy's publishes
the table as markup, one CSS class per nutrient — `field-item__field-carbs`
holds the carbohydrate and nothing else — so every value is labelled at its
own source. There is no column to slip, which is the entire failure mode the
other two seeds were built around. The rows below are lifted from that markup
by class name; nothing was transcribed by eye or by model.

Two checks were run over the extraction, since neither is visible in the
output. Every row's macros were compared with its own printed calorie count by
Atwater (4/4/9), and none deviates by more than 30% or 60 kcal, whichever is
larger. That bound is loose on purpose and proves only what it can: it catches
a row of numbers attached to the wrong item, which is the failure this check
exists for. It is not a claim that the arithmetic is tight — fourteen rows are
more than 10% out, and "Single Steakburger (No Cheese)" is 380 against an
Atwater 324. Those are Freddy's own numbers, faithfully copied.

Second, exactly one value is absent
from the page — the cholesterol for a regular order of fries, which is
therefore null here rather than zero (spec §5.6).

Two rows are dropped, both "Make any Sandwich a Lettuce Wrap". Freddy's
publishes it as a deduction — minus 180 calories, minus 25 g of carbohydrate
— because it is a modification rather than something you order. Hearth has no
negative food and the schema refuses one, which is right: a food that gives
calories back is not a food. Anyone eating a lettuce-wrapped burger logs the
burger and is about 180 calories high. Modelling a modifier is a spec
question, not something to smuggle into a seed. The loop below drops any row with a
negative value and names it, so if Freddy's publishes another the run says so
rather than handing it to a constraint.

Five rows carry `is_zero_calorie`: the three seasoning portions and both
mustards, which Freddy's publishes as zero across all four macros with only
sodium. Without the flag `needsAttention` would call them half-filled imports,
and `foods_update_household` requires a household, so nobody could ever clear
it from the app (spec §5.5).

Freddy's publishes no serving sizes, so every row is "1 serving", the same
answer Cava's table got for the same reason. For a steakburger or a concrete
that is the honest portion anyway.

Drinks and kids' meals are absent, as they are for Chipotle, Chopt and Cava.

Ids are uuid5 under the same namespace the other menus use, so re-running
produces the same rows and the migration stays idempotent.
"""

import io
import uuid

# name, kcal, protein, carb, fat, fibre g, sodium mg, cholesterol mg
# Sections and their order are the page's own.
FREDDYS = [
    ('Chicken & Hot Dogs', [
        ('Grilled Chicken Club', 530, 35, 31, 29, 1, 1410, 100),
        ('Crispy Chicken Club', 720, 42, 44, 41, 2, 1750, 100),
        ('Spicy Chicken Sandwich', 570, 32, 44, 29, 1, 1630, 65),
        ('Chicken Tenders - Regular (3-Piece)', 420, 35, 29, 17, 2, 1330, 60),
        ('Chicken Tenders - Large (5-Piece)', 690, 58, 49, 29, 4, 2210, 95),
        ('Hot Dog', 420, 15, 35, 24, 0, 1000, 40),
        ('Chili Cheese Dog', 540, 23, 41, 31, 1, 1320, 60),
        ('Make any Sandwich a Lettuce Wrap', -180, -3, -25, -6, 1, -270, 0),
    ]),
    ('Frozen Custard Toppings', [
        ('Banana', 20, 0, 5, 0, 1, 0, 0),
        ('Brownie', 170, 2, 26, 6, 0, 125, 15),
        ('Butterfinger®', 120, 1, 19, 4.5, 0, 60, 0),
        ('Cheesecake', 60, 1, 6, 3.5, 0, 55, 10),
        ('Cherry Syrup', 60, 0, 15, 0, 0, 40, 0),
        ('Chocolate Chips', 130, 2, 19, 8, 2, 0, 0),
        ('Chocolate Syrup', 80, 1, 21, 0, 1, 10, 0),
        ('Cookie Dough', 100, 1, 16, 4.5, 0, 50, 0),
        ('Gummy Worm', 100, 2, 23, 0, 0, 10, 0),
        ('Heath® Toffee Bar', 120, 0, 14, 8, 0, 75, 10),
        ('Hot Caramel', 150, 1, 33, 1.5, 0, 115, 5),
        ('Hot Fudge', 160, 0, 25, 5, 1, 70, 0),
        ('Maraschino Cherry', 5, 0, 2, 0, 0, 0, 0),
        ('Marshmallow', 70, 0, 18, 0, 0, 15, 0),
        ('M&M® Candies', 160, 1, 21, 7, 1, 20, 5),
        ('OREO® Cookie Pieces', 80, 1, 12, 3, 1, 60, 0),
        ('Pecans', 120, 2, 2, 12, 2, 0, 0),
        ("Reese's Peanut Butter Cup", 160, 3, 18, 9, 1, 110, 0),
        ("Reese's Peanut Butter Sauce", 120, 4, 4, 11, 1, 100, 0),
        ('Sprinkles', 120, 0, 21, 4, 0, 15, 0),
        ('Strawberry', 60, 0, 15, 0, 1, 0, 0),
        ('Whipped Cream', 30, 0, 2, 2.5, 0, 10, 5),
    ]),
    ('Sides', [
        ('Applesauce', 50, 0, 13, 0, 1, 0, 0),
        ('Cheese Fries - Large', 710, 20, 78, 36, 7, 1210, 30),
        ('Cheese Fries - Regular', 470, 6, 53, 26, 4, 710, 5),
        ('Cheese Curds - Large', 1110, 52, 43, 81, 3, 2530, 130),
        ('Cheese Curds - Regular', 520, 24, 20, 38, 1, 1180, 60),
        ('Chili - Bowl (w/ Cheese)', 390, 31, 28, 19, 6, 1440, 70),
        ('Chili - Cup (w/ Cheese)', 270, 21, 18, 14, 4, 960, 50),
        ('Chili Cheese Fries - Large', 710, 20, 78, 36, 7, 1210, 30),
        ('Chili Cheese Fries - Regular', 520, 12, 58, 27, 5, 830, 15),
        ("Freddy's Fries - Kid's", 230, 3, 27, 12, 2, 150, 0),
        ("Freddy's Fries - Large", 520, 7, 62, 27, 5, 340, 0),
        ("Freddy's Fries - Regular", 400, 7, 48, 21, 4, 260, None),
        ("Freddy's Kettle Cooked Potato Chips", 200, 2, 23, 12, 2, 260, 0),
        ("Freddy's Tots - Kid's", 300, 2, 23, 23, 2, 700, 0),
        ("Freddy's Tots - Large", 680, 4, 51, 52, 4, 1570, 0),
        ("Freddy's Tots - Regular", 530, 3, 39, 40, 3, 1220, 0),
        ('Onion Rings - Regular', 380, 4, 49, 19, 3, 610, 0),
        ('Onion Rings - Large', 770, 9, 98, 38, 5, 1230, 2),
    ]),
    ('Steakburgers', [
        ('Single Steakburger (No Cheese)', 380, 24, 30, 12, 0, 870, 70),
        ('Double Steakburger (No Cheese)', 570, 43, 30, 29, 0, 1060, 135),
        ('Triple Steakburger (No Cheese)', 760, 63, 30, 41, 0, 1250, 205),
        ('Bacon & Cheese - Single Patty', 520, 33, 32, 28, 0, 1460, 100),
        ('Bacon & Cheese - Double Patty', 760, 55, 33, 44, 0, 1890, 180),
        ('Bacon & Cheese - Triple Patty', 990, 77, 34, 60, 0, 2330, 260),
        ('California Style - Single Patty', 510, 27, 35, 29, 2, 890, 90),
        ('California Style - Double Patty', 750, 49, 36, 45, 2, 1320, 170),
        ('California Style - Triple Patty', 980, 71, 37, 61, 2, 1760, 250),
        ('Cheeseburger - Single Patty', 430, 26, 31, 22, 0, 1120, 80),
        ('Cheeseburger - Double Patty', 670, 48, 32, 38, 0, 1560, 160),
        ('Cheeseburger - Triple Patty', 910, 70, 33, 54, 0, 2000, 240),
        ('Patty Melt - Single Patty', 540, 30, 39, 28, 2, 1040, 80),
        ('Patty Melt - Double Patty', 780, 52, 40, 44, 2, 1470, 160),
        ('Patty Melt - Triple Patty', 1020, 74, 41, 60, 2, 1900, 240),
        ('Jalapeño Pepper Jack - Single Patty', 530, 27, 31, 33, 1, 960, 95),
        ('Jalapeño Pepper Jack - Double Patty', 790, 49, 32, 50, 1, 1470, 180),
        ('Jalapeño Pepper Jack - Triple Patty', 1050, 72, 33, 68, 1, 1980, 270),
        ('Prime Steakburger - Single Patty', 770, 34, 33, 54, 1, 1350, 130),
        ('Prime Steakburger - Double Patty', 1000, 56, 34, 70, 1, 1780, 210),
        ('Prime Steakburger - Triple Patty', 1240, 78, 35, 86, 1, 2210, 290),
        ('Grilled Cheese Steakburger - Double Patty', 1050, 64, 52, 67, 0, 2340, 215),
        ('Veggie Burger', 510, 22, 52, 24, 10, 1180, 20),
        ('Make any Sandwich a Lettuce Wrap', -180, -3, -25, -6, 1, -270, 0),
    ]),
    ('Bowls', [
        ('Crispy Chicken Bowl (Excludes Dressing)', 610, 43, 24, 38, 4, 1520, 105),
        ('Grilled Chicken Bowl (Excludes Dressing)', 420, 37, 10, 27, 4, 1180, 105),
        ('Steakburger Bowl (Excludes Dressing)', 660, 55, 9, 45, 4, 1070, 180),
        ('Veggie Burger Bowl (Excludes Dressing)', 370, 22, 26, 20, 12, 730, 20),
    ]),
    ('Frozen Custard', [
        ('Chocolate Brownie Delight - Concrete - Mini', 700, 10, 96, 31, 3, 360, 135),
        ('Chocolate Brownie Delight - Concrete - Regular', 1040, 19, 132, 47, 4, 510, 240),
        ('Chocolate Brownie Delight - Concrete - Large', 1710, 28, 224, 77, 7, 860, 365),
        ('Chocolate Brownie Delight - Shake - Mini', 930, 17, 118, 42, 4, 470, 195),
        ('Chocolate Brownie Delight - Shake - Regular', 1280, 27, 156, 60, 5, 630, 305),
        ('Chocolate Brownie Delight - Shake - Large', 1990, 39, 251, 91, 8, 1020, 435),
        ('Chocolate Brownie Delight - Sundae - Mini', 700, 10, 96, 31, 3, 360, 135),
        ('Chocolate Brownie Delight - Sundae - Regular', 1040, 19, 132, 47, 4, 510, 240),
        ('Chocolate Brownie Delight - Sundae - Large', 1710, 28, 224, 77, 7, 860, 365),
        ('Chocolate Chip Frozen Custard Sandwich (Each)', 300, 4, 43, 14, 1, 220, 40),
        ('Cold Brew Caramel Crunch - Concrete - Mini', 790, 13, 95, 36, 0, 420, 160),
        ('Cold Brew Caramel Crunch - Concrete - Regular', 1120, 20, 129, 53, 0, 580, 260),
        ('Cold Brew Caramel Crunch - Concrete - Large', 1720, 29, 206, 79, 0, 920, 365),
        ('Cold Brew Caramel Crunch - Shake - Mini', 830, 15, 99, 38, 0, 450, 170),
        ('Cold Brew Caramel Crunch - Shake - Regular', 1180, 23, 133, 56, 0, 620, 270),
        ('Cold Brew Caramel Crunch - Shake - Large', 1810, 34, 213, 84, 0, 980, 380),
        ('Cone - Chocolate - Single Scoop', 360, 10, 42, 17, 2, 160, 105),
        ('Cone - Chocolate - Double Scoop', 690, 19, 79, 33, 3, 310, 210),
        ('Cone - Chocolate - Triple Scoop', 1020, 28, 115, 50, 5, 460, 320),
        ('Cone - Vanilla - Single Scoop', 360, 9, 39, 17, 0, 170, 100),
        ('Cone - Vanilla - Double Scoop', 690, 16, 73, 33, 0, 330, 195),
        ('Cone - Vanilla - Triple Scoop', 1020, 24, 106, 50, 0, 490, 295),
        ('CYO Concrete - Chocolate - Mini', 500, 14, 55, 25, 2, 230, 160),
        ('CYO Concrete - Chocolate - Regular', 830, 23, 91, 42, 4, 380, 265),
        ('CYO Concrete - Chocolate - Large', 1170, 32, 127, 58, 5, 530, 370),
        ('CYO Concrete - Vanilla - Mini', 500, 11, 50, 25, 0, 240, 150),
        ('CYO Concrete - Vanilla - Regular', 830, 19, 83, 42, 0, 400, 245),
        ('CYO Concrete - Vanilla - Large', 1170, 26, 117, 58, 0, 560, 345),
        ('CYO Malt - Chocolate - Mini', 630, 17, 76, 28, 2, 280, 170),
        ('CYO Malt - Chocolate - Regular', 1020, 27, 123, 46, 4, 450, 275),
        ('CYO Malt - Chocolate - Large', 1420, 38, 171, 64, 5, 640, 390),
        ('CYO Malt - Vanilla - Mini', 630, 14, 72, 28, 0, 290, 155),
        ('CYO Malt - Vanilla - Regular', 1020, 23, 115, 46, 0, 470, 260),
        ('CYO Malt - Vanilla - Large', 1420, 32, 160, 64, 0, 660, 365),
        ('CYO Shake - Chocolate - Mini', 560, 17, 59, 28, 2, 270, 170),
        ('CYO Shake - Chocolate - Regular', 910, 27, 97, 46, 4, 430, 275),
        ('CYO Shake - Chocolate - Large', 1280, 38, 136, 64, 5, 610, 390),
        ('CYO Shake - Vanilla - Mini', 560, 14, 54, 28, 0, 280, 155),
        ('CYO Shake - Vanilla - Regular', 910, 23, 89, 46, 0, 450, 260),
        ('CYO Shake - Vanilla - Large', 1280, 32, 125, 64, 0, 640, 365),
        ('CYO Sundae - Chocolate - Mini', 330, 9, 36, 17, 2, 150, 105),
        ('CYO Sundae - Chocolate - Regular', 670, 18, 73, 33, 3, 300, 210),
        ('CYO Sundae - Chocolate - Large', 1000, 27, 109, 50, 5, 450, 320),
        ('CYO Sundae - Vanilla - Mini', 330, 8, 33, 17, 0, 160, 100),
        ('CYO Sundae - Vanilla - Regular', 670, 15, 67, 33, 0, 320, 195),
        ('CYO Sundae - Vanilla - Large', 1000, 23, 100, 50, 0, 480, 295),
        ("Dirt n' Worms - Concrete - Mini", 530, 9, 69, 21, 0, 250, 105),
        ("Dirt n' Worms - Concrete - Regular", 860, 17, 102, 37, 0, 410, 205),
        ("Dirt n' Worms - Concrete - Large", 1360, 26, 168, 57, 1, 670, 300),
        ("Dirt n' Worms - Sundae - Mini", 530, 9, 69, 21, 0, 250, 105),
        ("Dirt n' Worms - Sundae - Regular", 860, 17, 102, 37, 0, 410, 205),
        ("Dirt n' Worms - Sundae - Large", 1360, 26, 168, 57, 1, 670, 300),
        ("Freddy's Frost - Lemon Cream - Mini", 450, 8, 58, 18, 0, 160, 105),
        ("Freddy's Frost - Lemon Cream - Regular", 810, 15, 99, 35, 0, 320, 205),
        ("Freddy's Frost - Lemon Cream - Large", 1210, 23, 148, 51, 0, 480, 300),
        ("Freddy's Frost - Orange Cream - Mini", 540, 8, 83, 18, 0, 160, 105),
        ("Freddy's Frost - Orange Cream - Regular", 1010, 15, 149, 35, 0, 320, 205),
        ("Freddy's Frost - Orange Cream - Large", 1500, 23, 222, 51, 0, 480, 300),
        ('OREO® Custard Cookie - Chocolate', 310, 6, 41, 14, 2, 190, 55),
        ('OREO® Custard Cookie - Vanilla', 310, 5, 39, 14, 1, 200, 50),
        ('OREO® Double Trouble - Concrete - Mini', 700, 13, 80, 33, 1, 390, 155),
        ('OREO® Double Trouble - Concrete - Regular', 1040, 20, 113, 50, 1, 550, 250),
        ('OREO® Double Trouble - Concrete - Large', 1520, 29, 169, 72, 3, 820, 350),
        ('OREO® Double Trouble - Shake - Mini', 760, 16, 84, 36, 1, 430, 165),
        ('OREO® Double Trouble - Shake - Regular', 1110, 24, 119, 54, 1, 600, 265),
        ('OREO® Double Trouble - Shake - Large', 1630, 35, 178, 78, 3, 900, 370),
        ('OREO® Double Trouble - Sundae - Mini', 540, 9, 63, 25, 1, 310, 105),
        ('OREO® Double Trouble - Sundae - Regular', 870, 17, 96, 42, 1, 470, 205),
        ('OREO® Double Trouble - Sundae - Large', 1350, 25, 152, 64, 3, 740, 300),
        ('Peanut Butter Bananza - Concrete - Mini', 560, 12, 65, 27, 2, 260, 105),
        ('Peanut Butter Bananza - Concrete - Regular', 890, 19, 98, 43, 2, 420, 205),
        ('Peanut Butter Bananza - Concrete - Large', 1420, 31, 160, 69, 4, 690, 300),
        ('Peanut Butter Bananza - Sundae - Mini', 530, 12, 58, 27, 2, 260, 105),
        ('Peanut Butter Bananza - Sundae - Regular', 860, 19, 91, 43, 2, 420, 205),
        ('Peanut Butter Bananza - Sundae - Large', 1360, 31, 146, 69, 4, 670, 300),
        ('Pint - Chocolate', 1150, 31, 125, 57, 5, 520, 365),
        ('Pint - Vanilla', 1150, 26, 115, 57, 0, 550, 340),
        ('Quart - Chocolate', 2300, 63, 250, 115, 10, 1040, 730),
        ('Quart - Vanilla', 2300, 52, 230, 115, 0, 1100, 680),
        ("Reese's Royale - Concrete - Mini", 860, 21, 76, 51, 3, 490, 155),
        ("Reese's Royale - Concrete - Regular", 1200, 29, 109, 68, 3, 650, 250),
        ("Reese's Royale - Concrete - Large", 1870, 46, 164, 109, 6, 1060, 350),
        ("Reese's Royale - Shake - Mini", 920, 24, 80, 54, 3, 530, 165),
        ("Reese's Royale - Shake - Regular", 1270, 33, 115, 72, 3, 700, 265),
        ("Reese's Royale - Shake - Large", 1980, 52, 173, 115, 6, 1140, 370),
        ("Reese's Royale - Sundae - Mini", 700, 18, 59, 43, 3, 410, 105),
        ("Reese's Royale - Sundae - Regular", 1030, 25, 92, 59, 3, 570, 205),
        ("Reese's Royale - Sundae - Large", 1700, 43, 148, 101, 6, 980, 300),
        ('Signature Turtle - Concrete - Mini', 730, 10, 91, 34, 2, 320, 110),
        ('Signature Turtle - Concrete - Regular', 1070, 18, 124, 51, 2, 480, 205),
        ('Signature Turtle - Concrete - Large', 1770, 28, 211, 84, 4, 790, 310),
        ('Signature Turtle - Shake - Mini', 960, 17, 112, 46, 2, 440, 165),
        ('Signature Turtle - Shake - Regular', 1310, 25, 146, 63, 2, 610, 270),
        ('Signature Turtle - Shake - Large', 2050, 37, 237, 98, 4, 950, 375),
        ('Signature Turtle - Sundae - Mini', 750, 10, 91, 36, 2, 320, 110),
        ('Signature Turtle - Sundae - Regular', 1080, 18, 124, 53, 2, 480, 205),
        ('Signature Turtle - Sundae - Large', 1800, 28, 212, 87, 4, 790, 310),
        ('Strawberry Dreamcake - Concrete - Mini', 860, 14, 102, 40, 1, 430, 170),
        ('Strawberry Dreamcake - Concrete - Regular', 1190, 22, 135, 57, 1, 590, 265),
        ('Strawberry Dreamcake - Concrete - Large', 1850, 32, 218, 87, 2, 930, 380),
        ('Strawberry Dreamcake - Shake - Mini', 920, 17, 106, 43, 1, 470, 175),
        ('Strawberry Dreamcake - Shake - Regular', 1270, 25, 141, 61, 1, 640, 280),
        ('Strawberry Dreamcake - Shake - Large', 1960, 37, 226, 93, 2, 1010, 395),
        ('Strawberry Dreamcake - Sundae - Mini', 690, 10, 85, 32, 1, 350, 120),
        ('Strawberry Dreamcake - Sundae - Regular', 1030, 18, 119, 49, 1, 510, 215),
        ('Strawberry Dreamcake - Sundae - Large', 1690, 28, 201, 79, 2, 850, 330),
    ]),
    ('Condiments & Sandwich Add-Ons', [
        ('Bacon', 80, 7, 1, 6, 0, 330, 20),
        ('Cheese - American', 50, 3, 1, 4.5, 0, 250, 10),
        ('Cheese - Pepperjack', 70, 3, 1, 6, 0, 320, 20),
        ('Cheese - Shredded Monterey Jack & Cheddar', 50, 3, 0, 4.5, 0, 80, 10),
        ('Cheese - Swiss', 50, 3, 1, 4, 0, 240, 10),
        ("Freddy's Smoky Fry Sauce (1 oz cup)", 130, 0, 4, 13, 0, 300, 10),
        ("Freddy's Buttermilk Ranch (1 oz cup)", 140, 0.5, 2, 15, 0, 300, 12),
        ("Freddy's Famous Fry Sauce (1 oz cup)", 120, 0, 4, 12, 0, 288, 12),
        ("Freddy's Famous Steakburger & Fry Seasoning (1g packet)", 0, 0, 0, 0, 0, 320, 0),
        ("Freddy's Famous Steakburger & Fry Seasoning (Portion per Steakburger patty)", 0, 0, 0, 0, 0, 135, 0),
        ("Freddy's Famous Steakburger & Fry Seasoning (Portion per regular fries)", 0, 0, 0, 0, 0, 310, 0),
        ("Freddy's Hickory BBQ Sauce (1 oz cup)", 35, 0, 9, 0, 0, 220, 0),
        ("Freddy's Honey Mustard (1 oz cup)", 100, 0, 7, 8, 0, 250, 0),
        ("Freddy's Jalapeño Fry Sauce (1 oz cup)", 120, 0, 4, 12, 0, 330, 4),
        ('Jalapeños - Raw', 0, 0, 1, 0, 0, 470, 0),
        ('Jalapeños - Sautéed', 35, 0, 2, 3, 0, 10, 0),
        ('Ketchup', 5, 0, 2, 0, 0, 45, 0),
        ('Ketchup (0.95 oz Cup)', 30, 0, 8, 0, 0, 250, 0),
        ('Marinara (2 oz cup)', 30, 1, 6, 0.5, 0, 260, 0),
        ('Mayonnaise', 70, 0, 0, 8, 0, 60, 5),
        ('Mayonnaise (Packet)', 80, 0, 1, 8, 0, 80, 5),
        ('Mustard', 0, 0, 0, 0, 0, 45, 0),
        ('Mustard (Packet)', 0, 0, 0, 0, 0, 65, 0),
        ('Onion - Diced', 5, 0, 1, 0, 0, 0, 0),
        ('Onion - Grilled', 30, 0, 2, 2, 0, 10, 0),
        ('Onion - Sliced', 5, 0, 1, 0, 0, 0, 0),
        ('Pickles (2 Slices)', 5, 0, 1, 0, 0, 360, 0),
        ('Relish', 10, 0, 2, 0, 0, 70, 0),
        ('Relish (Packet)', 5, 0, 2, 0, 0, 35, 0),
        ('Sauerkraut', 5, 0, 1, 0, 1, 240, 0),
        ('Thousand Island', 70, 0, 3, 7, 0, 160, 10),
        ('Tomato', 5, 0, 1, 0, 0, 0, 0),
    ]),
    ('Limited Time Offerings', [
        ('Steakburger Taco', 360, 25, 17, 21, 0, 560, 85),
        ('Peanut Butter Brownie Concrete Made with Butterfinger - Mini', 950, 14, 119, 43, 3, 520, 170),
        ('Peanut Butter Brownie Concrete Made with Butterfinger - Regular', 1280, 21, 152, 60, 3, 680, 270),
        ('Peanut Butter Brownie Concrete Made with Butterfinger - Large', 2030, 31, 251, 93, 6, 1120, 390),
    ]),
]

NAMESPACE = uuid.UUID("2f1a7c30-9b41-4d5e-8a62-c0de00000000")


def det(key):
    return str(uuid.uuid5(NAMESPACE, key))


def sql(text):
    return text.replace("'", "''")


def number(value):
    """A value, or SQL null for one the page did not print.

    Not 0. A nutrient nobody published is unknown, and a zero there is a
    claim the restaurant never made (spec §5.6).
    """
    return "null" if value is None else repr(float(value))


food_rows = []
serving_rows = []
dropped = []
order = 0
for section, items in FREDDYS:
    for name, kcal, protein, carb, fat, fibre, sodium, chol in items:
        # A deduction, not a food. Named rather than silently skipped: the
        # next person to re-run this against a changed page should be told.
        if any(v is not None and v < 0
               for v in (kcal, protein, carb, fat, fibre, sodium, chol)):
            dropped.append("%s / %s" % (section, name))
            continue

        key = "freddys/%s/%s" % (section, name)
        food_id = det("menu/food/" + key)
        serving_id = det("menu/serving/" + key)

        # A condiment a restaurant publishes as four zeros is not a
        # half-filled import, and `needsAttention` would call it one forever:
        # `foods_update_household` requires a household, so a client can never
        # clear the flag on a global food. A seed is the only place it can be
        # said (spec §5.5).
        zero = not any((kcal, protein, carb, fat))

        food_rows.append(
            "    ('%s'::uuid, '%s', 'Freddy''s', '%s', %d, %s)"
            % (food_id, sql(name), sql(section), order,
               "true" if zero else "false")
        )
        serving_rows.append(
            "    ('%s'::uuid, '%s'::uuid, '1 serving', 1.0, 'count', 'item',\n"
            "     %s, %s, %s, %s, %s, %s, %s, 0)"
            % (
                serving_id, food_id, number(kcal), number(protein),
                number(carb), number(fat), number(fibre), number(sodium),
                number(chol),
            )
        )
        order += 1

HEADER = """\
-- Freddy's Frozen Custard & Steakburgers, from their own nutrition page
-- (spec 5.2).
--
-- Source: https://www.freddys.com/nutrition-and-allergens, read 4 September
-- 2026.
--
-- This one needed no reading. Freddy's publishes the table as markup with one
-- CSS class per nutrient, so every value is labelled at its own source and
-- there is no column to slip -- which is the entire failure mode the Chopt and
-- Cava seeds were built around. The rows were lifted by class name; nothing
-- was transcribed by eye or by model.
--
-- Every row's macros were compared with its own printed calorie count by
-- Atwater (4/4/9); none deviates by more than 30%% or 60 kcal, whichever is
-- larger. That bound is loose on purpose and catches what it is for: a row of
-- numbers attached to the wrong item. It is not a claim that the arithmetic is
-- tight -- fourteen rows are more than 10%% out, which is what Freddy's
-- published.
--
-- Exactly one value is missing from the page: the cholesterol for a regular
-- order of fries, which is null here rather than zero (spec 5.6).
--
-- Two rows are absent: both copies of "Make any Sandwich a Lettuce Wrap",
-- which Freddy's publishes as a deduction -- minus 180 calories, minus 25 g of
-- carbohydrate -- because it is a modification rather than something ordered.
-- Hearth has no negative food and `food_serving_options` refuses one, which is
-- right: a food that gives calories back is not a food. A lettuce-wrapped
-- burger is logged as the burger, and reads about 180 calories high.
--
-- Five rows carry `is_zero_calorie`: the three seasoning portions and both
-- mustards, which Freddy's publishes as zero across all four macros with only
-- sodium. Without the flag `needsAttention` would call them half-filled
-- imports, and `foods_update_household` requires a household, so nobody could
-- ever clear it from the app (spec 5.5).
--
-- Freddy's publishes no serving sizes, so every row is "1 serving" -- the same
-- answer Cava's table got, for the same reason.
--
-- Drinks and kids' meals are absent, as they are for the other three menus.
--
-- Global foods: the numbers are the restaurant's, not any household's. No RLS
-- change is needed and none is made -- the existing foods policies already
-- read `household_id is null` and already refuse client writes to a row
-- belonging to no household (CLAUDE.md rule 2, spec 8.2).
--
-- Generated by supabase/migrations/generators/freddys.py. Ids are uuid5 under
-- the namespace the other menus use, so this file is reproducible and the
-- upserts below are idempotent.

insert into public.foods (
  id, household_id, name, brand, menu_group, menu_order,
  source, is_zero_calorie, is_deleted, updated_at
)
select v.id, null, v.name, v.brand, v.menu_group, v.menu_order,
       'restaurant', v.is_zero_calorie, false, now()
from (values
%s
) as v (id, name, brand, menu_group, menu_order, is_zero_calorie)
on conflict (id) do update set
  name            = excluded.name,
  brand           = excluded.brand,
  menu_group      = excluded.menu_group,
  menu_order      = excluded.menu_order,
  source          = excluded.source,
  is_zero_calorie = excluded.is_zero_calorie,
  is_deleted      = false,
  updated_at      = now();

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
path = "supabase/migrations/20260909090000_freddys.sql"
io.open(path, "w", encoding="utf-8").write(out)
print("wrote %s with %d foods" % (path, len(food_rows)))
for name in dropped:
    print("  dropped, published as a deduction: %s" % name)
