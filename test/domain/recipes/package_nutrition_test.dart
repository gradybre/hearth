import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('PackageNutrition.manual (spec R9, R13)', () {
    test('10 oz package, 1 cup serving, 2 servings/package implies its own '
        'density', () {
      final PackageNutrition pn = PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'serving-cup',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      );
      expect(pn.isValid, isTrue);
      final double expected =
          Quantity.of(10, Units.ounce).canonicalAmount /
          (Quantity.of(1, Units.cup).canonicalAmount * 2);
      expect(pn.gramsPerMillilitre, closeTo(expected, 1e-9));
    });

    test('a half-cup serving with 4 servings/package implies the same total '
        'volume as 1 cup with 2 servings/package', () {
      final PackageNutrition halfCup = PackageNutrition.manual(
        servingsPerPackage: 4,
        servingOptionId: 's',
        servingAmount: Quantity.of(0.5, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      );
      final PackageNutrition oneCup = PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 's',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      );
      expect(
        halfCup.gramsPerMillilitre,
        closeTo(oneCup.gramsPerMillilitre!, 1e-9),
      );
    });

    test('fractional servings per package are valid', () {
      final PackageNutrition pn = PackageNutrition.manual(
        servingsPerPackage: 2.5,
        servingOptionId: 's',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(20, Units.ounce),
      );
      expect(pn.isValid, isTrue);
    });

    test('a missing servings-per-package field is invalid', () {
      final PackageNutrition pn = PackageNutrition.fromJson(<String, dynamic>{
        'version': 1,
        'serving_option_id': 's',
        'serving_amount': <String, dynamic>{
          'canonical_amount': 236.5882365,
          'kind': 'volume',
        },
        'package_amount': <String, dynamic>{
          'canonical_amount': 283.5,
          'kind': 'mass',
        },
        'is_approximate': false,
        'source': 'manual',
        'basis': 'as_packaged',
      });
      expect(pn.isValid, isFalse);
      expect(pn.gramsPerMillilitre, isNull);
    });

    test('a negative, zero, or nonfinite count is invalid', () {
      for (final Object bad in <Object>[-1, 0, double.nan, double.infinity]) {
        final PackageNutrition pn = PackageNutrition.fromJson(<String, dynamic>{
          'version': 1,
          'servings_per_package': bad,
          'serving_option_id': 's',
          'serving_amount': <String, dynamic>{
            'canonical_amount': 236.5882365,
            'kind': 'volume',
          },
          'package_amount': <String, dynamic>{
            'canonical_amount': 283.5,
            'kind': 'mass',
          },
          'is_approximate': false,
          'source': 'manual',
          'basis': 'as_packaged',
        });
        expect(pn.isValid, isFalse, reason: '$bad should be invalid');
      }
    });

    test('a count-unit serving is rejected: only mass<->volume is bridged', () {
      final PackageNutrition pn = PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 's',
        servingAmount: Quantity.of(1, Units.item),
        packageAmount: Quantity.of(10, Units.ounce),
      );
      expect(pn.isValid, isFalse);
    });

    test('a fluid-ounce package amount is rejected: the package must be a '
        'mass, not a volume', () {
      final PackageNutrition pn = PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 's',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.flOz),
      );
      expect(pn.isValid, isFalse);
    });

    test('unknown-version data round-trips untouched', () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'version': 2,
        'something': 'from the future',
      };
      final PackageNutrition pn = PackageNutrition.fromJson(raw);
      expect(pn.isValid, isFalse);
      expect(pn.toJson(), raw);
    });

    test('matches() detects every kind of staleness', () {
      final PackageNutrition pn = PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'serving-cup',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      );
      expect(
        pn.matches(
          pack: Quantity.of(10, Units.ounce),
          servingId: 'serving-cup',
          servingAmount: Quantity.of(1, Units.cup),
        ),
        isTrue,
      );
      expect(
        pn.matches(
          pack: Quantity.of(12, Units.ounce),
          servingId: 'serving-cup',
          servingAmount: Quantity.of(1, Units.cup),
        ),
        isFalse,
        reason: 'changed package size',
      );
      expect(
        pn.matches(
          pack: Quantity.of(10, Units.ounce),
          servingId: 'serving-other',
          servingAmount: Quantity.of(1, Units.cup),
        ),
        isFalse,
        reason: 'different serving selected',
      );
      expect(
        pn.matches(
          pack: Quantity.of(10, Units.ounce),
          servingId: 'serving-cup',
          servingAmount: Quantity.of(2, Units.cup),
        ),
        isFalse,
        reason: 'serving amount changed',
      );
      expect(
        pn.matches(
          pack: null,
          servingId: 'serving-cup',
          servingAmount: Quantity.of(1, Units.cup),
        ),
        isFalse,
        reason: 'package removed',
      );
    });
  });

  group('Food.activePackageServing and derived density (spec R9, R12)', () {
    ServingOption cupServing() => aServing(
      amount: 1,
      unit: Units.cup,
      id: 'serving-cup',
      macros: const Macros(kcal: 100, proteinG: 2, fiberG: 3),
    );

    Food foodWithPackage({
      List<ServingOption>? servingOptions,
      PackageNutrition? packageNutrition,
      Quantity? packSize,
      double? gramsPerMillilitre,
    }) => Food(
      id: 'food-pkg',
      name: 'Test food',
      servingOptions: servingOptions ?? <ServingOption>[cupServing()],
      source: FoodSource.manual,
      packSize: packSize ?? Quantity.of(10, Units.ounce),
      packageNutrition:
          packageNutrition ??
          PackageNutrition.manual(
            servingsPerPackage: 2,
            servingOptionId: 'serving-cup',
            servingAmount: Quantity.of(1, Units.cup),
            packageAmount: Quantity.of(10, Units.ounce),
          ),
      gramsPerMillilitre: gramsPerMillilitre,
    );

    test('resolves the linked serving when it still matches', () {
      final Food food = foodWithPackage();
      expect(food.activePackageServing?.id, 'serving-cup');
      expect(food.hasStalePackageNutrition, isFalse);
    });

    test('a changed package size makes the relationship stale', () {
      final Food food = foodWithPackage(packSize: Quantity.of(12, Units.ounce));
      expect(food.activePackageServing, isNull);
      expect(food.hasStalePackageNutrition, isTrue);
      expect(food.packageGramsPerMillilitre, isNull);
    });

    test('a removed serving makes the relationship stale, not a crash', () {
      final Food food = foodWithPackage(
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 400),
          ),
        ],
      );
      expect(food.activePackageServing, isNull);
      expect(food.hasStalePackageNutrition, isTrue);
    });

    test('reordering the serving list does not affect the match', () {
      final ServingOption other = aServing(
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 400),
      );
      final Food reordered = foodWithPackage(
        servingOptions: <ServingOption>[other, cupServing()],
      );
      expect(reordered.activePackageServing?.id, 'serving-cup');
    });

    test('an own explicit density wins over the package relationship', () {
      final Food food = foodWithPackage(gramsPerMillilitre: 2.0);
      expect(food.ownGramsPerMillilitre, 2.0);
      expect(food.effectiveGramsPerMillilitre, 2.0);
      expect(food.packageDensityConflictsWithOwn, isTrue);
    });

    test('with no own density, the package relationship is the fallback', () {
      final Food food = foodWithPackage();
      expect(food.ownGramsPerMillilitre, isNull);
      expect(food.effectiveGramsPerMillilitre, isNotNull);
      expect(food.effectiveGramsPerMillilitre, food.packageGramsPerMillilitre);
    });

    test('a zero-calorie food can still derive a package density', () {
      final Food food = foodWithPackage(
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.cup,
            id: 'serving-cup',
            macros: Macros.zero,
          ),
        ],
      );
      expect(food.effectiveGramsPerMillilitre, isNotNull);
    });
  });

  group('MacroCalculator bridges through the package relationship '
      '(spec R9, R12)', () {
    Food cheeseWithPackage({
      bool approximate = false,
      ServingOption? extraFirst,
    }) {
      final ServingOption cup = aServing(
        amount: 1,
        unit: Units.cup,
        id: 'serving-cup',
        macros: const Macros(kcal: 100, proteinG: 2, fatG: 1, fiberG: 3),
      );
      return Food(
        id: 'food-cheese',
        name: 'Test cheese',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[?extraFirst, cup],
        packSize: Quantity.of(10, Units.ounce),
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 2,
          servingOptionId: 'serving-cup',
          servingAmount: Quantity.of(1, Units.cup),
          packageAmount: Quantity.of(10, Units.ounce),
          isApproximate: approximate,
        ),
      );
    }

    test('30 oz resolves to 6 servings and 600 kcal; nulls stay null', () {
      final Food food = cheeseWithPackage();
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: 30,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      expect(result.status, IngredientMacroStatus.resolved);
      expect(result.macros.kcal, closeTo(600, 1e-6));
      expect(result.macros.proteinG, closeTo(12, 1e-6));
      expect(result.macros.fatG, closeTo(6, 1e-6));
      expect(result.macros.fiberG, closeTo(18, 1e-6));
      expect(result.macros.sodiumMg, isNull);
      expect(result.macros.cholesterolMg, isNull);
    });

    test('half and double the amount scale linearly', () {
      final Food food = cheeseWithPackage();
      final IngredientMacros half = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: 15,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      final IngredientMacros doubled = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: 60,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      expect(half.macros.kcal, closeTo(300, 1e-6));
      expect(doubled.macros.kcal, closeTo(1200, 1e-6));
    });

    test('a signed (deduction) mass quantity scales signed; the package '
        'amount itself is never negative', () {
      final Food food = cheeseWithPackage();
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: -15,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      expect(result.status, IngredientMacroStatus.resolved);
      expect(result.macros.kcal, closeTo(-300, 1e-6));
      expect(
        food.packageNutrition!.packageAmount!.canonicalAmount,
        greaterThan(0),
      );
    });

    test('uses the specifically selected serving, never an arbitrary first '
        'volume row', () {
      final ServingOption decoy = aServing(
        amount: 1,
        unit: Units.tbsp,
        macros: const Macros(kcal: 999999),
      );
      final Food food = cheeseWithPackage(extraFirst: decoy);
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: 10,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      // 10 oz is exactly one package, i.e. 2 cups: 200 kcal via the cup
      // serving, nowhere near the decoy tablespoon serving's numbers.
      expect(result.macros.kcal, closeTo(200, 1e-6));
    });

    test('a stale package relationship is not used silently', () {
      final ServingOption cup = aServing(
        amount: 1,
        unit: Units.cup,
        id: 'serving-cup',
        macros: const Macros(kcal: 100),
      );
      final Food food = Food(
        id: 'food-stale',
        name: 'Test stale',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[cup],
        packSize: Quantity.of(12, Units.ounce), // changed since review
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 2,
          servingOptionId: 'serving-cup',
          servingAmount: Quantity.of(1, Units.cup),
          packageAmount: Quantity.of(10, Units.ounce),
        ),
      );
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'Test stale',
          amount: 10,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      expect(result.status, IngredientMacroStatus.unconvertible);
    });

    test('flags the recipe-level approximate-package note when used', () {
      final Food food = cheeseWithPackage(approximate: true);
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'Test cheese',
          amount: 10,
          unit: Units.ounce,
          foodId: food.id,
        ),
        food: food,
      );
      expect(result.usesApproximatePackage, isTrue);

      final Recipe recipe = aRecipe(
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Test cheese',
            amount: 10,
            unit: Units.ounce,
            foodId: food.id,
          ),
        ],
      );
      final RecipeMacros macros = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{food.id: food},
      );
      expect(macros.usesApproximatePackageNutrition, isTrue);
    });

    test('an exact package relationship raises no approximate note', () {
      final Food food = cheeseWithPackage();
      final Recipe recipe = aRecipe(
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Test cheese',
            amount: 10,
            unit: Units.ounce,
            foodId: food.id,
          ),
        ],
      );
      final RecipeMacros macros = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{food.id: food},
      );
      expect(macros.usesApproximatePackageNutrition, isFalse);
    });
  });
}
