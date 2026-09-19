# FINAL-REVIEW - quantity units v1, planned serving reference

Status: independent read-only verification of the bounded repairs. I did not author the candidate, the prior reviews, or the repairs. Nothing here was built, run, migrated or deployed; every statement is read off the supplied source. Astra reports its own runs separately, and I make no claim about them. No edits are proposed.

## 1. Scope read

Read in full: lib/domain/planning/recent_log.dart, lib/domain/planning/portion_unit.dart, lib/features/plan/entry_resolver.dart, lib/features/plan/log_sheet.dart, lib/data/repositories/plan_repository.dart, lib/data/sync/remote_rows.dart, lib/domain/shopping/shopping_list_builder.dart, lib/features/foods/food_draft.dart, and the four supplied test files (read as source, not as evidence of execution).

Not supplied, therefore not reviewable: food.dart, package_nutrition.dart, plan_mapper.dart, sync_payload.dart, quantity.dart, unit.dart, macro_calculator.dart, the food editor widget, the label reader and edge function, test/support/app_harness.dart, the Drift schema and generated history, and the SQL migration.

## 2. Fixed

F1 - fixed. RecentLog carries servingOptionId; RecentLogs.from reads it off the entry rather than the snapshot, and moves it with the portion when a newer logging wins. PlanRepository.logAgain forwards it into add. log_sheet._logAgain resolves per-serving macros and coverage through EntryResolver.servingForEntry(food, recent.servingOptionId) and declines the one-tap path when that row is gone, opening the sheet instead. The fixture path (six of a 100 kcal label cup) can no longer be re-costed against a 200 kcal default row and frozen.

F2 - fixed. _fromFoods groups by (food id, serving id) and converts each group through portionsOf before any summing. An entry naming a removed row is recorded in unmeasurable, seeds an empty group, and the food still emits a line with hasUnquantified true and no invented count. A food whose only planned use names a removed row reaches the shop rather than vanishing.

F3 - fixed. _unitFrom tries PortionUnit.serving(standard) before units.first, and _standardFor returns the named row, the default when none is named, and null when the named row is gone - so the selected chip and the calorie line name the same row.

F4 - fixed. portionUnitsFor returns an empty list when food is null, before base is computed, so a caller passing standard for a food that has not loaded cannot reach the dereference.

Explicit clear on pull - fixed. applyEntry reads the local row only when SyncPayload.hasServingOptionId is false, and writes through toCompanion(false), so a current client clearing the reference persists null rather than having it treated as absent.

Reopened approximate qualifier - fixed. Both _usesApproximatePackage and _logAgain require food.activePackageServing?.id to equal the row being counted before the qualifier is shown or frozen, so it describes the relationship the numbers actually came through.

REPAIR R1 overflow - fixed. packageNutritionError computes the total volume and implied density and refuses a non-finite or non-positive result with a field explanation. packageNutritionNeedsConfirmation is then false, so Save is no longer blocked behind a confirm that cannot succeed, and packageNutritionPreview declines to print a sentence for that state.

REPAIR R2 note truncation - fixed. _boundedNotes truncates on rune boundaries and caps each note by encoded bytes (jsonEncode then utf8), de-duplicates, and keeps at most six - so a surrogate pair cannot be split and the capture block stays well inside the record cap.

## 3. Not fixed or open, within the reviewed scope

O1 (low, wording only). In _logAgain a food with no servings at all resolves to a null serving and takes the removed-row branch, which says the serving has been removed. The outcome is right; the sentence is wrong for a food that never had one. No data effect.

O2 (low, latent). PlanRepository.logAgain still takes liveCoverage as nullable while add asserts that a recipe states its own coverage. The single caller always passes one, so this is unreachable today; a future caller omitting it for a recipe trips a debug assert rather than failing to compile.

O3 (residual, unverifiable). confirmPackageNutrition still returns this unchanged when relation.isValid or captured.isValid is false. With the overflow guard and the bounded notes both paths should now be unreachable, but PackageNutrition.isValid was not supplied, so the shape and size rules it enforces cannot be checked here. The packet states the editor surfaces a SnackBar when confirm returns the same object; the editor was not supplied, so that is recorded rather than verified.

Already-explicit release gates (payload ordering, migration before client, live label extraction, native and device capture) are tracked in the packet and are not re-raised.

F6 remains pre-existing and out of scope: the v28 block alters shopping_list_items ahead of the v13 block that creates it. Historical schemas 25..28 are available and the 1..28 replay was interrupted, so neither reachability nor a complete historical replay is claimed here.

## 4. Unknown from the supplied source

- Kind and unit spellings: QuantityMapper.kindToSql and Units were not supplied, so client and server agreement on the snapshot kind and unit strings in the food upsert remains unconfirmed. Carried forward from REPAIR-REVIEW as the highest residual risk.
- Food and PackageNutrition accessors: activePackageServing, packageGramsPerMillilitre, ownGramsPerMillilitre, matches, isValid, isSendable, rawJson.
- Whether an ordinary silent panel now reads as as_packaged: the label reader and the edge function were not supplied, so how often the basis prompt appears cannot be checked. An unknown basis still requiring acknowledgement matches approved R9.
- PlanMapper.entryToDomain and entryToJson, SyncPayload, pumpHearthApp, nutrient coverage behaviour, the local Drift upgrade, and anything about migration application or live extraction.

No finding has been invented for any of these.

## 5. Acceptance for the reviewed scope

The four planned findings and both repair items are addressed in the supplied source, and the mechanisms they touch - the serving reference, its four-way wire semantics, the grouped shopping conversion and the package-relationship confirm path - read as internally consistent. I see no blocking regression in the paths supplied. Acceptance of the wider change still depends on the unknowns in section 4 and on the packet's own release ordering, neither of which this pass can settle.
