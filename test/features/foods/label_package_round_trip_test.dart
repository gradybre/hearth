import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';

/// What survives a package-only read once it has been through a save
/// (spec R10-R13).
///
/// The draft-level tests prove the merge; this proves the facts still hold
/// after the food has been written and reopened — the reviewed relationship,
/// the count it was reviewed against, the ids it is anchored to, and the
/// nutrition somebody entered by hand.
///
/// Transcribed Great Value Chopped Onions facts: NET WT 10 OZ, 2/3 cup
/// (85 g), 35 kcal, about 3.5 servings, item 694935141. No photograph is
/// stored in the repository and nothing here reads one.
void main() {
  /// Both faces: the panel's portion and the front's net contents.
  LabelReading panelAndFront() => LabelReading(
    name: 'Chopped Onions',
    packageSize: Quantity.of(10, Units.ounce),
    servingsPerContainer: 3.5,
    servingsApproximate: true,
    packageBasis: 'as_packaged',
    fieldSources: const <String, String>{'servings': 'nutrition'},
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

  /// The front of the package alone: net contents, no panel.
  LabelReading frontOnly({Object? link}) => LabelReading(
    servings: const <LabelServing>[],
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{'package_amount': 'package'},
    walmartLink: link == null
        ? const WalmartLinkReading.notFound()
        : WalmartLinkReading.fromJson(link),
  );

  Map<String, Object?> foundLink(String url) => <String, Object?>{
    'status': 'found',
    'url': url,
    'source': 'package',
  };

  /// A food with a confirmed package/nutrition relationship on it.
  FoodDraft reviewed() => FoodDraft.blank()
      .copyWith(name: 'Great Value Chopped Onions')
      .withLabel(panelAndFront())
      .confirmPackageNutrition();

  group('a confirmed relationship through a package-only read', () {
    test('the fixture saves as an active relationship', () {
      final Food saved = reviewed().toFood();

      expect(saved.packageNutrition?.isValid, isTrue);
      expect(saved.activePackageServing, isNotNull);
      expect(saved.packageNutrition!.servingsPerPackage, 3.5);
    });

    test('it is still active after a front read, a save and a reopen', () {
      final Food saved = reviewed().toFood();
      final FoodDraft afterFront = FoodDraft.fromFood(saved)
          .withLabel(frontOnly());
      final Food resaved = afterFront.toFood();

      expect(resaved.activePackageServing, isNotNull);
      expect(resaved.packageNutrition!.servingsPerPackage, 3.5);
      expect(resaved.packageNutrition!.isApproximate, isTrue);
      expect(
        resaved.activePackageServing!.id,
        saved.activePackageServing!.id,
        reason: 'the relationship is anchored by id, and the id is the same',
      );

      final FoodDraft reopened = FoodDraft.fromFood(resaved);
      expect(reopened.servingsPerPackage, '3.5');
      expect(reopened.packageNutritionNeedsConfirmation, isFalse);
      expect(reopened.hasStalePackageNutrition, isFalse);
    });

    test('and the nutrition somebody entered is untouched by it', () {
      final Food saved = reviewed().toFood();
      final Food resaved = FoodDraft.fromFood(saved)
          .withLabel(frontOnly())
          .toFood();

      expect(resaved.servingOptions, hasLength(1));
      final ServingOption serving = resaved.servingOptions.single;
      expect(serving.macros.kcal, 35);
      expect(serving.macros.proteinG, 1);
      expect(serving.macros.carbG, 8);
      expect(serving.macros.fiberG, 1);
      // A stated zero stays a stated zero.
      expect(serving.macros.sodiumMg, 0);
      expect(serving.amount.preferredUnit, Units.cup);
      expect(serving.label, '2/3 cup');
    });
  });

  group('the Walmart link a package photo read', () {
    test('fills an empty field', () {
      final FoodDraft merged = FoodDraft.blank()
          .copyWith(name: 'Chopped onions')
          .withLabel(
            frontOnly(link: foundLink('https://www.walmart.com/ip/694935141')),
          );

      expect(merged.toFood().walmartItemId, '694935141');
    });

    test('and never replaces a different one already entered', () {
      // A photo is evidence, not an authority — the same rule this merge
      // applies to a name, a brand and a package amount. The editor offers
      // the swap separately, against the reading it kept.
      final FoodDraft merged = FoodDraft.blank()
          .copyWith(name: 'Chopped onions', walmartItemId: '10450479')
          .withLabel(
            frontOnly(link: foundLink('https://www.walmart.com/ip/694935141')),
          );

      expect(merged.toFood().walmartItemId, '10450479');
    });
  });

  group('a draft restored from an older build', () {
    test('has no starter mark, and its row is kept', () {
      // Starter-ness cannot be inferred from the values: a saved 100 g row
      // with nothing on it is the commonest shape in the library. A draft
      // written before the mark existed is treated as the user's, which is
      // the safe direction to fail in.
      final FoodDraft legacy = FoodDraft.fromJson(<String, Object?>{
        'name': '',
        'servings': <Object?>[
          <String, Object?>{'amount': '100', 'unit_id': 'g', 'id': 'row'},
        ],
      });

      expect(legacy.servings.single.isStarter, isFalse);
      expect(legacy.servings.single.isUntouchedStarter, isFalse);
      expect(legacy.withLabel(frontOnly()).servings.single.id, 'row');
    });
  });
}
