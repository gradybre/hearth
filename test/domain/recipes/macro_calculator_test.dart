import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('single ingredient', () {
    test('scales the food serving to the ingredient amount', () {
      final Food chicken = aFoodPer100g(
        'chicken breast',
        kcal: 165,
        protein: 31,
        fat: 3.6,
        id: 'food-chicken',
      );
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'chicken breast',
          amount: 250,
          unit: Units.gram,
          foodId: 'food-chicken',
        ),
        food: chicken,
      );

      expect(result.status, IngredientMacroStatus.resolved);
      expect(result.macros.kcal, closeTo(412.5, 1e-9));
      expect(result.macros.proteinG, closeTo(77.5, 1e-9));
    });

    test('converts volume to weight when a density is known', () {
      final Food flour = aFoodPer100g(
        'all-purpose flour',
        kcal: 364,
        protein: 10,
        carbs: 76,
        id: 'food-flour',
      );
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'all-purpose flour',
          amount: 1,
          unit: Units.cup,
          foodId: 'food-flour',
        ),
        food: flour,
      );

      expect(result.status, IngredientMacroStatus.resolved);
      // 1 cup is ~125 g, so ~455 kcal.
      expect(result.macros.kcal, closeTo(455, 5));
    });

    test("prefers the food's own density over the generic table", () {
      final Food flour = aFoodPer100g(
        'all-purpose flour',
        kcal: 100,
        id: 'food-flour',
        gramsPerMillilitre: 1, // deliberately unlike the table's 0.528
      );
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'all-purpose flour',
          amount: 100,
          unit: Units.millilitre,
          foodId: 'food-flour',
        ),
        food: flour,
      );
      expect(result.macros.kcal, closeTo(100, 1e-9));
    });
  });

  group('exclusions and gaps (spec §5.2, §5.3)', () {
    test('optional ingredients are excluded and are NOT a data gap', () {
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient('salt', amount: 1, unit: Units.tsp, optional: true),
      );
      expect(result.status, IngredientMacroStatus.optionalExcluded);
      expect(result.macros, Macros.zero);
      expect(result.isDataGap, isFalse);
    });

    test('an unmatched ingredient is a gap, not a zero-calorie ingredient', () {
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient('fennel fronds', amount: 1, unit: Units.cup),
      );
      expect(result.status, IngredientMacroStatus.noFoodMatch);
      expect(result.isDataGap, isTrue);
    });

    test('an unquantified non-optional line is a gap', () {
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient('olive oil'),
        food: aFoodPer100g('olive oil', kcal: 884),
      );
      expect(result.status, IngredientMacroStatus.noQuantity);
      expect(result.isDataGap, isTrue);
    });

    test('an unconvertible unit is a gap rather than a guess', () {
      // Volume ingredient, weight-only food, no density for this name.
      final Food fronds = aFoodPer100g('fennel fronds', kcal: 30);
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient('fennel fronds', amount: 1, unit: Units.cup),
        food: fronds,
      );
      expect(result.status, IngredientMacroStatus.unconvertible);
      expect(result.macros, Macros.zero);
    });
  });

  group('whole recipe', () {
    Recipe buildRecipe() => aRecipe(
      servings: 4,
      ingredients: <RecipeIngredient>[
        anIngredient(
          'chicken breast',
          amount: 400,
          unit: Units.gram,
          foodId: 'food-chicken',
          sortOrder: 0,
        ),
        anIngredient(
          'olive oil',
          amount: 2,
          unit: Units.tbsp,
          foodId: 'food-oil',
          sortOrder: 1,
        ),
        anIngredient('salt', optional: true, sortOrder: 2),
      ],
    );

    final Map<String, Food> foods = <String, Food>{
      'food-chicken': aFoodPer100g(
        'chicken breast',
        kcal: 165,
        protein: 31,
        id: 'food-chicken',
      ),
      'food-oil': aFoodPer100g(
        'olive oil',
        kcal: 884,
        fat: 100,
        id: 'food-oil',
        gramsPerMillilitre: 0.918,
      ),
    };

    test('per-serving is the whole recipe divided by yield', () {
      final RecipeMacros result = MacroCalculator.forRecipe(
        buildRecipe(),
        foods: foods,
      );
      expect(result.perServing.kcal, closeTo(result.total.kcal / 4, 1e-9));
      expect(
        result.perServing.proteinG,
        closeTo(result.total.proteinG / 4, 1e-9),
      );
    });

    test('totals are the sum of the ingredients (spec §4)', () {
      final RecipeMacros result = MacroCalculator.forRecipe(
        buildRecipe(),
        foods: foods,
      );
      // 400 g chicken = 660 kcal; 2 tbsp oil = 29.57 ml * 0.918 = 27.15 g
      // = 240 kcal.
      expect(result.total.kcal, closeTo(900, 3));
      expect(result.total.proteinG, closeTo(124, 0.5));
    });

    test('a complete recipe is not flagged incomplete', () {
      final RecipeMacros result = MacroCalculator.forRecipe(
        buildRecipe(),
        foods: foods,
      );
      expect(result.isIncomplete, isFalse);
      expect(result.incompleteIngredients, isEmpty);
    });

    test('one unmatched ingredient flags the recipe but does not block', () {
      final Recipe recipe = aRecipe(
        servings: 2,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            amount: 200,
            unit: Units.gram,
            foodId: 'food-chicken',
          ),
          anIngredient('mystery spice blend', amount: 1, unit: Units.tbsp),
        ],
      );
      final RecipeMacros result = MacroCalculator.forRecipe(
        recipe,
        foods: foods,
      );

      expect(result.isIncomplete, isTrue);
      expect(result.incompleteIngredients.single.name, 'mystery spice blend');
      // What IS known is still counted.
      expect(result.total.kcal, closeTo(330, 1e-6));
    });

    test('a missing yield falls back to one serving instead of infinity', () {
      final Recipe recipe = aRecipe(
        servings: 0,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            amount: 100,
            unit: Units.gram,
            foodId: 'food-chicken',
          ),
        ],
      );
      final RecipeMacros result = MacroCalculator.forRecipe(
        recipe,
        foods: foods,
      );
      expect(result.perServing.kcal, closeTo(165, 1e-9));
      expect(result.perServing.kcal.isFinite, isTrue);
    });
  });

  test('forServings scales a logged portion', () {
    final ServingOption slice = aServing(
      amount: 1,
      unit: Units.slice,
      macros: const Macros(kcal: 80, proteinG: 3),
    );
    expect(MacroCalculator.forServings(slice, 2.5).kcal, 200);
  });
}
