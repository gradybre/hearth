import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';

/// Merging a photographed label into a draft, when the photos do not say
/// everything (spec §5.5, R9–R13).
///
/// The numbers are transcribed from a printed package: Great Value Chopped
/// Onions, NET WT 10 OZ (284 g), "about 3.5 servings per container", serving
/// 2/3 cup (85 g), 35 kcal, 1 g protein, 8 g carbohydrate, 0 g fat, 1 g fibre,
/// 0 mg sodium, 0 mg cholesterol. No photograph is stored in the repository
/// and nothing below reads one — these are synthetic readings carrying those
/// numbers, and where a reading states something the front of a package could
/// not state, the comment says it is synthetic rather than observed.
void main() {
  /// The panel and the front, read together.
  ///
  /// The cup and the gram figure are both printed for the one serving, and
  /// between them they are the only statement of how dense chopped onion is —
  /// which is exactly what a recipe measured in cups needs from a package
  /// sold by weight. The count and its "about" come off the panel.
  LabelReading bothPhotos() => LabelReading(
    name: 'Chopped Onions',
    brand: 'Great Value',
    packageSize: Quantity.of(10, Units.ounce),
    servingsPerContainer: 3.5,
    servingsApproximate: true,
    packageBasis: 'as_packaged',
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
      LabelServing(
        amount: 85,
        unitId: 'g',
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

  /// Only the front of the package was photographed.
  ///
  /// The net contents and nothing else — no panel, so no servings, no count,
  /// and a basis nobody could read. That is what a front-of-package read
  /// actually comes back with, and a fixture that quietly added a servings
  /// count to it would be testing an invention.
  LabelReading packageOnly() => LabelReading(
    servings: const <LabelServing>[],
    name: 'Chopped Onions',
    brand: 'Great Value',
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{'package_amount': 'package'},
  );

  /// The same front-of-package read, but the reply has also volunteered a
  /// generic 100 g row that no photographed panel supplied.
  ///
  /// Its provenance says as much: `field_sources.servings` is 'package'. The
  /// gate above this — the request's own intent — is what stops the forged
  /// and the unprovenanced cases; this is the draft's own defensive check
  /// for the one thing a reading states outright.
  LabelReading packageOnlyWithInventedNutrition() => LabelReading(
    servings: const <LabelServing>[
      LabelServing(
        amount: 100,
        unitId: 'g',
        kcal: 40,
        proteinG: 1.1,
        carbG: 9.3,
        fatG: 0.1,
      ),
    ],
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{
      'package_amount': 'package',
      'servings': 'package',
    },
  );

  /// The onion panel as somebody would have it in the editor already.
  ///
  /// The gram row deliberately leaves cholesterol blank: unknown and stated
  /// zero are different facts, and a photo must lose neither.
  FoodDraft onionRows() => const FoodDraft(
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
        sodium: '0',
        cholesterol: '0',
      ),
      ServingDraft(
        id: 'serving-g',
        amount: '85',
        unitId: 'g',
        kcal: '35',
        protein: '1',
        carbs: '8',
        fat: '0',
        fiber: '1',
        sodium: '0',
      ),
    ],
  );

  group('a package-only read', () {
    test('does not leave the 100 g starter standing as a serving', () {
      // The starter is Hearth's own opening default, not something a photo
      // said. A read that supplied package facts but no panel must not leave
      // it on screen looking like a transcribed serving.
      final FoodDraft merged = FoodDraft.blank().withLabel(packageOnly());

      expect(
        merged.servings.where((ServingDraft s) => s.isUntouchedStarter),
        isEmpty,
        reason: 'a panel-less read must not present 100 g as extracted',
      );
      expect(
        merged.servings.any(
          (ServingDraft s) => s.unitId == 'g' && s.amountValue == 100,
        ),
        isFalse,
      );
    });

    test('still applies the package facts it did read', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(packageOnly());

      expect(merged.packSize, '10 oz');
      expect(merged.name, 'Chopped Onions');
      expect(merged.brand, 'Great Value');
    });

    test('invents no servings-per-package count', () {
      // The front of a package does not print one. Working one out from a
      // net weight does not fail loudly — it silently converts wrongly.
      final FoodDraft merged = FoodDraft.blank().withLabel(packageOnly());

      expect(merged.servingsPerPackage, isEmpty);
      expect(merged.packageServingId, isNull);
    });
  });

  group('a package-only read over existing nutrition', () {
    test('leaves every existing row exactly as it was', () {
      final FoodDraft existing = onionRows();
      final FoodDraft merged = existing.withLabel(
        packageOnlyWithInventedNutrition(),
      );

      // Ids, units, amount text and all seven nutrients — compared whole,
      // because a package read has no business touching any of them.
      expect(merged.servings, existing.servings);
    });

    test('surfaces the dropped nutrition rather than saying nothing', () {
      final FoodDraft merged = onionRows().withLabel(
        packageOnlyWithInventedNutrition(),
      );

      expect(
        merged.packageReviewNotes,
        isNotEmpty,
        reason: 'nutrition that was not used has to be reviewable',
      );
    });

    test('the package facts still land', () {
      final FoodDraft merged = onionRows().withLabel(
        packageOnlyWithInventedNutrition(),
      );

      expect(merged.packSize, '10 oz');
    });

    test('does not preselect a serving it has no count for', () {
      // A pre-selection with no servings-per-package beside it puts a red
      // 'Servings per package needs a positive number' under a field nobody
      // touched. The package amount and the entered cup serving are both
      // still here to be paired by hand, which is the useful half.
      final FoodDraft merged = onionRows().withLabel(
        packageOnlyWithInventedNutrition(),
      );

      expect(merged.packageServingId, isNull);
      expect(merged.hasEnteredPackageFields, isFalse);
      expect(merged.packageNutritionError, isNull);
      expect(merged.toFood().packageNutrition, isNull);
    });

    test('survives a save and a reopen with every value intact', () {
      final FoodDraft merged = onionRows().withLabel(
        packageOnlyWithInventedNutrition(),
      );
      final Food saved = merged.toFood();
      final FoodDraft reopened = FoodDraft.fromFood(saved);

      expect(reopened.servings.map((ServingDraft s) => s.id), <String>[
        'serving-cup',
        'serving-g',
      ]);
      expect(reopened.servings.first.unitId, 'cup');
      expect(reopened.servings.first.amount, '2/3');
      expect(reopened.servings.first.kcal, '35');
      expect(reopened.servings.first.fiber, '1');
      // A stated zero stays a stated zero.
      expect(reopened.servings.first.sodium, '0');
      expect(reopened.servings.first.cholesterol, '0');
      // And an unknown stays unknown.
      expect(reopened.servings.last.cholesterol, isEmpty);
      expect(reopened.servings.last.unitId, 'g');
      expect(reopened.servings.last.amount, '85');
      expect(reopened.packSize, '10 oz');
    });
  });

  group('nutrition with no provenance at all', () {
    test('is trusted, because an older server sends none', () {
      // Treating silence as "this came off the package" would break every
      // read made against a server that predates the gate.
      final FoodDraft merged = onionRows().withLabel(
        const LabelReading(
          servings: <LabelServing>[
            LabelServing(amount: 1, unitId: 'tbsp', kcal: 5),
          ],
        ),
      );

      expect(merged.servings, hasLength(3));
      expect(merged.servings.last.unitId, 'tbsp');
    });
  });

  group('a row somebody started but has not finished', () {
    test('survives a read that returns servings of its own', () {
      // A portion typed with the macros still to come is work in progress,
      // not an empty slot to be cleared out from underneath.
      const FoodDraft partial = FoodDraft(
        name: 'Great Value Chopped Onions',
        servings: <ServingDraft>[
          ServingDraft(id: 'serving-cup', amount: '2/3', unitId: 'cup'),
        ],
      );

      final FoodDraft merged = partial.withLabel(bothPhotos());

      expect(
        merged.servings.any((ServingDraft s) => s.id == 'serving-cup'),
        isTrue,
        reason: 'an existing row, and its id, must not be deleted by a photo',
      );
    });

    test('and a portion already here is not rewritten under it', () {
      const FoodDraft partial = FoodDraft(
        name: 'Great Value Chopped Onions',
        servings: <ServingDraft>[
          ServingDraft(
            id: 'serving-cup',
            amount: '2/3',
            unitId: 'cup',
            kcal: '30',
          ),
        ],
      );

      final FoodDraft merged = partial.withLabel(bothPhotos());
      final ServingDraft cup = merged.servings.firstWhere(
        (ServingDraft s) => s.id == 'serving-cup',
      );

      expect(cup.kcal, '30');
      expect(
        merged.packageReviewNotes,
        isNotEmpty,
        reason: 'a disagreement is worth saying out loud',
      );
    });
  });

  group('both photos read cleanly', () {
    test('keeps both printed portions and invents no 100 g row', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(bothPhotos());

      expect(merged.servings, hasLength(2));
      expect(
        merged.servings.map((ServingDraft s) => s.unitId).toSet(),
        <String>{'cup', 'g'},
      );
      expect(merged.servings.first.amountValue, closeTo(2 / 3, 0.01));
      expect(merged.servings.last.amountValue, 85);
      expect(
        merged.servings.any(
          (ServingDraft s) => s.unitId == 'g' && s.amountValue == 100,
        ),
        isFalse,
      );
      expect(
        merged.servings.every((ServingDraft s) => !s.isUntouchedStarter),
        isTrue,
      );
    });

    test('every row it adds has an id of its own from the start', () {
      // A package relationship links to a row by id, through every rebuild
      // between here and Save.
      final FoodDraft merged = FoodDraft.blank().withLabel(bothPhotos());

      final Set<String?> ids = merged.servings
          .map((ServingDraft s) => s.id)
          .toSet();
      expect(ids, hasLength(2));
      expect(ids.contains(null), isFalse);
    });

    test('carries the printed nutrients, zeros included', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(bothPhotos());
      final ServingDraft cup = merged.servings.first;

      expect(cup.kcal, '35');
      expect(cup.protein, '1');
      expect(cup.carbs, '8');
      expect(cup.fat, '0');
      expect(cup.fiber, '1');
      // A printed 0 is a reading. Blank would say nobody looked.
      expect(cup.sodium, '0');
      expect(cup.cholesterol, '0');
    });

    test('offers the package relationship without activating it', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(bothPhotos());

      expect(merged.packSize, '10 oz');
      expect(merged.servingsPerPackage, '3.5');
      expect(merged.packageServingsApproximate, isTrue);
      expect(merged.packageServingId, merged.servings.first.id);
      expect(merged.packageNutritionError, isNull);
      expect(merged.packageNutritionNeedsConfirmation, isTrue);
      // Nothing is in force until somebody confirms it.
      expect(merged.toFood().packageNutrition, isNull);
    });
  });

  group('a relationship somebody already reviewed', () {
    FoodDraft reviewed() => FoodDraft.blank()
        .copyWith(name: 'Great Value Chopped Onions')
        .withLabel(bothPhotos())
        .confirmPackageNutrition();

    test('is not re-opened by a front-of-package photo', () {
      // The basis is a fact about a panel, and a front-only read saw none.
      // Reporting 'unknown' must not reset an answer somebody already gave.
      final FoodDraft before = reviewed();
      expect(before.originalPackageNutrition, isNotNull);

      final FoodDraft after = before.withLabel(packageOnly());

      expect(after.packageLabelBasis, before.packageLabelBasis);
      expect(after.packageBasisAcknowledged, before.packageBasisAcknowledged);
      expect(
        after.originalPackageNutrition?.servingsPerPackage,
        before.originalPackageNutrition?.servingsPerPackage,
      );
      expect(after.servingsPerPackage, '3.5');
      expect(after.packageNutritionError, isNull);
    });
  });
}
