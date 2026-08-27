import 'package:hearth/domain/format/quantity_format.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/recipes/recipe_scaler.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  Recipe simpleRecipe() => aRecipe(
    servings: 4,
    ingredients: <RecipeIngredient>[
      anIngredient('olive oil', amount: 1, unit: Units.tsp, sortOrder: 0),
      anIngredient(
        'chicken breast',
        amount: 400,
        unit: Units.gram,
        foodId: 'food-chicken',
        sortOrder: 1,
      ),
    ],
  );

  group('scaling by multiplier', () {
    test('multiplies every quantity and the yield', () {
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(simpleRecipe(), 2);
      expect(scaled.recipe.servings, 8);
      expect(
        scaled.recipe.allIngredients[1].quantity!.amountIn(Units.gram),
        closeTo(800, 1e-9),
      );
    });

    test('normalises units as it goes: 1 tsp tripled reads as 1 tbsp', () {
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(simpleRecipe(), 3);
      final RecipeIngredient oil = scaled.recipe.allIngredients.first;
      expect(oil.quantity!.preferredUnit, Units.tbsp);
      expect(QuantityFormat.format(oil.quantity!), '1 tbsp');
    });

    test('per-serving macros are unchanged by scaling', () {
      // Scaling changes how much you make, not what a serving is.
      final Map<String, Food> foods = <String, Food>{
        'food-chicken': aFoodPer100g(
          'chicken breast',
          kcal: 165,
          protein: 31,
          id: 'food-chicken',
        ),
      };
      final Recipe original = simpleRecipe();
      final Recipe doubled = RecipeScaler.byMultiplier(original, 2).recipe;

      expect(
        MacroCalculator.forRecipe(doubled, foods: foods).perServing.kcal,
        closeTo(
          MacroCalculator.forRecipe(original, foods: foods).perServing.kcal,
          1e-9,
        ),
      );
    });

    test('scaling up then back down returns the original amounts', () {
      final Recipe original = simpleRecipe();
      final Recipe roundTripped = RecipeScaler.byMultiplier(
        RecipeScaler.byMultiplier(original, 4).recipe,
        0.25,
      ).recipe;

      for (int i = 0; i < original.allIngredients.length; i++) {
        expect(
          roundTripped.allIngredients[i].quantity!.canonicalAmount,
          original.allIngredients[i].quantity!.canonicalAmount,
          reason: original.allIngredients[i].name,
        );
      }
      expect(roundTripped.servings, original.servings);
    });

    test('leaves unquantified lines alone', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[anIngredient('salt to taste')],
      );
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(recipe, 3);
      expect(scaled.recipe.allIngredients.single.quantity, isNull);
    });

    test('rejects a non-positive factor', () {
      expect(
        () => RecipeScaler.byMultiplier(simpleRecipe(), 0),
        throwsArgumentError,
      );
      expect(
        () => RecipeScaler.byMultiplier(simpleRecipe(), -2),
        throwsArgumentError,
      );
    });
  });

  group('scaling to a target yield (the primary control)', () {
    test('4 servings to 6 is a 1.5x scale', () {
      final ScaledRecipe scaled = RecipeScaler.toServings(simpleRecipe(), 6);
      expect(scaled.factor, 1.5);
      expect(scaled.recipe.servings, 6);
      expect(
        scaled.recipe.allIngredients[1].quantity!.amountIn(Units.gram),
        closeTo(600, 1e-9),
      );
    });

    test('scaling down works the same way', () {
      final ScaledRecipe scaled = RecipeScaler.toServings(simpleRecipe(), 2);
      expect(scaled.recipe.servings, 2);
      expect(
        scaled.recipe.allIngredients[1].quantity!.amountIn(Units.gram),
        closeTo(200, 1e-9),
      );
    });

    test('refuses a recipe with no yield to scale from', () {
      expect(
        () => RecipeScaler.toServings(aRecipe(servings: 0), 4),
        throwsArgumentError,
      );
    });
  });

  group('per-section scaling (spec §5.2)', () {
    Recipe sauced() => aRecipe(
      servings: 4,
      sections: <RecipeSection>[
        aSection(
          id: 'sec-main',
          name: 'Main',
          sortOrder: 0,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'chicken breast',
              amount: 400,
              unit: Units.gram,
              sectionId: 'sec-main',
            ),
          ],
        ),
        aSection(
          id: 'sec-sauce',
          name: 'Sauce',
          sortOrder: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'heavy cream',
              amount: 100,
              unit: Units.millilitre,
              sectionId: 'sec-sauce',
            ),
          ],
        ),
      ],
    );

    test('scales only the named section', () {
      final ScaledRecipe scaled = RecipeScaler.section(
        sauced(),
        'sec-sauce',
        2,
      );
      final Map<String, RecipeSection> byId = <String, RecipeSection>{
        for (final RecipeSection s in scaled.recipe.sections) s.id: s,
      };
      expect(
        byId['sec-sauce']!.ingredients.single.quantity!.amountIn(
          Units.millilitre,
        ),
        closeTo(200, 1e-9),
      );
      expect(
        byId['sec-main']!.ingredients.single.quantity!.amountIn(Units.gram),
        closeTo(400, 1e-9),
      );
    });

    test('leaves the yield alone — double sauce is not double dinner', () {
      final ScaledRecipe scaled = RecipeScaler.section(
        sauced(),
        'sec-sauce',
        2,
      );
      expect(scaled.recipe.servings, 4);
    });

    test('rejects an unknown section', () {
      expect(
        () => RecipeScaler.section(sauced(), 'sec-nope', 2),
        throwsArgumentError,
      );
    });
  });

  group('non-linear warnings — flagged, never auto-adjusted', () {
    test('flags seasoning and leavening', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('kosher salt', amount: 1, unit: Units.tsp),
          anIngredient('baking powder', amount: 2, unit: Units.tsp),
          anIngredient('all-purpose flour', amount: 2, unit: Units.cup),
        ],
      );
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(recipe, 3);

      expect(
        scaled.warnings.map((ScalingWarning w) => w.kind),
        containsAll(<ScalingWarningKind>[
          ScalingWarningKind.seasoning,
          ScalingWarningKind.leavening,
        ]),
      );
      // Flour is perfectly linear and must not be flagged.
      expect(
        scaled.warnings.map((ScalingWarning w) => w.subject),
        isNot(contains('all-purpose flour')),
      );
    });

    test('flags timers but does not change them', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('all-purpose flour', amount: 2, unit: Units.cup),
        ],
        steps: <RecipeStep>[aStep('Bake', timerSeconds: 1800)],
      );
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(recipe, 2);

      expect(scaled.warnings.single.kind, ScalingWarningKind.cookTime);
      expect(scaled.recipe.allSteps.single.timerSeconds, 1800);
    });

    test('scaling by 1 warns about nothing', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('salt', amount: 1, unit: Units.tsp),
        ],
        steps: <RecipeStep>[aStep('Bake', timerSeconds: 600)],
      );
      expect(RecipeScaler.byMultiplier(recipe, 1).warnings, isEmpty);
    });
  });
}
