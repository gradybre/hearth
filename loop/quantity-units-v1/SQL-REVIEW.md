# SQL review — package nutrition (d4-sql-review-a1)

Independent review of the unapplied migration
`supabase/migrations/20260919110000_package_nutrition.sql`, its test file
`supabase/tests/package_nutrition.sql`, and the paged-pull repair appended to
the migration after the full-replay run. Nothing in this review was executed;
the findings are read against the source and against plan R9-R13.

Scope respected: only the unapplied migration and its own test file are
edited. No historical migration is touched.

## Findings

### F1 — A malformed version raises where it should refuse (High, repaired)

`package_nutrition_is_valid` tested the version with a single condition:

    jsonb_typeof(... -> 'version') is distinct from 'number'
      or (... ->> 'version')::numeric is distinct from 1

Postgres does not promise to evaluate the operands of `or` left to right, so
the cast can run against a record whose version is `one` or `true` and raise
22P02. Inside a check constraint that is a 500 where a denial was meant, and
it is reachable through `upsert_food` as well, so an ordinary sync write could
fail with an error nothing in the client is prepared to read. The amount
validator already avoids this by using `case`, which is sequential; the record
validator did not.

Repaired: split into two statements. Regressions added for a string, a boolean
and a JSON null version — each of which the old code would have raised on
rather than refused.

### F2 — Three volume units could never be stored (High, repaired)

The unit allowlist admitted `tsp, tbsp, cup, fl_oz, ml, l` only. The client's
unit table also offers pint, quart and gallon, and a carton whose serving is
printed in pints is unremarkable. Such a record would be refused by the check
constraint — after the user had reviewed and confirmed it — and arrive as an
opaque sync failure with no way forward.

Repaired: the allowlist carries those three. Both the abbreviated and the
spelled-out ids are admitted, because this list is a copy of one kept in Dart
and the two must not be able to disagree quietly; admitting a spelling the
client never writes costs nothing, since `kind` must still agree and the unit
is still a volume either way. Before applying, confirm the exact ids in
`lib/domain/units/unit.dart` and drop any spelling that does not exist there.
Mass is unchanged (`g, kg, oz, lb`); confirm no milligram id is authorable.

### F3 — The paged repair is correct, and now pinned (Medium, test added)

`changed_foods_page` as appended to the migration was compared field by field
against both the new `changed_foods` and its last whole definition in
`20260912090000_paged_library_pull.sql`. The two new keys are present, every
prior key is carried, and the keyset predicate, the `(updated_at, id)`
ordering and the `greatest(1, least(p_limit, 1000))` clamp are unchanged. No
repair needed.

It was, however, unpinned. Every existing guard for a food column reads
`changed_foods`, which the app no longer calls, so the pair can diverge again
in silence — which is how it diverged the first time. A guard comparing the
whole paged and unpaged payloads for a fixture carrying both new fields is
added here rather than left to the whole-table comparison in
`schema_guards.sql`, which runs against a different database and did not catch
it either.

### F4 — A direct REST write can name another food's serving (Low, accepted)

The membership and snapshot checks live in `upsert_food`. A client holding the
ordinary UPDATE privilege on `foods` can set `package_nutrition` straight
through PostgREST, where only the check constraint applies — and that
validates shape, not membership.

Accepted as designed. The client resolves the relation by looking the id up in
*this* food's serving list and re-comparing both snapshots, so a foreign or
absent id yields no active relation and no conversion: the stored value is
inert evidence, which is exactly what a stale record already is. The thing
that must not happen — storing a shape nothing checked — is prevented by the
constraint. Moving membership into a trigger would also have to refuse an old
client's otherwise valid write, which R13 forbids.

### F5 — Time-of-check on the pre-read (Low, accepted)

`upsert_food` reads the stored record without `for update`, deliberately: a
row lock would demand the UPDATE policy for a decision that is read-only.
Under a concurrent write the worst outcome is a stored record that some
transaction did validate and that no longer matches — indistinguishable from
the stale records R13 already requires the client to detect. It cannot store
an unchecked shape.

### F6 — An explicit null display mode reads as automatic (Info)

`coalesce(p_food ->> 'mass_display_mode', 'automatic')` means a payload
sending the key with a JSON null resets the preference rather than preserving
it. Harmless: compatibility turns on the *absent* key, which is what an older
build sends, and that path preserves correctly.

### F7 — Unknown versions are refused server-side (Info)

The client keeps an unrecognised version opaque; the server stores version 1
only. Correct under R13: a future format ships its migration before the client
that writes it, so there is nothing here that could be activated by mistake.

### F8 — Default EXECUTE on the two validators (Info)

Both are created without a grant, so PUBLIC may execute them. They are
immutable, take only jsonb, read no table and hold no secret, and every writer
needs them through the check constraint. No escalation. A guard now asserts
both are immutable and that neither they nor the sync functions have become
`security definer`.

## Verified unchanged

- No policy, grant, role or RLS change. `upsert_food`, `changed_foods` and
  `changed_foods_page` remain security invoker, so a client still writes only
  what its own policies allow and no global or cross-household row becomes
  writable.
- The soft-delete columns and the resurrection triggers are untouched.
- `upsert_food` still deletes the serving rows *before* the food is upserted,
  which is what lets a modifier be turned back into an ordinary food under the
  composite foreign key.
- `is_modifier` is still taken from the food rather than from the serving.
- The minor nutrients still have no `coalesce`: a silent fibre stays silent.
- Omitted key preserves, explicit null clears, an identical resend is exempt
  from the membership check, and a new or changed relation is validated
  against the servings being saved.
- 4 KiB bound, finite positive amounts, 1e400 refused on the count and on both
  amounts, count units refused on both sides, and oz kept distinct from fl oz.

## Repairs delivered

1. `20260919110000_package_nutrition.sql`: version check split into two
   statements; volume allowlist extended.
2. `supabase/tests/package_nutrition.sql`: non-numeric versions refused rather
   than raising; every authorable volume and mass unit accepted; paged and
   unpaged payloads compared whole; security-invoker, volatility and RLS
   guards.

None of the R13 limits (finite positive, version 1 only, 4 KiB, as-packaged
basis) is changed by this review.
