import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';

import '../../support/fixtures.dart';

/// Two questions a photographed read has to get right about rows and about
/// review (spec R10, R11).
///
/// Which row is Hearth's own opening default and may be replaced, and which
/// is somebody's work and may not — and when a reviewed answer about a panel
/// still describes the photos in hand.
///
/// The numbers are transcribed from a printed package: Great Value Chopped
/// Onions, NET WT 10 OZ, 2/3 cup (85 g), 35 kcal, 1 g protein, 8 g
/// carbohydrate, 0 g fat, 1 g fibre, 0 mg sodium, 0 mg cholesterol. No
/// photograph is stored in the repository and nothing here reads one.
void main() {
  /// The front of the package and nothing else: net contents, no panel, so no
  /// servings, no count, and a basis nobody could read.
  LabelReading frontOnly() => LabelReading(
    servings: const <LabelServing>[],
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{'package_amount': 'package'},
  );

  /// A drained panel, which is the case that has to be acknowledged before a
  /// relationship built from it can convert anything.
  LabelReading drainedPanel() => LabelReading(
    name: 'Chopped Onions',
    packageSize: Quantity.of(10, Units.ounce),
    servingsPerContainer: 3.5,
    servingsApproximate: true,
    packageBasis: 'drained',
    fieldSources: const <String, String>{
      'package_amount': 'package',
      'servings_per_container': 'nutrition',
      'servings': 'nutrition',
    },
    servings: const <LabelServing>[
      LabelServing(
        amount: 2 / 3,
        unitId: 'cup',
        kcal: 35,
        proteinG: 1,
        carbG: 8,
        fatG: 0,
        fiberG: 1,
        sodiumMg: 0,
        cholesterolMg: 0,
      ),
    ],
  );

  /// The onion panel as somebody already has it in the editor.
  FoodDraft onionCup({String sodium = '0', String cholesterol = '0'}) =>
      FoodDraft(
        name: 'Great Value Chopped Onions',
        servings: <ServingDraft>[
          ServingDraft(
            id: 'serving-cup',
            amount: '2/3',
            unitId: 'cup',
            kcal: '35',
            protein: '1',
            carbs: '8',
            fat: '0',
            fiber: '1',
            sodium: sodium,
            cholesterol: cholesterol,
          ),
        ],
      );

  /// The same portion, read again with only a minor nutrient different.
  LabelReading cupAgain({
    double? fiberG = 1,
    double? sodiumMg = 0,
    double? cholesterolMg = 0,
  }) => LabelReading(
    fieldSources: const <String, String>{'servings': 'nutrition'},
    servings: <LabelServing>[
      LabelServing(
        amount: 2 / 3,
        unitId: 'cup',
        kcal: 35,
        proteinG: 1,
        carbG: 8,
        fatG: 0,
        fiberG: fiberG,
        sodiumMg: sodiumMg,
        cholesterolMg: cholesterolMg,
      ),
    ],
  );

  group('whose row is it', () {
    test("a blank draft's starter gives way to a front-of-package read", () {
      final FoodDraft merged = FoodDraft.blank().withLabel(frontOnly());

      expect(
        merged.servings.where((ServingDraft s) => s.isUntouchedStarter),
        isEmpty,
      );
      expect(
        merged.servings.any(
          (ServingDraft s) => s.unitId == 'g' && s.amountValue == 100,
        ),
        isFalse,
      );
    });

    test("a barcode draft's starter does too", () {
      final FoodDraft merged = FoodDraft.forBarcode('0078742370385')
          .withLabel(frontOnly());

      expect(
        merged.servings.where((ServingDraft s) => s.isUntouchedStarter),
        isEmpty,
      );
      expect(merged.barcode, '0078742370385');
    });

    test('a starter somebody typed a minor nutrient into is theirs', () {
      // A stated zero is an answer, and it is the whole of what somebody has
      // entered so far. The four majors being blank does not make the row
      // untouched, and deleting it would take its id with it.
      for (final ServingDraft typed in <ServingDraft>[
        const ServingDraft(
          id: 'row',
          amount: '100',
          unitId: 'g',
          isStarter: true,
          fiber: '0',
        ),
        const ServingDraft(
          id: 'row',
          amount: '100',
          unitId: 'g',
          isStarter: true,
          sodium: '0',
        ),
        const ServingDraft(
          id: 'row',
          amount: '100',
          unitId: 'g',
          isStarter: true,
          cholesterol: '0',
        ),
      ]) {
        expect(
          typed.isUntouchedStarter,
          isFalse,
          reason: 'a minor nutrient is something somebody entered',
        );

        final FoodDraft merged = FoodDraft(
          name: '',
          servings: <ServingDraft>[typed],
        ).withLabel(frontOnly());

        expect(merged.servings.single.id, 'row');
      }
    });

    test('a saved 100 g row with no macros is never a starter', () {
      // The commonest shape in the library: a half-filled import. It looks
      // exactly like the opening default and is nothing of the kind.
      final Food imported = aFood(
        'Chopped onions',
        servingOptions: <ServingOption>[
          aServing(
            id: 'serving-100g',
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 0),
          ),
        ],
      );

      final FoodDraft merged = FoodDraft.fromFood(imported)
          .withLabel(frontOnly());

      expect(merged.servings.single.id, 'serving-100g');
      expect(merged.servings.single.isStarter, isFalse);
    });

    test('the marker survives the draft record, and still clears', () {
      final FoodDraft blank = FoodDraft.blank();
      expect(blank.servings.single.isStarter, isTrue);

      final FoodDraft restored = FoodDraft.fromJson(blank.toJson());
      expect(restored.servings.single.isStarter, isTrue);
      expect(restored, blank);
      expect(
        restored
            .withLabel(frontOnly())
            .servings
            .where((ServingDraft s) => s.isUntouchedStarter),
        isEmpty,
      );
    });

    test('an edit takes ownership of the row', () {
      final ServingDraft starter = FoodDraft.blank().servings.single;
      expect(starter.copyWith(kcal: '35').isStarter, isFalse);
      expect(starter.copyWith(sodium: '0').isStarter, isFalse);
    });
  });

  group('a portion already entered', () {
    test('keeps its minor nutrients, and the difference is said out loud', () {
      final FoodDraft merged = onionCup().withLabel(cupAgain(sodiumMg: 150));

      expect(merged.servings, hasLength(1));
      expect(merged.servings.single.sodium, '0');
      expect(
        merged.packageReviewNotes,
        isNotEmpty,
        reason: 'a nutrient read differently is worth a note',
      );
    });

    test('an unknown and a stated zero are different facts', () {
      // Blank means nobody said. A photo reading 0 is a reading. Neither
      // silently becomes the other.
      final FoodDraft merged = onionCup(cholesterol: '').withLabel(cupAgain());

      expect(merged.servings.single.cholesterol, isEmpty);
      expect(merged.packageReviewNotes, isNotEmpty);
    });

    test('an identical re-read says nothing at all', () {
      final FoodDraft merged = onionCup().withLabel(cupAgain());

      expect(merged.servings, hasLength(1));
      expect(merged.packageReviewNotes, isEmpty);
    });
  });

  group('a relationship somebody already reviewed', () {
    FoodDraft reviewed() => FoodDraft.blank()
        .copyWith(name: 'Great Value Chopped Onions')
        .withLabel(drainedPanel())
        .copyWith(packageBasisAcknowledged: true)
        .confirmPackageNutrition();

    test('the fixture itself is a confirmed, acknowledged relationship', () {
      final FoodDraft before = reviewed();
      expect(before.originalPackageNutrition?.isValid, isTrue);
      expect(before.packageBasisAcknowledged, isTrue);
      expect(before.packageLabelBasis, 'drained');
    });

    test('a front-of-package photo does not re-open it', () {
      // Nothing new was read about the panel, so the answer given about the
      // panel still stands.
      final FoodDraft before = reviewed();
      final FoodDraft after = before.withLabel(frontOnly());

      expect(after.packageBasisAcknowledged, isTrue);
      expect(after.packageLabelBasis, 'drained');
      expect(after.originalPackageNutrition, isNotNull);
      expect(after.packageNutritionError, isNull);
    });

    test('a new prepared panel has to be answered again', () {
      final FoodDraft before = reviewed();
      final FoodDraft after = before.withLabel(
        LabelReading(
          packageSize: Quantity.of(10, Units.ounce),
          servingsPerContainer: 3.5,
          packageBasis: 'prepared',
          fieldSources: const <String, String>{'servings': 'nutrition'},
          servings: const <LabelServing>[
            LabelServing(amount: 1, unitId: 'cup', kcal: 40),
          ],
        ),
      );

      expect(
        after.packageBasisAcknowledged,
        isFalse,
        reason: 'a new panel is new evidence, not the evidence already agreed',
      );
      expect(after.packageNutritionError, isNotNull);
      // The record itself is preserved; it is the conversion that waits.
      expect(after.originalPackageNutrition, isNotNull);
    });

    test('a count that disagrees has to be answered again', () {
      final FoodDraft before = reviewed();
      final FoodDraft after = before.withLabel(
        LabelReading(
          servings: const <LabelServing>[],
          packageSize: Quantity.of(10, Units.ounce),
          servingsPerContainer: 4,
          packageBasis: 'unknown',
          fieldSources: const <String, String>{'package_amount': 'package'},
        ),
      );

      expect(after.packageBasisAcknowledged, isFalse);
      expect(after.servingsPerPackage, '3.5');
      expect(after.originalPackageNutrition, isNotNull);
    });
  });
}
