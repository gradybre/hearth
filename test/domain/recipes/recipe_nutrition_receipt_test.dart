import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/recipes/recipe_nutrition_receipt.dart';
import 'package:hearth/domain/recipes/recipe_scaler.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

RecipeNutritionReceipt receiptFor(
  Recipe recipe,
  List<Food> foods, {
  Recipe? authoredRecipe,
  bool wholeDish = false,
}) {
  final Map<String, Food> byId = <String, Food>{
    for (final Food food in foods) food.id: food,
  };
  return RecipeNutritionReceipt(
    recipe: recipe,
    authoredRecipe: authoredRecipe,
    calculation: MacroCalculator.forRecipe(recipe, foods: byId),
    foods: byId,
    wholeDish: wholeDish,
  );
}

void main() {
  test('direct measurement records the row used, not the default serving', () {
    final ServingOption grams = aServing(
      id: 'grams',
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 200, proteinG: 10),
    );
    final Food food = aFood(
      'Beans',
      id: 'beans',
      servingOptions: <ServingOption>[
        aServing(
          id: 'can',
          amount: 1,
          unit: Units.can,
          macros: const Macros(kcal: 999),
        ),
        grams,
      ],
    );
    final IngredientMacros part = MacroCalculator.forIngredient(
      anIngredient('beans', amount: 250, unit: Units.gram),
      food: food,
    );
    expect(part.serving, same(grams));
    expect(part.servingCount, 2.5);
    expect(part.macros.kcal, 500);
    expect(part.macros.proteinG, 25);
  });

  test('food density records the actual cross-kind row and multiplier', () {
    final ServingOption serving = aServing(
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 80),
    );
    final IngredientMacros part = MacroCalculator.forIngredient(
      anIngredient('broth', amount: 50, unit: Units.millilitre),
      food: aFood(
        'Broth',
        gramsPerMillilitre: 2,
        servingOptions: <ServingOption>[serving],
      ),
    );
    expect(part.serving, same(serving));
    expect(part.servingCount, 1);
    expect(part.macros.kcal, 80);
    expect(part.usesApproximatePackage, isFalse);
  });

  test(
    'approximate package evidence names its reviewed row, even after reorder',
    () {
      final ServingOption anchor = aServing(
        id: 'reviewed-cup',
        amount: 1,
        unit: Units.cup,
        macros: const Macros(kcal: 50, fiberG: 2),
      );
      final Food food = aFood(
        'Prepared grains',
        id: 'grains',
        packSize: Quantity.of(200, Units.gram),
        servingOptions: <ServingOption>[
          aServing(
            id: 'other-cup',
            amount: 1,
            unit: Units.cup,
            macros: const Macros(kcal: 999),
          ),
          anchor,
        ],
        packageNutrition: PackageNutrition.manual(
          servingOptionId: anchor.id,
          servingAmount: anchor.amount,
          packageAmount: Quantity.of(200, Units.gram),
          servingsPerPackage: 4,
          isApproximate: true,
        ),
      );
      final Recipe recipe = aRecipe(
        servings: 2,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'grains',
            amount: 100,
            unit: Units.gram,
            foodId: food.id,
          ),
        ],
      );
      final RecipeNutritionReceipt receipt = receiptFor(recipe, <Food>[food]);
      final IngredientNutritionReceipt row = receipt.ingredients.single;
      expect(row.calculation.serving, same(anchor));
      expect(row.calculation.servingCount, 2);
      expect(row.calculation.usesApproximatePackage, isTrue);
      expect(row.contribution!.kcal, 50);
      expect(receipt.shown!.fiberG, 2);
    },
  );

  test('scaled receipt preserves authored amounts and unchanged per-serving values', () {
    final Food food = aFood(
      'Beans',
      id: 'beans',
      servingOptions: <ServingOption>[
        aServing(amount: 1, unit: Units.can, macros: const Macros(kcal: 200)),
      ],
    );
    final Recipe original = aRecipe(
      servings: 4,
      ingredients: <RecipeIngredient>[
        anIngredient('beans', amount: 2, unit: Units.can, foodId: food.id),
      ],
    );
    final Recipe doubled = RecipeScaler.byMultiplier(original, 2).recipe;
    final RecipeNutritionReceipt per = receiptFor(doubled, <Food>[
      food,
    ], authoredRecipe: original);
    final RecipeNutritionReceipt whole = receiptFor(
      doubled,
      <Food>[food],
      authoredRecipe: original,
      wholeDish: true,
    );
    expect(per.isScaled, isTrue);
    expect(per.ingredients.single.authored.quantity!.amountIn(Units.can), 2);
    expect(
      per.ingredients.single.calculation.ingredient.quantity!.amountIn(
        Units.can,
      ),
      4,
    );
    expect(per.ingredients.single.calculation.servingCount, 4);
    expect(per.shown!.kcal, 100);
    expect(per.ingredients.single.contribution!.kcal, 100);
    expect(whole.shown!.kcal, 800);
    expect(whole.ingredients.single.contribution!.kcal, 800);
    expect(original.servings, 4);
  });

  test('unresolved and excluded lines do not turn calculator placeholders into zero', () {
    final Food grams = aFood(
      'Dry mix',
      id: 'mix',
      servingOptions: <ServingOption>[
        aServing(
          amount: 100,
          unit: Units.gram,
          macros: const Macros(kcal: 200),
        ),
      ],
    );
    final Recipe recipe = aRecipe(
      ingredients: <RecipeIngredient>[
        anIngredient(
          'optional',
          optional: true,
          amount: 1,
          unit: Units.gram,
          foodId: 'mix',
        ),
        anIngredient('seasoning', needsNoMatch: true),
        anIngredient('unquantified', foodId: 'mix'),
        anIngredient('unmatched', amount: 1, unit: Units.can),
        anIngredient(
          'incompatible',
          amount: 1,
          unit: Units.item,
          foodId: 'mix',
        ),
      ],
    );
    final RecipeNutritionReceipt receipt = receiptFor(recipe, <Food>[
      grams,
    ], wholeDish: true);
    expect(
      receipt.ingredients.map(
        (IngredientNutritionReceipt row) => row.calculation.status,
      ),
      <IngredientMacroStatus>[
        IngredientMacroStatus.optionalExcluded,
        IngredientMacroStatus.noMatchNeeded,
        IngredientMacroStatus.noQuantity,
        IngredientMacroStatus.noFoodMatch,
        IngredientMacroStatus.unconvertible,
      ],
    );
    for (final IngredientNutritionReceipt row in receipt.ingredients) {
      expect(row.contribution, isNull);
      expect(row.calculation.serving, isNull);
      expect(row.calculation.servingCount, isNull);
    }
    expect(receipt.shown, isNull);
    expect(receipt.requiredCount, 3);
  });

  test('stated zero and unknown minor nutrients remain different', () {
    final Food water = aFood(
      'Water',
      id: 'water',
      isZeroCalorie: true,
      servingOptions: <ServingOption>[
        aServing(
          amount: 1,
          unit: Units.cup,
          macros: const Macros(kcal: 0, fiberG: 0),
        ),
      ],
    );
    final Recipe recipe = aRecipe(
      ingredients: <RecipeIngredient>[
        anIngredient('water', amount: 1, unit: Units.cup, foodId: 'water'),
      ],
    );
    final RecipeNutritionReceipt receipt = receiptFor(recipe, <Food>[water]);
    expect(receipt.shown!.kcal, 0);
    expect(receipt.ingredients.single.contribution!.fiberG, 0);
    expect(receipt.ingredients.single.contribution!.sodiumMg, isNull);
  });

  for (final double yield in <double>[0, double.nan, double.infinity]) {
    test(
      'invalid yield $yield withholds Per serving without losing Whole dish',
      () {
        final Food food = aFood(
          'Beans',
          id: 'beans',
          servingOptions: <ServingOption>[
            aServing(
              amount: 1,
              unit: Units.can,
              macros: const Macros(kcal: 200),
            ),
          ],
        );
        final Recipe recipe = aRecipe(
          servings: yield,
          ingredients: <RecipeIngredient>[
            anIngredient('beans', amount: 2, unit: Units.can, foodId: 'beans'),
          ],
        );
        final RecipeNutritionReceipt per = receiptFor(recipe, <Food>[food]);
        final RecipeNutritionReceipt whole = receiptFor(recipe, <Food>[
          food,
        ], wholeDish: true);
        expect(per.shown, isNull);
        expect(per.ingredients.single.contribution, isNull);
        expect(whole.shown!.kcal, 400);
        expect(whole.ingredients.single.contribution!.kcal, 400);
      },
    );
  }

  test(
    'restaurant deductions keep their signed contribution and serving count',
    () {
      final Food food = aFood(
        'Rice',
        id: 'rice',
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.item,
            macros: const Macros(kcal: 100, carbG: 20),
          ),
        ],
      );
      final Recipe recipe = aRecipe(
        kind: RecipeKind.eatenOut,
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('base', amount: 4, unit: Units.item, foodId: 'rice'),
          anIngredient('no rice', amount: -1, unit: Units.item, foodId: 'rice'),
        ],
      );
      final RecipeNutritionReceipt receipt = receiptFor(recipe, <Food>[food]);
      expect(receipt.ingredients.last.calculation.servingCount, -1);
      expect(receipt.ingredients.last.contribution!.kcal, -100);
      expect(receipt.shown!.kcal, 300);
    },
  );

  test('temporary duplicate preview IDs keep separate authored rows', () {
    final Recipe original = aRecipe(
      ingredients: <RecipeIngredient>[
        anIngredient('beans', id: 'preview', amount: 2, unit: Units.can),
        anIngredient('oil', id: 'preview', amount: 1, unit: Units.tbsp),
      ],
    );
    final Recipe scaled = RecipeScaler.byMultiplier(original, 2).recipe;
    final RecipeNutritionReceipt receipt = receiptFor(
      scaled,
      const <Food>[],
      authoredRecipe: original,
    );
    expect(
      receipt.ingredients.map(
        (IngredientNutritionReceipt row) => row.authored.name,
      ),
      <String>['beans', 'oil'],
    );
    expect(receipt.ingredients.first.authored.quantity!.amountIn(Units.can), 2);
    expect(receipt.ingredients.last.authored.quantity!.amountIn(Units.tbsp), 1);
  });
}
