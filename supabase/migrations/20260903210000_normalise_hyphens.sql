-- Re-key remembered ingredient matches now that a hyphen is a separator.
--
-- normaliseKey used to keep the hyphen, so "sun-dried tomatoes" and "sun
-- dried tomatoes" were different keys — and recipes spell the same ingredient
-- both ways. Everything keyed on it split in two: the shopping list showed a
-- line per spelling, a duplicate food was never flagged, and a match
-- remembered under one spelling was asked again under the other. A slash was
-- worse than a hyphen — it was deleted outright, fusing "96/4" into "964".
--
-- The client now treats both as spaces. This brings the rows already stored
-- into line, because a match keyed the old way is simply never found again.

-- The exact counterpart of Dart's normaliseKey. Kept as a function rather than
-- inlined so the two can be compared side by side, and so the merge below can
-- use it twice without repeating four regexes.
create or replace function public.normalise_ingredient_key(p_raw text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      regexp_replace(
        -- Separators first, so "sun-dried" becomes two words, not one.
        regexp_replace(lower(coalesce(p_raw, '')), '[-/]', ' ', 'g'),
        '[^a-z0-9[:space:]]', '', 'g'
      ),
      '\s+', ' ', 'g'
    )
  )
$$;

comment on function public.normalise_ingredient_key(text) is
  'The SQL counterpart of Dart normaliseKey (lib/domain/text/text_normaliser.dart). '
  'If one changes, the other must.';

do $$
declare
  v_merged int;
  v_rekeyed int;
begin
  -- Re-normalising makes some rows collide that did not before: a household
  -- that answered "Sun-dried tomatoes" and "sun dried tomatoes" separately now
  -- has two rows for one key. The newer answer wins — it is the more recent
  -- thing the household said about that wording — and ties fall back to the id
  -- so the outcome does not depend on row order.
  with ranked as (
    select id,
           row_number() over (
             partition by household_id,
                          public.normalise_ingredient_key(ingredient_string)
             order by updated_at desc, id desc
           ) as rank
    from public.ingredient_matches
  )
  delete from public.ingredient_matches m
   using ranked r
   where m.id = r.id and r.rank > 1;
  get diagnostics v_merged = row_count;

  update public.ingredient_matches
     set ingredient_string = public.normalise_ingredient_key(ingredient_string)
   where ingredient_string
         is distinct from public.normalise_ingredient_key(ingredient_string);
  get diagnostics v_rekeyed = row_count;

  -- A wording that normalises to nothing at all was never findable.
  delete from public.ingredient_matches where btrim(ingredient_string) = '';

  raise notice
    'ingredient matches: % re-keyed, % merged away', v_rekeyed, v_merged;
end;
$$;

-- Shopping lines are merged by item_key, which for an ingredient with no
-- matched food is the same normalised wording. Left alone, the first rebuild
-- after this change would see a hyphenated line as brand new and quietly drop
-- its tick, its on-hand amount and any quantity edited by hand — the whole
-- point of merging rather than replacing. A matched line is keyed by food id
-- and is unaffected.
update public.shopping_list_items
   set item_key = public.normalise_ingredient_key(item_key)
 where item_key is not null
   and food_id is null
   and item_key is distinct from public.normalise_ingredient_key(item_key);

-- Ids are deliberately left alone. The client derives one from the key with a
-- v5 UUID, so a re-keyed row's id no longer matches what the client would
-- compute — but every writer upserts on (household_id, ingredient_string) and
-- rewrites the id on conflict, so the rows correct themselves the next time
-- the household answers. Building SHA-1 UUIDs in a migration would be a lot of
-- surface to save the app one self-correcting write.
