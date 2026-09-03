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
    ('0c1bd2ec-da05-5c5f-beee-fb30836326c6'::uuid, 'Flour Tortilla (burrito)', 0),
    ('964a4ef6-2773-5756-9235-e266a8cc522b'::uuid, 'Flour Tortilla (taco)', 1),
    ('1bfeb536-ddbd-517c-84e3-29165b91937e'::uuid, 'Crispy Corn Tortilla', 2),
    ('205ded87-5a92-5622-b304-da95443b02d8'::uuid, 'Cilantro-Lime Brown Rice', 3),
    ('29202a99-38f0-5f30-8aaf-4e046579bd37'::uuid, 'Cilantro-Lime White Rice', 4),
    ('53fca3ee-5529-548d-ad85-5e8102caa56b'::uuid, 'Black Beans', 5),
    ('8e741a71-bcc5-5e52-a8bc-d35be0ef5296'::uuid, 'Pinto Beans', 6),
    ('8e563d4f-9abb-576f-9cd1-3e93521e216e'::uuid, 'Fajita Vegetables', 7),
    ('c78d1c2b-a603-5d01-bee2-bdbaa2b87ed2'::uuid, 'Barbacoa', 8),
    ('629def4f-1c69-57e9-80c8-fb88bc2fef1d'::uuid, 'Chicken', 9),
    ('e532f40c-9adc-5351-9431-b83adf560318'::uuid, 'Carnitas', 10),
    ('535bdfba-dd87-5e34-9941-4755c61670d1'::uuid, 'Steak', 11),
    ('82869f03-f563-582d-a0ce-32de7a7bcec7'::uuid, 'Sofritas', 12),
    ('412df6c7-12e1-5120-a7e7-2689d65f9fa6'::uuid, 'Fresh Tomato Salsa', 13),
    ('5fc3825f-30ce-5998-8e85-2064b0d51a7c'::uuid, 'Roasted Chili-Corn Salsa', 14),
    ('725aeb81-b32b-5fc5-a52e-27fec4aff79e'::uuid, 'Tomatillo-Green Chili Salsa', 15),
    ('7b89caf5-2dbc-5784-b726-8b8381f32d2d'::uuid, 'Tomatillo-Red Chili Salsa', 16),
    ('18f4a495-ba9c-5a34-8a81-4d4af45c04b8'::uuid, 'Cheese', 17),
    ('fe83ba06-288a-5580-9d4b-2352c8a76154'::uuid, 'Sour Cream', 18),
    ('f8fde5d8-7687-5183-ab97-9ef04996b080'::uuid, 'Guacamole', 19),
    ('764149e5-c519-5d41-ac2b-67f0abb95d8a'::uuid, 'Guacamole (large)', 20),
    ('cb1c9d94-c7aa-5c70-982f-b1e8eafd0a7e'::uuid, 'Queso Blanco (entree)', 21),
    ('60ee5c1e-0983-51ec-8ded-d0668a24d90f'::uuid, 'Queso Blanco (side)', 22),
    ('e9457ae6-3c7e-50fc-9321-00dad9a58275'::uuid, 'Queso Blanco (large)', 23),
    ('3edd2b32-9176-586a-b073-65ada21c34d6'::uuid, 'Supergreens Salad Mix', 24),
    ('2a4400e1-0cad-5fa9-ab0a-0fe651a51827'::uuid, 'Romaine Lettuce', 25),
    ('3e331200-8fdc-5234-8458-0a9506703c2c'::uuid, 'Chips (regular)', 26),
    ('b6d98702-afc4-59a2-b981-18ce08089c8b'::uuid, 'Chips (large)', 27),
    ('5ea7fffc-0742-5bb6-aa5f-408897e8a935'::uuid, 'Chipotle-Honey Vinaigrette', 28)
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
    ('e257eeda-cdb1-5f92-894c-1d0be6492cc2'::uuid, '0c1bd2ec-da05-5c5f-beee-fb30836326c6'::uuid, '1 ea', 1.0, 'count', 'item',
     320.0, 8.0, 50.0, 9.0, 3.0, 600.0, 0.0, 0),
    ('45095f17-ac0e-5007-86e1-cfd34d4bcdac'::uuid, '964a4ef6-2773-5756-9235-e266a8cc522b'::uuid, '1 ea', 1.0, 'count', 'item',
     80.0, 2.0, 13.0, 2.5, null, 160.0, 0.0, 1),
    ('ac2ff943-db40-5b17-aafe-b2ce4b244ca0'::uuid, '1bfeb536-ddbd-517c-84e3-29165b91937e'::uuid, '1 ea', 1.0, 'count', 'item',
     70.0, 1.0, 10.0, 3.0, 1.0, 0.0, 0.0, 2),
    ('40e9b38b-825a-5138-867f-a0cd22bbd458'::uuid, '205ded87-5a92-5622-b304-da95443b02d8'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     210.0, 4.0, 36.0, 6.0, 2.0, 190.0, 0.0, 3),
    ('3dedb012-ab4b-54da-9786-59b563e4f6ea'::uuid, '29202a99-38f0-5f30-8aaf-4e046579bd37'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     210.0, 4.0, 40.0, 4.0, 1.0, 350.0, 0.0, 4),
    ('c15baee1-4dfe-5148-b043-7b1c60b09e58'::uuid, '53fca3ee-5529-548d-ad85-5e8102caa56b'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     130.0, 8.0, 22.0, 1.5, 7.0, 210.0, 0.0, 5),
    ('52283d42-fffe-58b4-b095-83203bad32e0'::uuid, '8e741a71-bcc5-5e52-a8bc-d35be0ef5296'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     130.0, 8.0, 21.0, 1.5, 8.0, 210.0, 0.0, 6),
    ('87526a82-4981-5b8a-b94e-590ddf417554'::uuid, '8e563d4f-9abb-576f-9cd1-3e93521e216e'::uuid, '2 oz', 56.699046, 'mass', 'oz',
     20.0, 1.0, 5.0, 0.0, 1.0, 150.0, 0.0, 7),
    ('5519428d-b3f1-5ea2-9f9f-b5dcac5a8594'::uuid, 'c78d1c2b-a603-5d01-bee2-bdbaa2b87ed2'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     170.0, 24.0, 2.0, 7.0, 1.0, 530.0, 65.0, 8),
    ('a06052ed-766d-571b-a26c-b2d63978d4ee'::uuid, '629def4f-1c69-57e9-80c8-fb88bc2fef1d'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     180.0, 32.0, 0.0, 7.0, 0.0, 310.0, 125.0, 9),
    ('708faa26-fdcb-5cee-ad85-b50e32f7f3cd'::uuid, 'e532f40c-9adc-5351-9431-b83adf560318'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     210.0, 23.0, 0.0, 12.0, 0.0, 450.0, 65.0, 10),
    ('5117b510-ece6-5e6c-948f-7b997f849fa9'::uuid, '535bdfba-dd87-5e34-9941-4755c61670d1'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     150.0, 21.0, 1.0, 6.0, 1.0, 330.0, 80.0, 11),
    ('1f4cab86-e758-5b52-85d5-bda8d4eb6ca8'::uuid, '82869f03-f563-582d-a0ce-32de7a7bcec7'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     150.0, 8.0, 9.0, 10.0, 3.0, 560.0, 0.0, 12),
    ('b2efbadb-cdd4-53c0-8fe1-f8e364adf45d'::uuid, '412df6c7-12e1-5120-a7e7-2689d65f9fa6'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     25.0, 0.0, 4.0, 0.0, 1.0, 550.0, 0.0, 13),
    ('f2a6034a-5c2e-50c5-9647-7d68480ea2b4'::uuid, '5fc3825f-30ce-5998-8e85-2064b0d51a7c'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     80.0, 3.0, 16.0, 1.5, 3.0, 330.0, 0.0, 14),
    ('3597532d-72b8-5ec7-b3ef-2566ff3a65df'::uuid, '725aeb81-b32b-5fc5-a52e-27fec4aff79e'::uuid, '2 fl oz', 59.147059, 'volume', 'fl_oz',
     15.0, 0.0, 4.0, 0.0, 0.0, 260.0, 0.0, 15),
    ('f36ee8b6-9d46-5865-97b6-0480fbea8e8a'::uuid, '7b89caf5-2dbc-5784-b726-8b8381f32d2d'::uuid, '2 fl oz', 59.147059, 'volume', 'fl_oz',
     30.0, 0.0, 4.0, 0.0, 1.0, 500.0, 0.0, 16),
    ('c88ca333-6bfa-57e8-ba0b-d53e29bc921c'::uuid, '18f4a495-ba9c-5a34-8a81-4d4af45c04b8'::uuid, '1 oz', 28.349523, 'mass', 'oz',
     110.0, 6.0, 1.0, 8.0, 0.0, 190.0, 30.0, 17),
    ('b4dd4cc1-6c16-555d-8075-96f2954aba33'::uuid, 'fe83ba06-288a-5580-9d4b-2352c8a76154'::uuid, '2 oz', 56.699046, 'mass', 'oz',
     110.0, 2.0, 2.0, 9.0, 0.0, 30.0, 40.0, 18),
    ('f5a351df-5d2f-5562-8d47-6a73a7c87320'::uuid, 'f8fde5d8-7687-5183-ab97-9ef04996b080'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     230.0, 2.0, 8.0, 22.0, 6.0, 370.0, 0.0, 19),
    ('a63283bf-1e29-5192-a1fa-d19e01600da6'::uuid, '764149e5-c519-5d41-ac2b-67f0abb95d8a'::uuid, '8 oz', 226.796185, 'mass', 'oz',
     460.0, 4.0, 16.0, 44.0, 12.0, 740.0, 0.0, 20),
    ('58470263-be90-57cc-a8af-26bc5c2176c6'::uuid, 'cb1c9d94-c7aa-5c70-982f-b1e8eafd0a7e'::uuid, '2 oz', 56.699046, 'mass', 'oz',
     120.0, 5.0, 4.0, 9.0, 0.0, 250.0, 30.0, 21),
    ('8582008e-4a5e-5465-94cf-87b68fe58eb7'::uuid, '60ee5c1e-0983-51ec-8ded-d0668a24d90f'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     240.0, 10.0, 7.0, 18.0, 0.0, 490.0, 60.0, 22),
    ('a9246088-f84c-5548-8dfd-a488bdb5ee7f'::uuid, 'e9457ae6-3c7e-50fc-9321-00dad9a58275'::uuid, '8 oz', 226.796185, 'mass', 'oz',
     480.0, 20.0, 14.0, 37.0, null, 980.0, 120.0, 23),
    ('92de7b82-c657-5be0-ad2f-f73b2b5cffdc'::uuid, '3edd2b32-9176-586a-b073-65ada21c34d6'::uuid, '3 oz', 85.048569, 'mass', 'oz',
     15.0, 1.0, 3.0, 0.0, 2.0, 15.0, 0.0, 24),
    ('30739059-710a-5184-a785-70c7aca8290c'::uuid, '2a4400e1-0cad-5fa9-ab0a-0fe651a51827'::uuid, '1 oz', 28.349523, 'mass', 'oz',
     5.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 25),
    ('f38aea4e-17ff-5df7-9907-a4d1419b2c51'::uuid, '3e331200-8fdc-5234-8458-0a9506703c2c'::uuid, '4 oz', 113.398093, 'mass', 'oz',
     540.0, 7.0, 73.0, 25.0, 7.0, 390.0, 0.0, 26),
    ('c73dcb2b-564f-5e01-9607-5e250dde6f98'::uuid, 'b6d98702-afc4-59a2-b981-18ce08089c8b'::uuid, '6 oz', 170.097139, 'mass', 'oz',
     810.0, 11.0, 110.0, 38.0, 11.0, 590.0, 0.0, 27),
    ('c63f4754-5901-5c3d-8954-2b38e5bc02f4'::uuid, '5ea7fffc-0742-5bb6-aa5f-408897e8a935'::uuid, '2 fl oz', 59.147059, 'volume', 'fl_oz',
     220.0, 1.0, 18.0, 16.0, 1.0, 850.0, 0.0, 28)
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
