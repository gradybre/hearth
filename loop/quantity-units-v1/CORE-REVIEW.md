# CORE-REVIEW — quantity units v1 (R6, R9, R12, R13, logging, sync, scan)

Independent review. I did not author this candidate. Everything below is read off the supplied source rather than the authoring notes. Nothing was run, built or tested; each item cites a file, a member and a reproduction path.

No source edits are made here. Repairs are requested for Astra to schedule as bounded tasks.

Out of scope by instruction, and deliberately not reviewed: the server SQL migration and the food upsert function, the food editor and draft recovery, and the shopping surfaces. Where a finding crosses one of those boundaries it is stated as a required piece of evidence rather than as a change to those files.

## Blocking

### B1 — High — an unusable stored density both blocks the reviewed package fallback and poisons macros with NaN or Infinity

`lib/domain/models/food.dart`, `ownGramsPerMillilitre` / `effectiveGramsPerMillilitre`; `lib/domain/recipes/macro_calculator.dart`, `MacroCalculator.forIngredient` and `_tryCrossKind`; `lib/domain/units/unit_converter.dart`, `UnitConverter.crossKind`.

`ownGramsPerMillilitre` returns the stored `gramsPerMillilitre` verbatim, with no check that it is finite and positive. Two consequences, both in the new precedence path:

1. R12 says the first step is a *usable* direct answer. Here any non-null value, including 0, a negative or NaN, makes `ownDensity != null` true in `forIngredient`, which is the exact condition guarding the new package branch — so a reviewed, valid package relationship is skipped in favour of a figure that cannot answer anything.
2. `_tryCrossKind` then calls `crossKind` with that density. `crossKind` only tests `density == null`, so for NaN it returns `ConversionResult(densityMissing: false)` carrying a NaN canonical amount; `isExact` is true, the ratio is NaN, and `Macros.scaledBy(NaN)` propagates NaN into the ingredient, the recipe total, the per-serving figure and any day that logs it. A stored 0 gives Infinity by the same route.

Reproduction: a foods payload with `grams_per_millilitre` as the string NaN (or 0). `SyncPayload._double` accepts it — `double.tryParse` parses NaN, Infinity and -Infinity — and `SyncPayload.food` puts it straight on the model. Then any volume ingredient against that food returns `IngredientMacroStatus.resolved` with NaN macros instead of either a package-derived answer or an honest `unconvertible`.

Note the asymmetry that makes this clearly a defect rather than a house style: `PackageNutrition.gramsPerMillilitre` and `portion_unit.dart`'s `_across` both guard `isFinite` and `> 0`. The macro path is the one place that does not.

Requested repair: a single usability accessor (finite and greater than zero) used by `ownGramsPerMillilitre`, so a malformed stored density is ignored and the package relationship is allowed to answer, per R12's wording.

### B2 — High — cross-kind portion units are offered on an unusable density, and the conversion then silently stores the typed number as servings

`lib/domain/planning/portion_unit.dart`, `portionUnitsFor`, `PortionUnit.countOf`, `PortionUnit.toDefaultServings`.

`canCross` is `other != null && food!.effectiveGramsPerMillilitre != null` — a null check only. With the same unusable density as B1, the ml and fl oz chips are offered. `countOf` and `toDefaultServings` then call `_across`, which correctly returns null, and both methods fall back to returning their input **unchanged**. The field therefore shows the serving count under a volume label, and the stored value is the typed number read as a count of the default serving.

Reproduction: food whose default serving is 170 g, stored density 0. Tap the ml chip, type 250, log. `toDefaultServings` returns 250, so the row stores 250 servings of 170 g — 42.5 kg — with no warning anywhere.

This needs its own repair even after B1, because `countOf`'s documented fallback is to return the value unchanged rather than to refuse; the guard has to be at the point the unit is *offered*. Requested repair: gate `canCross` on the same finite-and-positive accessor.

### B3 — High — logged coverage is derived from a different serving row than the macros, and is frozen

`lib/features/plan/log_sheet.dart`, `_LogSheetState._coverage` versus `_LogSheetState._perServing`; `lib/domain/planning/portion_unit.dart`, `packagePortionFor`.

When a raw mass amount resolves through the package relationship, `_perServing` takes its numbers from `packagePortionFor`, which correctly scales `food.activePackageServing`'s macros — the row the relationship was reviewed against. `_coverage` does not follow: for a food it returns `NutrientCoverage.ofOne(_food.defaultServing.macros)`, and for an existing entry `widget.existing!.liveCoverage`. Neither is the selected row.

Reproduction: a food with two rows both labelled 1 cup, the default one stating fibre and the package-selected one leaving fibre null. Type 30 oz and log. The frozen `MacroSnapshot` carries a null fibre with a coverage that says fibre is complete. Per spec section 4 and rule 3 a snapshot is never recomputed, so the wrong claim is permanent, and it is exactly the defect `NutrientCoverage` was introduced to prevent (see the comment on `MealPlanEntry.log` about `ofOne` being the original bug).

Requested repair: have `PackagePortion` carry the serving it used (or its coverage) and read `_coverage` from the same source as `_perServing`, so the two cannot diverge.

### B4 — Medium-high — the client persists and pushes records its own validator rejects, and the 4 KiB bound is measured on different bytes than are written

`lib/data/mappers/food_mapper.dart`, `encodePackageNutrition` and `toJson`; `lib/domain/models/package_nutrition.dart`, `isValid`.

`isValid` is advisory: nothing at the write boundary consults it. `encodePackageNutrition` encodes whatever is attached, and `toJson` always states `package_nutrition`. So a malformed version-1 record — an over-cap one, or one whose `source` is null, both of which `isValid` rejects — is written locally and pushed.

If the server enforces R13's shape, finite-positive and payload-bound checks, the rejection lands on the *whole* food upsert. The pending write then retries to the attempt cap set in v25 and that food stops syncing entirely, taking unrelated name, macro and serving edits with it. R13 asks for the bound to be enforced on client as well as server, which today it is not.

Separately the bound is measured inconsistently: `isValid` sizes `rawJson` when it is non-empty, but the bytes actually persisted are `toJson()`, which for version 1 rebuilds only the known keys. A record can be rejected client-side while its persisted form is well under 4 KiB, and — with B4's missing gate — a record can be written whose measured size was never the written size.

Requested repair: measure the bound on the exact bytes to be written, and either refuse to attach an invalid version-1 record to an outgoing payload while keeping it locally for correction (R10 preserves original facts for correction), or confirm the server accepts and ignores it. Blocking on evidence that a malformed relation cannot block an unrelated edit to the same food.

## Medium

### M5 — version-1 forward compatibility is lost on any unrelated re-save

`lib/domain/models/package_nutrition.dart`, `toJson`.

`toJson` returns `rawJson` verbatim only when `version != 1`. For version 1 it rebuilds from the typed fields, so any key a newer client added inside a version-1 record is dropped the next time this build saves the food. R13 asks that opaque values be preserved on unrelated writes.

Reproduction: server row `{version: 1, ..., basis_note: drained-verified}`; edit the food's brand on this build and save; the extra key is gone for every device.

The codebase already has the right pattern twice over: `MacroSnapshot.unreadFields` with `PlanMapper._snapshotKeys`, and `snapshotToJson` spreading the unread map first so known keys win. Requested repair: the same treatment here, or `{...rawJson, ...knownFields}`.

### M6 — staleness is keyed on preferred-unit identity, which is stricter than R13 and must match the server

`lib/domain/models/package_nutrition.dart`, `_sameQuantity` (used by `matches`, hence by `Food.activePackageServing` and `hasStalePackageNutrition`).

`_sameQuantity` returns false when `a.preferredUnit != b.preferredUnit`. R13 says numeric equality uses the existing same-kind tolerance and that the id and the dimension must agree — it does not require the display unit to agree. So the same physical amount re-expressed in another unit, 10 oz to 283.495 g or 1 cup to 8 fl oz, invalidates a human-confirmed relation and raises Check package servings.

This fails safe (it never yields a wrong density) and `test/domain/recipes/package_nutrition_validation_test.dart` asserts it deliberately, so it is accepted **conditionally** on two things:

- The server validity check compares the unit too. Otherwise the client hides a relation a peer still treats as active, and the two disagree about whether a review is needed. This is the piece of evidence I need; the SQL is out of scope here.
- A pack size reconstructed without a unit can still be matched. It cannot today: `packSizeFrom` in `food_mapper.dart` yields `preferredUnit == null` when `pack_unit` is absent, `_isUsable` requires a non-null preferred unit on the snapshot, and `_sameQuantity` requires identity — so such a food is permanently stale with no route back except re-review. Any payload that states `pack_canonical` and `pack_kind` without `pack_unit` produces this.

### M7 — a remembered *display* unit moves a planned entry's macros

`lib/features/plan/log_sheet.dart`, `_perServing`, `_basisFor`, `_recordEntryUnit`.

The `_amountBasis` field exists precisely so that changing the display unit does not restate the amount, and it works for the in-session case — `_PortionUnitPicker`'s callback pins `_amountBasis ??= unit` before moving `_entryUnit`, which is why the widget test showing 200 kcal after tapping oz holds. On reopen it does not: `_amountBasis` is null, `_basisFor` falls back to `_unitFrom(units)`, and `_recordEntryUnit` stored the *displayed* unit rather than the entered one. `_perServing` consults `_packagePortion` before `widget.existing!.perServing`, so a planned entry reopens costed through the package-selected row rather than the default serving the day screen projects from.

Reproduction: food with default row cup-a at 200 kcal and package-selected row cup-b at 100 kcal; plan one serving having typed in oz, so `logUnitForEntry` remembers unit:oz; reopen the planned entry. The sheet reads 100 kcal where the day reads 200, and Update freezes 100.

Requested repair: take the package path only when the amount was actually entered in that unit (`_amountBasis != null`), which is the distinction the field was added to draw.

### M8 — the scan controller's generation counter is global, so one slot cancels an in-flight pick for the other

`lib/features/foods/label_scan_controller.dart`, `pick`, `remove`, `_run`.

`pick` captures `run = ++_run` and, after the await, returns without assigning when `run != _run`. `remove` and a second `pick` both bump `_run` unconditionally. So an operation on one slot discards the result of an in-flight pick for the *other* slot, silently: no message, empty slot.

Reproduction: begin `pick(LabelSlot.nutrition, library)`; while the system picker is open, `remove(LabelSlot.package)`; when the nutrition photo returns it is dropped. R11 requires that cancellation never clears the other slot.

Requested repair: per-slot generations for `pick`; keep the single global generation for `read`, where it is correct.

### M9 — `PackageNutrition.manual` defaults `basis` to `asPackaged`, so an unverified basis fails open

`lib/domain/models/package_nutrition.dart`, the `manual` factory and `PackageNutritionBasis`.

`EdgeFunctionLabelReader.readingFrom` deliberately returns `packageBasis` as `unknown` for prepared, drained and unreadable panels, and `_basis` clamps anything unrecognised to `unknown`. The enum has no member for that state, and the factory's default is the one basis `isValid` accepts. Any caller that forgets to branch on `reading.packageBasis` activates an as-packaged relation off a drained or as-prepared panel, which R9 forbids outright.

The food editor is out of scope here, so this is reported as a domain API hazard rather than an editor bug: the unsafe call is currently the shortest one to write. Requested repair: make `basis` required, or add an `unverified` member that `isValid` rejects, so the rule lives in the type.

## Low

### L10 — `MergePlan.merged` omits `isDeleted`

`lib/domain/foods/food_merge.dart`, the `merged` getter. Every field is spelled out on the stated grounds that this prevents a silent drop, and `isDeleted` is already missing, so merging a soft-deleted survivor resurrects it. Pre-existing; worth fixing while the constructor is being touched.

The new fields in the same getter are correct: `massDisplayMode` takes the survivor's own preference, and `adoptedPackageNutrition` adopts only when the survivor has none, remaps the serving id with the same derived scheme `unionServings` uses, and re-validates `matches` against `survivor.packSize` — so no relationship is borrowed from another food or pinned to a package nobody reviewed.

### L11 — a finite but absurd servings-per-package is valid with no usable density and no staleness cue

`lib/domain/models/package_nutrition.dart`, `isValid` and `gramsPerMillilitre`. With a one-cup serving, counts above roughly 7.6e305 overflow `servingAmount.canonicalAmount * servingsPerPackage` to infinity, so `gramsPerMillilitre` returns null while `isValid` stays true. `activePackageServing` then resolves, `hasStalePackageNutrition` is false, and the editor shows a confirmed relationship that answers nothing. Requested repair: require `gramsPerMillilitre != null` in `isValid`, which also collapses two definitions of usable into one.

### L12 — an old build downgrades a future mass display mode

`lib/data/mappers/food_mapper.dart`, `massDisplayModeFrom` and `toJson`. The omitted-key case is handled correctly. An unknown *value* reads as automatic, and because `toJson` always states the key, the next ordinary edit writes automatic back over it. R8 only protects known explicit settings, so this is within spec, but one edit from an old build erases a new mode for the whole household. Worth a documented note or a server-side preserve-on-unknown.

## Verified, no action

- R9 arithmetic and provenance. 10 oz package, 1 cup serving, 2 servings per package gives the expected grams per millilitre; a 30 oz ingredient resolves to 6 servings and 600 kcal off the *selected* row rather than an arbitrary first volume row (`forIngredient`'s package branch scales `packageServing.macros`); signed quantities scale signed while the stored package amount stays positive; a zero-calorie food still derives a density because nothing divides by energy; null minor nutrients stay null through `scaledBy`.
- Staleness detection covers a changed package amount, a changed serving amount, a different selected id and a removed serving, and is id-based so reordering `servingOptions` is harmless. `withPackSize` in `pack_size_queue.dart` deliberately preserves a now-stale relation so `hasStalePackageNutrition` can ask for a review rather than silently reconfirming or discarding.
- Unknown record versions never activate and round-trip verbatim through `toJson`; a non-finite version parses to -1 without throwing; `basis` other than `as_packaged` never activates; a count-unit serving and a fluid-ounce package are both rejected.
- Precedence order in `forIngredient` matches R12: direct same-kind serving, then the food's own density, then the package relationship (gated on the food having no own density), then the generic name table. The generic table is never reached before the package relationship.
- Immutability after the food changes. `_log` passes a null qualifier for an already-logged entry; `MealPlanEntry.log` falls back to the frozen value; `logEntry` preserves the original `loggedAt`; `PlanMapper` writes and reads `uses_approximate_package_nutrition`, lists it in `_snapshotKeys` so it is not duplicated into `unreadFields`, and reads an absent key as false. `MacroSnapshot` equality and `hashCode` include it. The recipe-level flag propagates through `IngredientMacros.usesApproximatePackage` to `RecipeMacros.usesApproximatePackageNutrition` and on to the sheet's note.
- Sync semantics. `packageNutritionFrom` and `massDisplayModeFrom` distinguish an omitted key from an explicit null via `containsKey`; `library_sync.pull` supplies `existing` from the local store for foods, so an old-client payload preserves both fields, and `hasEnded(pass)` is checked before each apply so an abandoned scope cannot write. `FoodMapper.toJson` always states both keys, which is how this build declares intent.
- R6 display. `_imperialMassDecimal` keeps 14.5, 15.25 and 28 at two trimmed decimals (max error 0.005) instead of rounding above ten; a value under 0.01 stays non-zero via `_significantDecimal`; `formatAsAuthored` keeps authored precision; `UnitConverter.normalise` returns mass untouched, so a display choice is never baked into `preferredUnit`. Pluralisation reads the displayed magnitude, not the raw value.
- Editable values are not round-tripped through a display formatter: `_PortionStepper._commit` parses the same rounded text it displayed, so an unchanged unfocus writes nothing; only typing or stepping moves `_amountBasis` and the stored portion.
- Local schema. v29 is the next version after v28, both columns are added with `_addColumnIfMissing`, `mass_display_mode` is non-null defaulting to automatic and `package_nutrition` is nullable text, and no branch rebuilds `foods` via `TableMigration`, so the new columns cannot be re-created by a lower-numbered step.
- Scan lifecycle. No auto-read on selection; `read` is one deliberate combined call in a fixed back-then-front order; a failure keeps both images for retry and a success drops the originals before publishing; the 5 MiB per-image guard precedes the upload and two slots cannot exceed the server aggregate; `onDispose` bumps the generation and clears both slots. Parser guards are correct: `_positiveCount` rejects zero, negative and non-finite counts, `_basis` clamps to the four known values, `_pack` and `_serving` drop half-read amounts and unknown units rather than defaulting them.

## Pre-existing versus introduced

Introduced by this work: B2, B3, B4, M5, M6, M7, M9, L11, and the readiness half of B1 (the unchecked density is old, but R12's new precedence is what turns it into a fallback blocker as well as a NaN source).

Pre-existing and unchanged in behaviour: the raw `gramsPerMillilitre` field itself, `crossKind`'s null-only density check, L10 and L12.
