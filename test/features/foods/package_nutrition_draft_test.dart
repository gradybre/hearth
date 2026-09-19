import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';

import '../../support/fixtures.dart';

/// The package/nutrition relationship on the food editor's draft
/// (spec R6, R9-R13): confirming it, changing it, losing it, and the
/// precision it must not quietly spend.
void main() {
  test('an overflowing package count explains why it cannot convert', () {
    const draft = FoodDraft(
      name: 'Corn',
      packSize: '10 oz',
      servingsPerPackage: '1e308',
      packageServingId: 'cup',
      servings: [
        ServingDraft(id: 'cup', amount: '1', unitId: 'cup', kcal: '100'),
      ],
    );
    expect(draft.packageNutritionError, contains('too large'));
    expect(draft.packageNutritionNeedsConfirmation, isFalse);
  });
  test('long Unicode capture notes cannot strand a reviewed relationship', () {
    final note = List.filled(200, '🍲').join();
    final draft = FoodDraft(
      name: 'Corn',
      packSize: '10 oz',
      servingsPerPackage: '2',
      packageServingId: 'cup',
      servings: const [
        ServingDraft(id: 'cup', amount: '1', unitId: 'cup', kcal: '100'),
      ],
      packageLabelBasis: 'prepared',
      packageBasisAcknowledged: true,
      packageReviewNotes: List.generate(6, (i) => '$i$note'),
    );
    final confirmed = draft.confirmPackageNutrition();
    expect(confirmed.originalPackageNutrition?.isValid, isTrue);
    final reopened = FoodDraft.fromFood(confirmed.toFood());
    expect(reopened.packageLabelBasis, 'prepared');
    expect(reopened.packageBasisAcknowledged, isTrue);
    expect(reopened.packageReviewNotes, isNotEmpty);
    for (final text in reopened.packageReviewNotes) {
      expect(text.runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
    }
  });

  test('manual escape keeps the existing draft untouched', () {
    final draft = FoodDraft.blank();
    expect(draft.withLabel(const LabelReading(servings: [])), same(draft));
  });
  test('photo field provenance survives confirm save and reopen', () {
    final draft = FoodDraft.blank()
        .withLabel(
          LabelReading(
            name: 'Corn',
            packageSize: Quantity.of(10, Units.ounce),
            servingsPerContainer: 2,
            packageBasis: 'as_packaged',
            fieldSources: const {
              'package_amount': 'package',
              'servings': 'nutrition',
            },
            servings: const [LabelServing(amount: 1, unitId: 'cup', kcal: 100)],
          ),
        )
        .confirmPackageNutrition();
    final saved = draft.toFood();
    expect(saved.activePackageServing, isNotNull);
    expect(FoodDraft.fromFood(saved).packageFieldSources, {
      'package_amount': 'package',
      'servings': 'nutrition',
    });
    expect(draft.packageNutritionUnitPreview, '1 cup = 5 oz');
  });

  FoodDraft cheddarDraft() => const FoodDraft(
    name: 'Shredded cheddar',
    packSize: '10 oz',
    servings: <ServingDraft>[
      ServingDraft(id: 'serving-cup', amount: '1', unitId: 'cup', kcal: '100'),
    ],
  );

  PackageNutrition relationOf({double count = 2}) => PackageNutrition.manual(
    servingsPerPackage: count,
    servingOptionId: 'serving-cup',
    servingAmount: Quantity.of(1, Units.cup),
    packageAmount: Quantity.of(10, Units.ounce),
  );

  Food cheddarFood({PackageNutrition? relation}) => aFood(
    'Shredded cheddar',
    packSize: Quantity.of(10, Units.ounce),
    servingOptions: <ServingOption>[
      aServing(
        id: 'serving-cup',
        amount: 1,
        unit: Units.cup,
        macros: const Macros(kcal: 100),
      ),
    ],
    packageNutrition: relation,
  );

  group('an optional entry never blocks the food', () {
    test('a half-filled package section still saves the food', () {
      final FoodDraft partial = cheddarDraft().withPackageField(
        servingsPerPackage: '2',
      );
      expect(partial.packageNutritionError, isNotNull);
      expect(partial.isValid, isTrue);
      expect(partial.packageNutritionNeedsConfirmation, isFalse);
      expect(partial.toFood().packageNutrition, isNull);
    });
  });

  group('confirming is its own step', () {
    test('a complete entry waits, then saves once confirmed', () {
      final FoodDraft ready = cheddarDraft().withPackageField(
        servingsPerPackage: '2',
        packageServingId: 'serving-cup',
      );
      expect(ready.packageNutritionError, isNull);
      expect(ready.packageNutritionNeedsConfirmation, isTrue);
      // Not in effect until somebody says so.
      expect(ready.toFood().packageNutrition, isNull);
      expect(
        ready.packageNutritionPreview,
        '1 package (10 oz) = 2 servings = 2 cups',
      );

      final FoodDraft confirmed = ready.confirmPackageNutrition();
      expect(confirmed.packageNutritionNeedsConfirmation, isFalse);
      expect(confirmed.packageNutritionReviewed, isTrue);
      final Food saved = confirmed.toFood();
      expect(saved.packageNutrition!.isValid, isTrue);
      expect(saved.activePackageServing, isNotNull);
    });

    test('a changed count does not take effect on its own', () {
      final FoodDraft confirmed = cheddarDraft()
          .withPackageField(
            servingsPerPackage: '2',
            packageServingId: 'serving-cup',
          )
          .confirmPackageNutrition();

      final FoodDraft changed = confirmed.withPackageField(
        servingsPerPackage: '4',
      );
      expect(changed.packageNutritionNeedsConfirmation, isTrue);
      // The old record is preserved rather than quietly rewritten under a
      // number nobody reviewed.
      expect(changed.toFood().packageNutrition!.servingsPerPackage, 2);

      expect(
        changed
            .confirmPackageNutrition()
            .toFood()
            .packageNutrition!
            .servingsPerPackage,
        4,
      );
    });

    test('the selected serving has to be a volume', () {
      final FoodDraft draft =
          const FoodDraft(
            name: 'Beef',
            packSize: '1 lb',
            servings: <ServingDraft>[
              ServingDraft(id: 'serving-oz', amount: '4', unitId: 'oz'),
            ],
          ).withPackageField(
            servingsPerPackage: '4',
            packageServingId: 'serving-oz',
          );

      expect(draft.packageNutritionError, isNotNull);
      expect(draft.packageNutritionNeedsConfirmation, isFalse);
      expect(draft.confirmPackageNutrition().originalPackageNutrition, isNull);
    });

    test('a basis warning has to be answered first', () {
      final FoodDraft flagged = cheddarDraft()
          .withPackageField(
            servingsPerPackage: '2',
            packageServingId: 'serving-cup',
          )
          .copyWith(
            packageReviewNotes: const <String>[
              'The label describes a "drained" amount, which needs manual '
                  'confirmation before it can be used to convert between '
                  'weight and servings.',
            ],
          );

      expect(flagged.packageNutritionError, isNotNull);
      expect(
        flagged.confirmPackageNutrition().originalPackageNutrition,
        isNull,
      );

      final FoodDraft acknowledged = flagged.copyWith(
        packageBasisAcknowledged: true,
      );
      expect(acknowledged.packageNutritionError, isNull);
      expect(
        acknowledged.confirmPackageNutrition().originalPackageNutrition,
        isNotNull,
      );
    });

    test('removing it is explicit, and clears the fields with it', () {
      final FoodDraft confirmed = cheddarDraft()
          .withPackageField(
            servingsPerPackage: '2',
            packageServingId: 'serving-cup',
          )
          .confirmPackageNutrition();

      final FoodDraft cleared = confirmed.clearPackageNutrition();
      expect(cleared.originalPackageNutrition, isNull);
      expect(cleared.servingsPerPackage, isEmpty);
      expect(cleared.packageServingId, isNull);
      expect(cleared.packageNutritionNeedsConfirmation, isFalse);
      expect(cleared.toFood().packageNutrition, isNull);
    });
  });

  group('a saved relationship survives unrelated edits', () {
    test('renaming keeps it, and asks for nothing', () {
      final FoodDraft reopened = FoodDraft.fromFood(
        cheddarFood(relation: relationOf()),
      );
      expect(reopened.packageNutritionReviewed, isTrue);
      expect(reopened.packageNutritionNeedsConfirmation, isFalse);
      expect(reopened.hasStalePackageNutrition, isFalse);

      final FoodDraft renamed = reopened.copyWith(name: 'Sharp cheddar');
      expect(renamed.isValid, isTrue);
      expect(renamed.packageNutritionNeedsConfirmation, isFalse);
      expect(renamed.toFood().packageNutrition, isNotNull);
    });

    test('editing the package makes it stale without blocking a save', () {
      final FoodDraft edited = FoodDraft.fromFood(
        cheddarFood(relation: relationOf()),
      ).copyWith(packSize: '12 oz');

      expect(edited.hasStalePackageNutrition, isTrue);
      // Stale is not pending: the facts it was reviewed against changed,
      // and that must never stand between somebody and Save.
      expect(edited.packageNutritionNeedsConfirmation, isFalse);
      expect(edited.isValid, isTrue);

      final Food saved = edited.toFood();
      expect(saved.packageNutrition, isNotNull);
      expect(saved.hasStalePackageNutrition, isTrue);
      expect(saved.activePackageServing, isNull);
    });
  });

  group('precision', () {
    test('an untouched package amount keeps its exact value', () {
      final Food original = aFood(
        'Canned beans',
        packSize: Quantity.of(15.25, Units.ounce),
      );
      final FoodDraft reopened = FoodDraft.fromFood(original);
      expect(
        reopened.toFood().packSize!.canonicalAmount,
        original.packSize!.canonicalAmount,
      );
    });

    test('an edited package amount is reparsed normally', () {
      final Food original = aFood(
        'Canned beans',
        packSize: Quantity.of(15.25, Units.ounce),
      );
      final FoodDraft edited = FoodDraft.fromFood(original)
          .copyWith(packSize: '28 oz');
      expect(edited.toFood().packSize, Quantity.of(28, Units.ounce));
    });

    test('an untouched serving amount keeps its exact value', () {
      final Food original = aFood(
        'Yogurt',
        servingOptions: <ServingOption>[
          aServing(
            id: 's',
            amount: 15.25,
            unit: Units.ounce,
            macros: const Macros(kcal: 100),
          ),
        ],
      );
      final FoodDraft reopened = FoodDraft.fromFood(original);
      expect(
        reopened.toFood().servingOptions.single.amount.canonicalAmount,
        original.servingOptions.single.amount.canonicalAmount,
      );
    });
  });

  group('a lookup match', () {
    test('keeps the pack size and weight display, and remaps the link', () {
      final Food looked = Food(
        id: 'off:5000157024671',
        name: 'Cheddar',
        source: FoodSource.openFoodFacts,
        packSize: Quantity.of(10, Units.ounce),
        massDisplayMode: MassDisplayMode.ounces,
        packageNutrition: relationOf(),
        servingOptions: <ServingOption>[
          aServing(
            id: 'serving-cup',
            amount: 1,
            unit: Units.cup,
            macros: const Macros(kcal: 100),
          ),
        ],
      );

      final FoodDraft draft = FoodDraft.fromLookup(looked);
      expect(draft.packSize, isNotEmpty);
      expect(draft.massDisplayMode, MassDisplayMode.ounces);

      final String? newId = draft.servings.single.id;
      expect(newId, isNotNull);
      expect(newId, isNot('serving-cup'));
      expect(draft.packageServingId, newId);

      final Food saved = draft.toFood();
      expect(saved.activePackageServing?.id, newId);
    });
  });

  group('a photographed label', () {
    test('records that the package facts came off a photo', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(
        LabelReading(
          servings: const <LabelServing>[],
          packageSize: Quantity.of(24, Units.ounce),
          servingsPerContainer: 6,
        ),
      );

      expect(merged.packageNutritionSource, PackageNutritionSource.photos);
      expect(merged.servingsPerPackage, '6');
      // The photo's own canonical amount, not a reparse of its text.
      expect(merged.originalPackSize, Quantity.of(24, Units.ounce));
    });

    test('typing over a photographed fact makes the record mixed', () {
      final FoodDraft merged = FoodDraft.blank()
          .withLabel(
            LabelReading(
              servings: const <LabelServing>[],
              packageSize: Quantity.of(24, Units.ounce),
              servingsPerContainer: 6,
            ),
          )
          .withPackageField(servingsPerPackage: '4');

      expect(merged.packageNutritionSource, PackageNutritionSource.mixed);
    });

    test('a prepared basis needs a fresh acknowledgement', () {
      final FoodDraft merged = FoodDraft.blank()
          .copyWith(packageBasisAcknowledged: true)
          .withLabel(
            LabelReading(
              servings: const <LabelServing>[],
              packageSize: Quantity.of(24, Units.ounce),
              servingsPerContainer: 6,
              packageBasis: 'prepared',
            ),
          );

      expect(merged.packageBasisAcknowledged, isFalse);
      expect(merged.packageReviewNotes, isNotEmpty);
    });
  });

  group('a package that disagrees with the food itself', () {
    test('is flagged, and changes nothing', () {
      final FoodDraft draft = const FoodDraft(
        name: 'Cheddar',
        packSize: '10 oz',
        servings: <ServingDraft>[
          ServingDraft(id: 'c', amount: '1', unitId: 'cup', kcal: '100'),
          ServingDraft(id: 'g', amount: '100', unitId: 'g', kcal: '400'),
        ],
      ).withPackageField(servingsPerPackage: '2', packageServingId: 'c');

      expect(draft.ownGramsPerMillilitre, isNotNull);
      expect(draft.packageGramsPerMillilitre, isNotNull);
      expect(draft.packageDensityConflictNote, isNotNull);
      // Still confirmable: a note is a note, not a refusal.
      expect(draft.packageNutritionError, isNull);
    });
  });

  group('a draft round-trips through its own JSON', () {
    test('every package field survives draft recovery', () {
      final FoodDraft confirmed = cheddarDraft()
          .withPackageField(
            servingsPerPackage: '2',
            packageServingId: 'serving-cup',
            packageServingsApproximate: true,
          )
          .confirmPackageNutrition();

      expect(FoodDraft.fromJson(confirmed.toJson()), confirmed);
    });
  });

  group('an explicit density is not lost by the editor', () {
    Food denseMilk({Quantity? pack}) => Food(
      id: 'milk',
      name: 'Milk',
      source: FoodSource.manual,
      gramsPerMillilitre: 1.03,
      packSize: pack,
      servingOptions: <ServingOption>[
        ServingOption(
          id: 'serving-cup',
          label: '1 cup',
          amount: Quantity.of(1, Units.cup),
          macros: const Macros(kcal: 100),
        ),
      ],
    );

    test('it survives a rename, a JSON round trip and a lookup', () {
      final FoodDraft draft = FoodDraft.fromFood(denseMilk());
      expect(draft.preservedDensity, 1.03);
      expect(draft.ownGramsPerMillilitre, 1.03);
      expect(
        draft.copyWith(name: 'Whole milk').toFood().gramsPerMillilitre,
        1.03,
      );
      expect(FoodDraft.fromJson(draft.toJson()).preservedDensity, 1.03);
      expect(FoodDraft.fromLookup(denseMilk()).preservedDensity, 1.03);
    });

    test('it is what a package relationship is compared against', () {
      final FoodDraft draft =
          FoodDraft.fromFood(denseMilk(pack: Quantity.of(10, Units.ounce)))
              .withPackageField(
                servingsPerPackage: '2',
                packageServingId: 'serving-cup',
              );
      expect(draft.packageGramsPerMillilitre, isNotNull);
      expect(draft.packageDensityConflictNote, isNotNull);
      // A note, not a refusal: both facts are kept as entered.
      expect(draft.packageNutritionError, isNull);
    });
  });

  group('a servings count reopens exactly as stored', () {
    test('a high-precision count is neither rewritten nor pending', () {
      final FoodDraft reopened = FoodDraft.fromFood(
        cheddarFood(relation: relationOf(count: 1.23456789)),
      );
      expect(reopened.servingsPerPackage, '1.23456789');
      expect(reopened.packageNutritionNeedsConfirmation, isFalse);
      expect(
        reopened.toFood().packageNutrition!.servingsPerPackage,
        1.23456789,
      );
    });

    test('a whole count reads as a whole number', () {
      expect(
        FoodDraft.fromFood(cheddarFood(relation: relationOf()))
            .servingsPerPackage,
        '2',
      );
    });
  });

  group('where the package facts came from', () {
    LabelReading front() => LabelReading(
      servings: const <LabelServing>[],
      packageSize: Quantity.of(24, Units.ounce),
    );
    LabelReading back() =>
        const LabelReading(servings: <LabelServing>[], servingsPerContainer: 6);

    test('two photo slots stay photos in either order', () {
      expect(
        FoodDraft.blank()
            .withLabel(back())
            .withLabel(front())
            .packageNutritionSource,
        PackageNutritionSource.photos,
      );
      expect(
        FoodDraft.blank()
            .withLabel(front())
            .withLabel(back())
            .packageNutritionSource,
        PackageNutritionSource.photos,
      );
    });

    test('a nutrition-only scan is photos, not manual', () {
      expect(
        FoodDraft.blank().withLabel(back()).packageNutritionSource,
        PackageNutritionSource.photos,
      );
    });

    test('typing over a scanned package or serving makes it mixed', () {
      final FoodDraft scanned = FoodDraft.blank()
          .withLabel(front())
          .withLabel(back());
      expect(scanned.packageNutritionSource, PackageNutritionSource.photos);
      expect(
        scanned.copyWith(packSize: '12 oz').packageNutritionSource,
        PackageNutritionSource.mixed,
      );
      expect(
        scanned
            .copyWith(
              servings: <ServingDraft>[
                ...scanned.servings,
                const ServingDraft(id: 'extra', amount: '1', unitId: 'cup'),
              ],
            )
            .packageNutritionSource,
        PackageNutritionSource.mixed,
      );
      // An unrelated edit changes nothing about where the facts came from.
      expect(
        scanned.copyWith(name: 'Cheddar').packageNutritionSource,
        PackageNutritionSource.photos,
      );
    });
  });

  group('a corrected prepared label keeps its capture facts', () {
    FoodDraft drainedScan() => cheddarDraft().withLabel(
      const LabelReading(
        servings: <LabelServing>[],
        servingsPerContainer: 2,
        packageBasis: 'drained',
      ),
    );

    test('it cannot activate before the basis is acknowledged', () {
      final FoodDraft scanned = drainedScan();
      expect(scanned.packageBasisAcknowledged, isFalse);
      expect(scanned.packageReviewNotes, isNotEmpty);
      expect(scanned.packageNutritionError, isNotNull);
      expect(
        scanned.confirmPackageNutrition().originalPackageNutrition,
        isNull,
      );
    });

    test('the basis and its notes survive a save and a reopen', () {
      final FoodDraft confirmed = drainedScan()
          .copyWith(packageBasisAcknowledged: true)
          .confirmPackageNutrition();
      expect(confirmed.originalPackageNutrition, isNotNull);
      // Kept, not cleared: these are the facts a correction is made from.
      expect(confirmed.packageReviewNotes, isNotEmpty);

      final Food saved = confirmed.toFood();
      expect(saved.activePackageServing, isNotNull);

      final FoodDraft reopened = FoodDraft.fromFood(saved);
      expect(reopened.packageLabelBasis, 'drained');
      expect(reopened.packageBasisAcknowledged, isTrue);
      expect(reopened.packageReviewNotes, isNotEmpty);
      expect(reopened.packageNutritionError, isNull);
      expect(reopened.packageNutritionNeedsConfirmation, isFalse);
    });

    test('a repeated read does not stack the same note twice', () {
      final FoodDraft twice = drainedScan().withLabel(
        const LabelReading(
          servings: <LabelServing>[],
          servingsPerContainer: 2,
          packageBasis: 'drained',
        ),
      );
      expect(
        twice.packageReviewNotes.toSet().length,
        twice.packageReviewNotes.length,
      );
    });
  });

  group('a record from a newer build', () {
    test('never activates, and never blocks a save', () {
      final Food future = cheddarFood(
        relation: PackageNutrition.fromJson(<String, dynamic>{
          'version': 99,
          'something_new': true,
        }),
      );
      final FoodDraft draft = FoodDraft.fromFood(future);
      expect(draft.isValid, isTrue);
      expect(draft.hasEnteredPackageFields, isFalse);
      expect(draft.packageNutritionNeedsConfirmation, isFalse);
      expect(draft.hasStalePackageNutrition, isFalse);

      final Food saved = draft.toFood();
      // Round-tripped verbatim rather than quietly deleted.
      expect(saved.packageNutrition, isNotNull);
      expect(saved.activePackageServing, isNull);
      expect(saved.hasStalePackageNutrition, isFalse);
    });
  });
}
