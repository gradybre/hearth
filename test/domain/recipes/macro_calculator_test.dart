import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  noMatchNeededTests();

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

    test('a partial fibre total says how much of it was guessed at', () {
      // Two ingredients count; one of their foods knows its fibre. The total
      // is real as far as it goes, and saying so is the difference between a
      // useful number and one somebody trusts too far (spec §5.6).
      final Food known = aFood(
        'oats',
        id: 'f-oats',
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 380, fiberG: 10),
          ),
        ],
      );
      final Food silent = aFood(
        'milk',
        id: 'f-milk',
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.millilitre,
            macros: const Macros(kcal: 50),
          ),
        ],
      );

      final RecipeMacros macros = MacroCalculator.forRecipe(
        aRecipe(
          title: 'Porridge',
          servings: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'oats',
              amount: 100,
              unit: Units.gram,
              foodId: 'f-oats',
            ),
            anIngredient(
              'milk',
              amount: 100,
              unit: Units.millilitre,
              foodId: 'f-milk',
            ),
          ],
        ),
        foods: <String, Food>{'f-oats': known, 'f-milk': silent},
      );

      expect(macros.total.fiberG, closeTo(10, 1e-9));
      expect(macros.unknownCountFor(MinorNutrient.fiber), 1);
      expect(
        macros.partialNoteFor(MinorNutrient.fiber),
        '1 ingredient did not say',
      );
      // Nobody said anything about sodium, so there is no total to caveat.
      expect(macros.total.sodiumMg, isNull);
      expect(macros.partialNoteFor(MinorNutrient.sodium), isNull);
    });

    test('a total every counted ingredient knew carries no caveat', () {
      final Food oats = aFood(
        'oats',
        id: 'f-oats',
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 380, fiberG: 10),
          ),
        ],
      );
      final RecipeMacros macros = MacroCalculator.forRecipe(
        aRecipe(
          title: 'Oats',
          servings: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'oats',
              amount: 100,
              unit: Units.gram,
              foodId: 'f-oats',
            ),
            // Excluded on the recipe's own say-so, so not a gap in anything.
            anIngredient('salt', optional: true),
          ],
        ),
        foods: <String, Food>{'f-oats': oats},
      );

      expect(macros.partialNoteFor(MinorNutrient.fiber), isNull);
    });

    test('optional wins over the seasoning mark, and that is deliberate', () {
      // Both flags are set, and `optionalExcluded` is the answer. Do not
      // reorder these two checks to make a "mark as a seasoning" button do
      // something on a "to taste" line: the parser read the recipe's own
      // words, and "to taste" is what the recipe said. The button is hidden
      // there instead — see `showFoodPicker`'s `offerSeasoning`.
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient('salt', optional: true, needsNoMatch: true),
      );
      expect(result.status, IngredientMacroStatus.optionalExcluded);
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

  group('a food that can bridge its own units', () {
    // Brendan's report: 2.5 cups of a cheddar recorded in grams came back
    // "no serving in cup", even though the food itself states both a cup
    // serving and a gram serving — it had already said how much a cup
    // weighs, and nothing was reading it.
    Food cheddar() => aFood(
      'Costco shredded cheddar',
      id: 'food-cheddar',
      servingOptions: <ServingOption>[
        // 1/4 cup is 28 g: 110 kcal against 393 kcal per 100 g.
        aServing(
          amount: 0.25,
          unit: Units.cup,
          macros: const Macros(kcal: 110, proteinG: 7, fatG: 9),
        ),
        aServing(
          amount: 100,
          unit: Units.gram,
          macros: const Macros(kcal: 393, proteinG: 25, fatG: 32),
        ),
      ],
    );

    test('states a density its own servings imply', () {
      // A quarter-cup (59.15 ml) weighing 28 g is about 0.47 g/ml.
      expect(cheddar().effectiveGramsPerMillilitre, closeTo(0.473, 0.01));
    });

    test('an explicit density still wins over the derived one', () {
      // A figure the source measured describes this food better than one
      // inferred from two of its own roundings.
      final Food measured = aFood(
        'Cheddar',
        gramsPerMillilitre: 0.6,
        servingOptions: cheddar().servingOptions,
      );
      expect(measured.effectiveGramsPerMillilitre, 0.6);
    });

    test('a cup of it now resolves instead of being flagged', () {
      final IngredientMacros result = MacroCalculator.forIngredient(
        anIngredient(
          'shredded cheddar',
          amount: 2.5,
          unit: Units.cup,
          foodId: 'food-cheddar',
        ),
        food: cheddar(),
      );

      expect(result.status, IngredientMacroStatus.resolved);
      // 2.5 cups is ten quarter-cups: ten times the 110 kcal serving.
      expect(result.macros.kcal, closeTo(1100, 1));
    });

    test('one serving alone still cannot bridge anything', () {
      // Nothing dishonest happens when the food has only one measurement to
      // go on — there is no second one to compare it against.
      final Food massOnly = aFoodPer100g('Mystery', kcal: 200);
      expect(massOnly.effectiveGramsPerMillilitre, isNull);
    });

    test('a zero-calorie food bridges on its other macros', () {
      final Food water = aFood(
        'Sparkling water',
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.millilitre,
            macros: const Macros(kcal: 0, proteinG: 1),
          ),
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 0, proteinG: 1),
          ),
        ],
      );
      expect(water.effectiveGramsPerMillilitre, closeTo(1, 1e-9));
    });

    test('a food with no numbers at all bridges nothing', () {
      final Food empty = aFood(
        'Empty',
        servingOptions: <ServingOption>[
          aServing(amount: 1, unit: Units.cup, macros: Macros.zero),
          aServing(amount: 100, unit: Units.gram, macros: Macros.zero),
        ],
      );
      expect(empty.effectiveGramsPerMillilitre, isNull);
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

  group('why a recipe is incomplete', () {
    // Brendan's report: a recipe with all 8 ingredients matched to foods
    // still said 4 were "not matched". They were matched — they were counts
    // ("1/2 small white onion") against foods that only knew grams, which is
    // a different gap with a different fix, and telling him to re-match them
    // sent him back to work that could not have helped.
    final Food onion = aFoodPer100g('White onion', kcal: 40, id: 'food-onion');
    final Food chicken = aFoodPer100g(
      'chicken breast',
      kcal: 165,
      protein: 31,
      id: 'food-chicken',
    );

    test('a matched-but-unconvertible ingredient is not reported as '
        'unmatched', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient(
            'small white onion',
            amount: 0.5,
            unit: Units.item,
            foodId: 'food-onion',
          ),
        ],
      );
      final RecipeMacros result = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{'food-onion': onion},
      );

      expect(result.isIncomplete, isTrue);
      expect(result.ingredientsMissingFood, isEmpty);
      expect(result.ingredientsUnconvertible, hasLength(1));
      expect(result.incompleteReason, isNot(contains('not matched to a food')));
      expect(result.incompleteReason, contains('no serving in that unit'));
    });

    test('a genuinely unmatched ingredient still says so', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('mystery spice', amount: 1, unit: Units.tsp),
        ],
      );
      final RecipeMacros result = MacroCalculator.forRecipe(recipe);

      expect(result.ingredientsMissingFood, hasLength(1));
      expect(result.incompleteReason, contains('not matched to a food'));
    });

    test('several kinds of gap are all named, not collapsed into one', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient(
            'small white onion',
            amount: 0.5,
            unit: Units.item,
            foodId: 'food-onion',
          ),
          anIngredient('mystery spice', amount: 1, unit: Units.tsp),
          anIngredient('a pinch of something'),
        ],
      );
      final RecipeMacros result = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{'food-onion': onion},
      );

      expect(result.ingredientsUnconvertible, hasLength(1));
      expect(result.ingredientsMissingFood, hasLength(1));
      expect(result.ingredientsWithoutQuantity, hasLength(1));
      expect(result.incompleteReason, contains('not matched to a food'));
      expect(result.incompleteReason, contains('no serving in that unit'));
      expect(result.incompleteReason, contains('no amount'));
    });

    test('a complete recipe has no reason to give', () {
      final Recipe recipe = aRecipe(
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
        foods: <String, Food>{'food-chicken': chicken},
      );

      expect(result.isIncomplete, isFalse);
      expect(result.incompleteReason, isNull);
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

/// Lines marked as needing no food at all (spec §5.3).
void noMatchNeededTests() {
  Recipe withSalt({bool marked = true}) => aRecipe(
    title: 'Bread',
    servings: 1,
    ingredients: <RecipeIngredient>[
      anIngredient(
        'flour',
        amount: 500,
        unit: Units.gram,
        foodId: 'food-flour',
      ),
      anIngredient('salt', needsNoMatch: marked),
    ],
  );

  Map<String, Food> flour() => <String, Food>{
    'food-flour': aFoodPer100g('Flour', kcal: 364, id: 'food-flour'),
  };

  group('a seasoning line', () {
    test('contributes nothing and says why', () {
      final RecipeMacros macros = MacroCalculator.forRecipe(
        withSalt(),
        foods: flour(),
      );
      final IngredientMacros salt = macros.ingredients.last;

      expect(salt.status, IngredientMacroStatus.noMatchNeeded);
      expect(salt.macros, Macros.zero);
      expect(macros.total.kcal, closeTo(1820, 1e-6));
    });

    test('is not a gap, so the recipe reads as complete', () {
      // The whole point. A warning that is always on stops being read, and
      // salt was going to keep it on for ever.
      final RecipeMacros macros = MacroCalculator.forRecipe(
        withSalt(),
        foods: flour(),
      );

      expect(macros.isIncomplete, isFalse);
      expect(macros.incompleteReason, isNull);
      expect(macros.ingredientsMissingFood, isEmpty);
      expect(macros.ingredientsWithoutQuantity, isEmpty);
    });

    test('and unmarked, the same line is a gap again', () {
      final RecipeMacros macros = MacroCalculator.forRecipe(
        withSalt(marked: false),
        foods: flour(),
      );

      expect(macros.isIncomplete, isTrue);
      expect(macros.incompleteReason, isNotNull);
    });

    test('beats the no-amount check, which salt would trip too', () {
      // "Salt to taste" has no quantity either. Reporting it as a missing
      // amount would be the same permanent warning wearing another label.
      final RecipeMacros macros = MacroCalculator.forRecipe(
        withSalt(),
        foods: flour(),
      );
      expect(
        macros.ingredients.last.status,
        isNot(IngredientMacroStatus.noQuantity),
      );
    });

    test('optional still means optional, and is still its own thing', () {
      final RecipeMacros macros = MacroCalculator.forRecipe(
        aRecipe(
          title: 'Garnished',
          servings: 1,
          ingredients: <RecipeIngredient>[
            anIngredient('parsley', optional: true),
          ],
        ),
        foods: const <String, Food>{},
      );

      expect(
        macros.ingredients.single.status,
        IngredientMacroStatus.optionalExcluded,
      );
    });
  });

  group('a recipe that comes to less than nothing (spec §5.2)', () {
    Food wrap() => aFood(
      'Make it a Lettuce Wrap',
      id: 'f-wrap',
      source: FoodSource.restaurant,
      servingOptions: <ServingOption>[
        aServing(
          amount: 1,
          unit: Units.item,
          macros: const Macros(kcal: -180, carbG: -25, fiberG: 1),
        ),
      ],
    ).asModifier();

    Recipe onlyTheDeduction() => aRecipe(
      servings: 1,
      ingredients: <RecipeIngredient>[
        anIngredient(
          'Make it a Lettuce Wrap',
          amount: 1,
          unit: Units.item,
          foodId: 'f-wrap',
        ),
      ],
    );

    test('says so, rather than quietly reducing the day', () {
      // The builder refuses to assemble one, but the recipe editor will let
      // you delete the burger afterwards and keep the wrap. Nothing is
      // missing here, so the ordinary "not counted" phrasing has nothing to
      // report — and a silent −180 would be frozen into whatever day it was
      // logged to (rule 3).
      final RecipeMacros macros = MacroCalculator.forRecipe(
        onlyTheDeduction(),
        foods: <String, Food>{'f-wrap': wrap()},
      );

      expect(macros.total.kcal, -180);
      expect(macros.incompleteReason, contains('less than nothing'));
    });

    test('and it is not only the calories that can go under', () {
      // A deduction can leave the calories at zero while the carbohydrate
      // total is below it — a wrap against a zero-calorie condiment, say.
      // Checking kcal alone would log a negative macro with nothing said.
      final Food condiment = aFood(
        'Mustard',
        id: 'f-mustard',
        source: FoodSource.restaurant,
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.item,
            macros: const Macros(kcal: 180, carbG: 0),
          ),
        ],
      );
      final Recipe recipe = aRecipe(
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Mustard',
            amount: 1,
            unit: Units.item,
            foodId: 'f-mustard',
          ),
          anIngredient(
            'Make it a Lettuce Wrap',
            amount: 1,
            unit: Units.item,
            foodId: 'f-wrap',
          ),
        ],
      );

      final RecipeMacros macros = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{'f-wrap': wrap(), 'f-mustard': condiment},
      );

      expect(macros.total.kcal, 0);
      expect(macros.total.carbG, -25);
      expect(macros.incompleteReason, contains('less than nothing'));
    });

    test('and an ordinary recipe still says nothing at all', () {
      final Food chicken = aFoodPer100g('chicken breast', kcal: 165);
      final Recipe recipe = aRecipe(
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            amount: 100,
            unit: Units.gram,
            foodId: chicken.id,
          ),
        ],
      );

      expect(
        MacroCalculator.forRecipe(
          recipe,
          foods: <String, Food>{chicken.id: chicken},
        ).incompleteReason,
        isNull,
      );
    });
  });
}
