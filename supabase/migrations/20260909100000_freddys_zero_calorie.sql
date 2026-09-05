-- Freddy's condiments that carry no macros at all (spec 5.5).
--
-- Five rows: the three steakburger-and-fry seasoning portions and both
-- mustards. Freddy's publishes each as zero across all four macros with only
-- sodium, which is the restaurant's real answer rather than a half-filled
-- import -- but `needsAttention` cannot tell those apart without
-- `is_zero_calorie`, and `foods_update_household` requires a household, so a
-- client can never clear the flag on a global food. Left alone, five
-- condiments would sit in the library's "needs attention" filter forever with
-- no way out.
--
-- Why a second migration rather than a fix to the seed: 20260909090000 had
-- already been applied to the hosted database when this was found. The seed
-- and its generator are corrected too, so a database built from scratch gets
-- the flag from the seed itself and this file is a no-op there. It exists for
-- the one database that had already run the first version.
--
-- Addressed by id, not by name: a name is what a restaurant changes.

update public.foods
set is_zero_calorie = true,
    updated_at = now()
where id in (
  -- Freddy's Famous Steakburger & Fry Seasoning (1g packet)
  'c13f38be-1671-526f-b414-f71a77ab5b35'::uuid,
  -- Freddy's Famous Steakburger & Fry Seasoning (Portion per Steakburger patty)
  '7341b397-088c-5c69-b759-80685e645689'::uuid,
  -- Freddy's Famous Steakburger & Fry Seasoning (Portion per regular fries)
  '60b7d0ab-d321-5359-9f90-eee9a1dae20e'::uuid,
  -- Mustard
  '3f2173aa-e717-5e52-89eb-cdd9b3816f83'::uuid,
  -- Mustard (Packet)
  '0db416f3-c524-5117-af11-c4c53559d346'::uuid
)
and household_id is null
and source = 'restaurant'
and is_zero_calorie = false;
