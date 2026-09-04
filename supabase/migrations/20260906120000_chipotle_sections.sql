-- Chipotle's menu in its own sections (spec §5.2).
--
-- The seed already stored the sheet's order on the serving options, but a
-- `Food` carries no order and had no section at all — so the builder listed
-- 29 items alphabetically, with the barbacoa between the beans and the
-- cheese. That is nobody's menu.
--
-- Sections and positions are the sheet's, in the sheet's order: tortillas,
-- rice, beans, the fajita veg, the proteins, the salsas, the toppings, the
-- greens, the sides, the dressing. `menu_order` running straight through
-- them is what puts the sections in that order too, since each is ordered by
-- where it first appears.
--
-- "Proteins" rather than "Meats", because sofritas is neither.
--
-- An update, not an insert: these 29 rows exist, keyed by the same uuid5 ids
-- the first seed used. Nothing here creates a food, so a household that
-- deleted one keeps it deleted.

update public.foods as f
set menu_group = v.menu_group,
    menu_order = v.menu_order,
    updated_at = now()
from (values
    ('0c1bd2ec-da05-5c5f-beee-fb30836326c6'::uuid, 'Tortillas', 0),
    ('964a4ef6-2773-5756-9235-e266a8cc522b'::uuid, 'Tortillas', 1),
    ('1bfeb536-ddbd-517c-84e3-29165b91937e'::uuid, 'Tortillas', 2),
    ('205ded87-5a92-5622-b304-da95443b02d8'::uuid, 'Rice', 3),
    ('29202a99-38f0-5f30-8aaf-4e046579bd37'::uuid, 'Rice', 4),
    ('53fca3ee-5529-548d-ad85-5e8102caa56b'::uuid, 'Beans', 5),
    ('8e741a71-bcc5-5e52-a8bc-d35be0ef5296'::uuid, 'Beans', 6),
    ('8e563d4f-9abb-576f-9cd1-3e93521e216e'::uuid, 'Veggies', 7),
    ('c78d1c2b-a603-5d01-bee2-bdbaa2b87ed2'::uuid, 'Proteins', 8),
    ('629def4f-1c69-57e9-80c8-fb88bc2fef1d'::uuid, 'Proteins', 9),
    ('e532f40c-9adc-5351-9431-b83adf560318'::uuid, 'Proteins', 10),
    ('535bdfba-dd87-5e34-9941-4755c61670d1'::uuid, 'Proteins', 11),
    ('82869f03-f563-582d-a0ce-32de7a7bcec7'::uuid, 'Proteins', 12),
    ('412df6c7-12e1-5120-a7e7-2689d65f9fa6'::uuid, 'Salsas', 13),
    ('5fc3825f-30ce-5998-8e85-2064b0d51a7c'::uuid, 'Salsas', 14),
    ('725aeb81-b32b-5fc5-a52e-27fec4aff79e'::uuid, 'Salsas', 15),
    ('7b89caf5-2dbc-5784-b726-8b8381f32d2d'::uuid, 'Salsas', 16),
    ('18f4a495-ba9c-5a34-8a81-4d4af45c04b8'::uuid, 'Toppings', 17),
    ('fe83ba06-288a-5580-9d4b-2352c8a76154'::uuid, 'Toppings', 18),
    ('f8fde5d8-7687-5183-ab97-9ef04996b080'::uuid, 'Toppings', 19),
    ('764149e5-c519-5d41-ac2b-67f0abb95d8a'::uuid, 'Toppings', 20),
    ('cb1c9d94-c7aa-5c70-982f-b1e8eafd0a7e'::uuid, 'Toppings', 21),
    ('60ee5c1e-0983-51ec-8ded-d0668a24d90f'::uuid, 'Toppings', 22),
    ('e9457ae6-3c7e-50fc-9321-00dad9a58275'::uuid, 'Toppings', 23),
    ('3edd2b32-9176-586a-b073-65ada21c34d6'::uuid, 'Greens', 24),
    ('2a4400e1-0cad-5fa9-ab0a-0fe651a51827'::uuid, 'Greens', 25),
    ('3e331200-8fdc-5234-8458-0a9506703c2c'::uuid, 'Sides', 26),
    ('b6d98702-afc4-59a2-b981-18ce08089c8b'::uuid, 'Sides', 27),
    ('5ea7fffc-0742-5bb6-aa5f-408897e8a935'::uuid, 'Dressing', 28)
) as v (id, menu_group, menu_order)
where f.id = v.id and f.brand = 'Chipotle';
