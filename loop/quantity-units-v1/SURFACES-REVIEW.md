# D4 surfaces review - quantity units v1

Independent read-only review. No shell, no build, no tests, no database, no images. Nothing here is an executed check; every item is either read-verified against the supplied source or listed as unverifiable.

**Out of scope by instruction** (owned elsewhere): usable-density / raw-shape / outgoing-invalid domain repair; logging and scan-controller review; small-screen render evidence; new real-DB save/reopen tests; and the known pending item that a manual pack or serving edit after a photo read must re-mark the source as mixed. That last one is still present in the source: the editor writes the package amount through plain `copyWith(packSize:)` rather than `withPackageField`, so the source stays `photos`.

## High

### H1 - a reviewed package relation can override a directly stated mass/volume pair

`Food.ownGramsPerMillilitre` is explicit density ?? `_densityFromServings()`, and `_bridge` skips any serving whose macro scale is <= 0. A food that states both 1 cup and 240 g but carries zero macros on both rows therefore has no own density, so `effectiveGramsPerMillilitre` falls through to `packageGramsPerMillilitre`. R12 is explicit that a package relation fills a missing link and must not silently override a directly stated mass serving. `packageDensityConflictsWithOwn` returns false in the same case because own is null, so neither the precedence nor the 5% warning fires.

Repro: construct a `Food` with serving options [1 cup, all macros 0] and [240 g, all macros 0] plus a valid `packageNutrition` implying 5 oz per cup, then read `effectiveGramsPerMillilitre` and `packageDensityConflictsWithOwn`. This reaches recipe nutrition, shopping cross-kind consolidation and on-hand subtraction at once, because all three route through that one getter.

Narrow fix: derive own density from a mass/volume serving pair by amount when the macro bridge is unavailable, or at minimum treat the presence of both kinds as a conflict signal.

### H2 - an acknowledged prepared or drained label is stored as as_packaged, evidence discarded

`FoodDraft.confirmPackageNutrition` always builds `PackageNutrition.manual(...)` with the default basis `asPackaged`, and then sets `packageReviewNotes: const <String>[]`. So when `withLabel` flagged a non-as_packaged basis and the user ticked `packageBasisAcknowledged`, the saved record asserts as-packaged, the note explaining why it needed confirming is deleted, and the acknowledgement itself is draft-only - `packageBasisAcknowledged` never reaches `toFood`. Reopening the food shows a clean, apparently verified relation with no trace that it came off a drained or prepared panel. R9 requires that prepared and drained interpretations never activate automatically and that original facts are preserved for correction.

Repro: a photo read returning `package_basis` of `drained`; tick the acknowledgement; confirm; save; reopen - no warning, no note, basis as_packaged.

Narrow fix: carry the acknowledged basis into the record or a companion flag, and keep the uncertainty notes rather than clearing them on confirm.

## Medium

**M1 - basket count disagrees with the ticked rows.** `_LineTile` renders from `ShoppingLineResolver.resolve(...).isChecked`, but `_Body` counts `lines.where((l) => l.checked)`. If `isChecked` is derived from coverage, a row can render ticked and struck through while the header still says none in the basket; tapping it then writes `ticked(!done)` from the derived value onto stored state. Repro: a line with on-hand in a different kind that a density converts to cover the need.

**M2 - the amount sheet edits in a different unit from the row.** `_edit` passes the raw `line`; `_AmountSheetState._unit` comes from `line.fullAmount?.preferredUnit`, while the row shows the settled and resolved amount. A row reading 3 x 24 oz can open a sheet whose fields are labelled in the authored volume unit, and an on-hand figure typed there is stored in that unit. R5 wants every surface to agree and R6 wants editors to reflect the entered unit. Repro: a recipe authored in cups matched to a food with an oz pack.

**M3 - the combined ingredient view drops raw pack evidence.** `_IngredientRow` and `StepAmounts` both pass `rawSources: [rawText]` to `FoodQuantityFormat.format`; `_CombinedRow` passes only `food`. By section and Combined can therefore resolve a different display unit for the same ingredient. Repro: a grouped recipe with a 2 (28 oz) cans line, toggling the segmented control.

**M4 - the read-label sheet can pop twice.** On `LabelScanDone` the sheet schedules `Navigator.pop` in a post-frame callback on every build, guarded only by `mounted`. Two builds inside one frame schedule two callbacks, and the first pop does not clear `mounted` before the second runs in the same flush, so the editor route can be popped as well. A one-shot flag is the whole fix.

**M5 - the two-slot photo flow is missing preview and roles.** `_Slot` shows only the words Photo selected; there is no thumbnail, so the one thing the pair review exists for - confirming both photos are the same product and that front and back went into the right slots - cannot be done visually. `EdgeFunctionLabelReader.read` also sends a flat images array with no role metadata, and the client parses no per-field provenance, so `packageNutritionSource` is inferred locally at manual/photos/mixed granularity only. R11 asks for preview and for capture metadata recording field origin.

**M6 - the basis warning fires on almost every label.** `withLabel` adds the manual-confirmation note whenever `reading.packageBasis != 'as_packaged'`, and both the server default and `EdgeFunctionLabelReader._basis` fall back to `unknown` when the panel says nothing, which is the normal case. Every ordinary scan therefore demands the preparation tick. That is the warning-that-cannot-be-cleared failure mode this codebase already argues against in `Food.isZeroCalorie`. Distinguish an unstated basis from an explicitly prepared or drained one.

**M7 - a confirmed relation goes stale on a unit-only change.** `PackageNutrition._sameQuantity` requires identical `preferredUnit`, so re-expressing a 10 oz pack as 283.5 g, or any mapper or sync round trip that drops or normalises `preferredUnit`, invalidates a human-confirmed record. R13 asks for tolerance on the number with agreement on id and dimension. Because the mappers were not supplied, round-trip fidelity of `preferredUnit` is now load-bearing and unverified.

**M8 - Use this one silently discards a just-reviewed relation.** In `_save`, choosing an existing duplicate pops that id and drops the draft; the scanned package amount, serving count and confirmed relation are thrown away without a word, and nothing is applied to the chosen food. R11 asks for scan values to be shown as proposals alongside the existing food.

**M9 - only mass packages with volume servings are supported, and the message blames the user.** `packageNutritionError` requires the pack to be mass and the serving to be volume, and reports that the package amount needs a weight. A 64 fl oz liquid with a 1 cup serving, or a mass serving with a volume package, is the mirror of the supported case, and R9 says the reverse conversion uses the same relation. At minimum the copy should say the pairing is unsupported rather than implying bad input.

**M10 - a photo-suggested serving raises an error the user did not cause, and cannot be un-selected.** `withLabel` may pre-select `packageServingId` when exactly one volume row exists; if no count was read, `hasEnteredPackageFields` is true and `packageNutritionError` reports that servings per package needs a positive number. The nutrition serving dropdown has no none entry and its `onChanged` never delivers null, and the Remove package/nutrition link button renders only when `originalPackageNutrition != null` - so for an unconfirmed suggestion there is no control matching the save-time text that invites the user to remove the link. Clearing the count text is the only escape.

## Low

- **L1** `ShoppingRepository.removeSource` settles surviving lines with no `food`, then `replace` immediately re-settles them with the library. Harmless today because `settle` recomputes from the asks, but the intermediate call is misleading and one refactor away from being the persisted result.
- **L2** `packageReviewNotes` accumulate across repeated reads with no de-duplication, and are then cleared wholesale by `confirmPackageNutrition`, taking the photo uncertainty notes with them.
- **L3** `PackageNutrition.isValid` rejects an otherwise well-formed v1 record whose `rawJson` lacks `is_approximate`, while `fromJson` already defaults it to false. An older or partial row deactivates rather than reading as exact.
- **L4** `CookAlongScreen` snapshots the recipe but watches `foodLibraryProvider` live, so a household member changing a food mass display mode shifts units under a cook mid-step - the same class of surprise the recipe snapshot exists to prevent.
- **L5** `repointFood` rewrites and re-enqueues every line on the list in order to re-settle one.
- **L6** the amount sheet Reset clears both the buy override and the on-hand figure; those are independent decisions.
- **L7** `EdgeFunctionLabelReader._ask` reports Take a photo of the label first for an empty image list, even when the user supplied only a front-of-pack intent.

## Unverifiable from the supplied source

Listed so they are not mistaken for passes.

- The whole R13 persistence half: migration and drift version, mappers, sync payloads, the upsert function, omitted key versus explicit null, the 4 KiB cap, and the atomic serving-membership check. None of those files were supplied. Largest remaining risk.
- `Quantity` equality. `withLabel` compares `resolvedPackSize != reading.packageSize`; without value equality that conflict note fires on every read where a pack is already entered.
- `QuantityFormat.formatAmount` rounding in the amount sheet, `FoodQuantityFormat.format` raw-source precedence, and `UnitConverter.normalise` behaviour for a metric pack under an imperial system.
- `ShoppingLine.toBuy`, `fullAmount`, `isChecked`, `PackDisplay` and `CartQuantity`, so pack counting, shortfall text and on-hand subtraction are unchecked here.
- `MacroCalculator.usesApproximatePackageNutrition`, snapshot persistence of the qualifier, the portion selector same-kind audit, and planned or logged food conversion.
- Label scan controller: in-flight cancellation on dismiss, generation guarding, and the 5 MiB per-image and aggregate limits.
- Whether `DropdownButtonFormField.initialValue` updates on a programmatic change - clearing, or a photo suggestion - rather than only at first build.

## Scope coverage against the plan

- Food editor: covered.
- Recipes: grouped, combined, scaled, step amounts and cook-along all take a `foods` snapshot; the gap is M3.
- Shopping: list, amount sheet, rebuild, contributions, merge and export all route through the resolver or `settle`; gaps are M1 and M2.
- Photo nutrition input: present but partial - M5 and M6.
- Not evidenced at all: portion selector, planned and logged food nutrition, log snapshots, and the persistence layer.

## Read-verified and looking right

Shopping provenance survives add, remove and food-metadata change. Contributions store authored quantities in source mode - `sourceMode: true` in the builder and in `addRecipe`, `crossKind: false` in `merge` - and every write and read path re-derives the total against the current food, via `ShoppingRepository.replace` and `_settled`, `ShoppingListMerge.into`, and `ShoppingLineResolver._settled`. Adding, changing or removing a package relation therefore recomputes rather than fossilising an old conversion. Legacy rows keep only their stored total, which the code documents as the R8 limit rather than inventing a lost unit. `_rawPackageUnit` is applied as a display hint only and never touches a canonical amount. Untouched editor fields return their original `Quantity` rather than a reparse, in both `ServingDraft.resolvedAmount` and `_AmountSheetState._read`.
