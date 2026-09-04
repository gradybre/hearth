-- A Chipotle portion is the portion, to the last decimal (spec §5.2).
--
-- The first seed rounded each canonical amount to six places, so 4 oz was
-- stored as 113.398093 g rather than 113.3980925. Converting that back gives
-- **4.000000017636981 oz**, which is what a bowl built from the menu showed
-- in its ingredients — and half a scoop showed 2.0000000088184904.
--
-- The display now snaps residue away, so this is not the only thing standing
-- between a user and that string. It is still worth fixing at the source: the
-- numbers are wrong, however well they are printed, and every future reader
-- of them inherits the error.
--
-- An update, not an insert. Nothing here creates a serving.

update public.food_serving_options as o
set amount_canonical = v.amount
from (values
    ('e257eeda-cdb1-5f92-894c-1d0be6492cc2'::uuid, 1.0),
    ('45095f17-ac0e-5007-86e1-cfd34d4bcdac'::uuid, 1.0),
    ('ac2ff943-db40-5b17-aafe-b2ce4b244ca0'::uuid, 1.0),
    ('40e9b38b-825a-5138-867f-a0cd22bbd458'::uuid, 113.3980925),
    ('3dedb012-ab4b-54da-9786-59b563e4f6ea'::uuid, 113.3980925),
    ('c15baee1-4dfe-5148-b043-7b1c60b09e58'::uuid, 113.3980925),
    ('52283d42-fffe-58b4-b095-83203bad32e0'::uuid, 113.3980925),
    ('87526a82-4981-5b8a-b94e-590ddf417554'::uuid, 56.69904625),
    ('5519428d-b3f1-5ea2-9f9f-b5dcac5a8594'::uuid, 113.3980925),
    ('a06052ed-766d-571b-a26c-b2d63978d4ee'::uuid, 113.3980925),
    ('708faa26-fdcb-5cee-ad85-b50e32f7f3cd'::uuid, 113.3980925),
    ('5117b510-ece6-5e6c-948f-7b997f849fa9'::uuid, 113.3980925),
    ('1f4cab86-e758-5b52-85d5-bda8d4eb6ca8'::uuid, 113.3980925),
    ('b2efbadb-cdd4-53c0-8fe1-f8e364adf45d'::uuid, 113.3980925),
    ('f2a6034a-5c2e-50c5-9647-7d68480ea2b4'::uuid, 113.3980925),
    ('3597532d-72b8-5ec7-b3ef-2566ff3a65df'::uuid, 59.147059125),
    ('f36ee8b6-9d46-5865-97b6-0480fbea8e8a'::uuid, 59.147059125),
    ('c88ca333-6bfa-57e8-ba0b-d53e29bc921c'::uuid, 28.349523125),
    ('b4dd4cc1-6c16-555d-8075-96f2954aba33'::uuid, 56.69904625),
    ('f5a351df-5d2f-5562-8d47-6a73a7c87320'::uuid, 113.3980925),
    ('a63283bf-1e29-5192-a1fa-d19e01600da6'::uuid, 226.796185),
    ('58470263-be90-57cc-a8af-26bc5c2176c6'::uuid, 56.69904625),
    ('8582008e-4a5e-5465-94cf-87b68fe58eb7'::uuid, 113.3980925),
    ('a9246088-f84c-5548-8dfd-a488bdb5ee7f'::uuid, 226.796185),
    ('92de7b82-c657-5be0-ad2f-f73b2b5cffdc'::uuid, 85.048569375),
    ('30739059-710a-5184-a785-70c7aca8290c'::uuid, 28.349523125),
    ('f38aea4e-17ff-5df7-9907-a4d1419b2c51'::uuid, 113.3980925),
    ('c73dcb2b-564f-5e01-9607-5e250dde6f98'::uuid, 170.09713875),
    ('c63f4754-5901-5c3d-8954-2b38e5bc02f4'::uuid, 59.147059125)
) as v (id, amount)
where o.id = v.id;
