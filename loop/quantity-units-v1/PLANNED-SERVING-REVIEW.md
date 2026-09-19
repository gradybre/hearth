# D29 planned serving reference - independent review

Status: review only. Nothing in this pass was built, run, migrated or deployed; the supplied tests are read as source, not as evidence of execution. The candidate under review was not authored by this reviewer, and the source was treated as read-only.

## 1. Scope reviewed

Read in full: `lib/domain/planning/meal_plan.dart`, `lib/domain/planning/portion_unit.dart`, `lib/features/plan/entry_resolver.dart`, `lib/features/plan/log_sheet.dart`, `lib/data/repositories/plan_repository.dart`, `lib/data/mappers/plan_mapper.dart`, `lib/data/mappers/sync_payload.dart`, `lib/data/sync/remote_rows.dart`, `lib/data/local/tables.dart`, `lib/data/local/hearth_database.dart`, `lib/domain/shopping/shopping_list_builder.dart`, `supabase/migrations/20260919113000_planned_serving_reference.sql`, `supabase/tests/planned_serving_reference.sql`, and the two supplied Dart test files.

Not supplied, therefore not reviewable: `Food`, `PackageNutrition`, `ServingOption`, `NutrientCoverage`, `RecentLog`/`RecentLogs`, `ShoppingLine`, `ShoppingContributions`, `PreferenceStore`, `SupabaseRemoteGateway`, `plan_store.dart`, the day screen, and the widget harness `test/support/app_harness.dart`. Claims that depend on those are marked unverifiable in section 5.

## 2. Contract checks that hold

Each item below was traced through the supplied source.

- **Reference semantics.** `MealPlanEntry.servingOptionId` is nullable; null is documented and implemented as a count of `Food.defaultServing`, and no code invents an id for legacy rows. `EntryResolver.servingForEntry` returns the default only when the id is null, and returns null (not the default) when a named row is gone.
- **Missing named row leaves a planned entry uncostable.** `EntryResolver.resolve` sets `isResolvable: false` and `perServing: Macros.zero` for that case, so `isUncostable` is true for pending entries and false for logged ones. Logged entries answer from `MealPlanEntry.contribution` via the frozen snapshot, which is unaffected.
- **Snapshots stay frozen.** `copyWith` carries `macroSnapshot` through untouched; `filedUnder` (move) and `log` both carry `servingOptionId`; `PlanRepository.logEntry` refuses to repoint the reference when `existing.isLogged`, so a correction to an already-logged meal cannot change the row it counts. `copyAsPlanned` carries the reference, and `repointUnloggedEntry` clears it, which is right because the old row belonged to a different food.
- **`unlog` preserves the reference** and drops only the snapshot, matching the documented intent.
- **Omitted vs explicit clear.** `PlanMapper.entryToJson` always emits the key and uses `''` for none; `PlanMapper.servingOptionIdFromSql` and `SyncPayload.servingOptionId` both read `''` back as null; `SyncPayload.hasServingOptionId` distinguishes silence from a clear; `RemoteRows.applyEntry` reads the local row and preserves its value only when the key is absent. This is the correct four-way behaviour and is consistent across all three layers.
- **Server trigger.** `preserve_entry_serving_option` is BEFORE UPDATE, `security invoker`, `set search_path = ''`, and only copies OLD onto NEW when NEW is null. It cannot be used to escalate privilege, and it does not weaken the table policy. The `''` sentinel is not null, so an explicit clear from a current client passes through. Inserts are untouched, which is right.
- **SQL idempotence.** `add column if not exists`, a named constraint dropped-then-added, `create or replace function`, and `drop trigger if exists` before `create trigger` make the migration safe to re-apply. Adding the constraint by name rather than inline on `add column if not exists` is the correct choice and the file says why.
- **Bound.** `length(serving_option_id) <= 128` caps the column; the value is only ever compared, never interpolated, so there is no injection surface.
- **Drift v29.** `schemaVersion` is 29 and the new block adds two food columns and `meal_plan_entries.serving_option_id` through `_addColumnIfMissing`, which swallows only duplicate-column errors. All three target tables exist from v1, so the block is safe despite `onUpgrade` running newest-first. The local column is nullable with no default, matching the server.
- **Shopping consolidation.** `ShoppingListBuilder._fromFoods` groups by (food id, serving id) and converts each group through `portionsOf` before any summing, so counts of unlike rows are never added. `portionsOf` gained an optional `serving` parameter, so existing callers keep the default-serving behaviour.

## 3. Findings

### F1 (high) - one-tap repeat re-costs a package-derived portion against the default serving

`RecentLog` carries no serving reference, and both repeat paths ignore one. `_LogSheetState._logAgain` computes `perServing` as `foods[recent.refId]?.defaultServing?.macros`, and `PlanRepository.logAgain` forwards to `add` without `servingOptionId`.

Repro, using the packet fixture (10 oz package, 2 servings, selected row `package` at 100 kcal per cup, default row at 200 kcal per cup): log 30 oz. The entry stores `servings: 6`, `servingOptionId: package`, snapshot 600 kcal. The next day, open the log sheet and tap the recent row for that food. The new entry stores `servings: 6` with no reference, and freezes 6 x 200 = 1200 kcal.

Impact: the repeat silently records double the meal it claims to repeat, and the result is frozen history that rule 3 forbids correcting later. It is a plausible daily path, not an edge case.

Fix: carry the reference on `RecentLog` (built in `RecentLogs.from`, which already receives whole `MealPlanEntry` values), pass it through `PlanRepository.logAgain` into `add`, and resolve the per-serving macros from that row via `EntryResolver.servingForEntry` rather than from `defaultServing`. If the named row is gone, decline the one-tap repeat and open the sheet instead, matching the uncostable rule already used on the plan surface.

### F2 (medium) - a planned food whose selected row was deleted vanishes from the shopping list

In `ShoppingListBuilder._fromFoods`, an entry naming a row that no longer exists is skipped with `continue`. If that entry is the only planned use of the food, the food produces no line at all.

Repro: plan 6 of the `package` row, delete that serving row from the food, rebuild the list for the range. The food is absent; the plan screen correctly reports the entry as uncostable, but the shopper gets nothing and no signal.

Impact: a silently understated shop. The asymmetry with `EntryResolver` is the tell - one surface reports the gap, the other hides it.

Fix: still emit a line for the food with an empty `planned` list and `hasUnquantified: true`, the same signal `_fromRecipes` already propagates for unmeasurable ingredients. `_planLine` already forwards `hasUnquantified` into the plan contribution, so the change is confined to the skip branch.

### F3 (low-medium) - the reopened sheet preselects the wrong serving chip

`_unitFrom` falls back to `units.first`, and `portionUnitsFor` lists every same-kind serving row in the food order. For a reopened planned entry the selected chip is therefore the food's first row, not the row `_servings` counts.

Repro: plan the fixture amount (stored as 6 of `package`), reopen the sheet with no remembered unit. The chip reads `Default cup` while the calorie line reads 600, which is 6 x the `package` row. The arithmetic is right - `count` is computed against `_standardFor`, and `_basis` writes back the stored reference - but the displayed unit and the displayed calories name different rows.

Impact: no data loss and no wrong write; a genuine reading hazard where two same-kind rows carry different macros, which is exactly the case the package relationship creates.

Fix: when `_servingOptionId` is non-null, seed the chip from `_standardFor(foods)` before falling back to the remembered id and then to `units.first`.

### F4 (low, latent) - `portionUnitsFor` null-asserts the food

`portionUnitsFor(Food? food, {ServingOption? standard})` computes `base = standard ?? food?.defaultServing` and returns early only when `base` is null, then dereferences `food!`. A caller passing `standard` with a null `food` throws.

No current caller does: the only call site passes `_standardFor(foods)`, which returns null whenever the food is null. Recorded as hardening rather than a live defect.

Fix: return an empty list when `food` is null, before computing `base`.

### F5 (release gate) - the payload key is unconditional

`PlanMapper.entryToJson` always writes `serving_option_id`. A client on this build talking to a server that has not had the migration applied will have every plan-entry upsert rejected for an unknown column, which strands the whole queue rather than one field.

This matches the packet's stated ordering, but it is a hard gate rather than a preference: the additive SQL must be applied and verified before any client carrying this mapper is released, and a client rollback is safe only because the column is additive.

### F6 (pre-existing, out of scope) - `onUpgrade` block ordering

`HearthDatabase.migration` runs its version blocks newest-first. The `from < 28` block alters `shopping_list_items`, which is not created until the `from < 13` block further down. An upgrade from a schema below 13 would therefore ALTER a table that does not yet exist, and `_addColumnIfMissing` rethrows anything that is not a duplicate-column error.

This predates the candidate (it arrived with v28) and the v29 block is not affected, because all three of its target tables exist from v1. Reachability depends on whether any device still sits below v13, which cannot be established from the supplied source. Recorded so it is not lost, not proposed as part of this change.

## 4. Security review

No new secret, scope, endpoint or trust boundary. The trigger is invoker-rights with an empty `search_path` and references no unqualified objects. RLS is untouched and continues to govern every write; the trigger cannot widen it. The column is free text bounded at 128 characters and there is deliberately no foreign key, which is consistent with the existing `ref_id` reasoning: history must not depend on a target still existing, and a cascade would silently rewrite a portion.

One accepted risk, stated for the record: the server does not validate that `serving_option_id` names a serving of the referenced food. The client already treats an unknown id as uncostable rather than substituting the default, so the failure mode is a visible gap rather than a wrong number. Adding membership validation here would require the food to be readable in the same transaction and would break the deliberate absence of a foreign key.

## 5. Unverifiable from the supplied source

- Whether `Food.packageGramsPerMillilitre`, `activePackageServing` and `ownGramsPerMillilitre` behave as `packagePortionFor` assumes, including staleness of a reviewed relation. `food.dart` and `package_nutrition.dart` were not supplied.
- Whether `NutrientCoverage.ofOne` reports an unknown fibre as unknown, which the 600 kcal fixture depends on for its null-fibre assertion.
- Whether the remote gateway actually pushes `insert ... on conflict do update set col = excluded.col`. The migration comment asserts it, and the trigger is only load-bearing under that shape; under a plain UPDATE with an omitted column the trigger is harmless but redundant.
- Whether `RecentLogs.from` retains enough of the entry to carry a serving reference (F1's fix); the call shape suggests it does, since it receives whole entries.
- The widget test in `test/features/plan/planned_package_context_test.dart` depends on `pumpHearthApp`, which was not supplied, and on the `oz` chip being offered, which depends on the unsupplied density accessors.
- All statements about migration replay, generated schema history and hosted behaviour. Nothing was executed.

## 6. Test coverage gaps observed

Read from the two supplied Dart tests and the supplied SQL test.

- No test covers F1's repeat path, F2's deleted-row shopping case, or F3's chip preselection.
- No test covers switching the display chip on a reopened planned entry and asserting that neither the stored portion nor the macros move. That guard is the subtlest part of `log_sheet` (`_amountBasis` versus `_entryUnit`) and is currently unprotected.
- No test covers shopping consolidation of two planned entries on the same food in two different serving rows.
- `supabase/tests/planned_serving_reference.sql` runs its `do $$` block as the owner, so it exercises the trigger and the omitted-key case but not RLS. It also never asserts that a value longer than 128 characters is rejected, and never exercises a current client's explicit `''` clear through the `on conflict do update` shape the trigger is written for.
- Test evidence for a real local database upgrade and a hosted deployment is outstanding; both are required gates and neither can be satisfied by schema or adapter tests.

## 7. Recommendation

The core mechanism is sound: the reference is additive, nullable, carried through every state transition reviewed, correctly distinguished from silence on the wire, and enforced without weakening RLS. F1 should be fixed before release - it writes wrong frozen history through a one-tap path. F2 and F3 should be fixed before release as well, being small and confined. F4 is hardening. F5 is an ordering requirement on deployment, not a code change. F6 is pre-existing and should be raised separately rather than folded into this change.
