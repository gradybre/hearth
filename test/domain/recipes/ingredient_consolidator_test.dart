import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

ConsolidatedIngredient _byName(
  List<ConsolidatedIngredient> list,
  String name,
) => list.firstWhere((ConsolidatedIngredient c) => c.displayName == name);

void main() {
  group('stage one: section flatten (spec §5.2)', () {
    Recipe twoSections() => aRecipe(
      id: 'recipe-a',
      servings: 4,
      sections: <RecipeSection>[
        aSection(
          id: 'sec-main',
          name: 'Main',
          sortOrder: 0,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'olive oil',
              amount: 1,
              unit: Units.tbsp,
              sectionId: 'sec-main',
            ),
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
              'olive oil',
              amount: 2,
              unit: Units.tbsp,
              sectionId: 'sec-sauce',
            ),
            anIngredient(
              'garlic',
              amount: 2,
              unit: Units.clove,
              sectionId: 'sec-sauce',
              optional: true,
            ),
          ],
        ),
      ],
    );

    test('sums an ingredient appearing in more than one section', () {
      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        twoSections(),
      );
      final ConsolidatedIngredient oil = _byName(flat, 'olive oil');
      expect(oil.quantities.single.amountIn(Units.tbsp), closeTo(3, 1e-9));
      expect(oil.isMixedUnit, isFalse);
    });

    test('excludes optional ingredients by default', () {
      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        twoSections(),
      );
      expect(
        flat.map((ConsolidatedIngredient c) => c.displayName),
        isNot(contains('garlic')),
      );
    });

    test('includes optional ingredients when asked', () {
      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        twoSections(),
        includeOptional: true,
      );
      expect(
        _byName(flat, 'garlic').quantities.single.amountIn(Units.clove),
        2,
      );
    });

    test('matches on normalised names', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('Olive Oil', amount: 1, unit: Units.tbsp),
          anIngredient('olive oil,', amount: 1, unit: Units.tbsp),
        ],
      );
      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        recipe,
      );
      expect(flat, hasLength(1));
      expect(
        flat.single.quantities.single.amountIn(Units.tbsp),
        closeTo(2, 1e-9),
      );
    });

    test('matches on food id when two strings resolved to the same food', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('evoo', amount: 1, unit: Units.tbsp, foodId: 'food-oil'),
          anIngredient(
            'extra virgin olive oil',
            amount: 1,
            unit: Units.tbsp,
            foodId: 'food-oil',
          ),
        ],
      );
      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        recipe,
      );
      expect(flat, hasLength(1));
      expect(flat.single.foodId, 'food-oil');
    });

    test('flags a line that had an unquantified contribution', () {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('olive oil', amount: 1, unit: Units.tbsp),
          anIngredient('olive oil'),
        ],
      );
      expect(
        IngredientConsolidator.flatten(recipe).single.hasUnquantified,
        isTrue,
      );
    });
  });

  group('stage two: cross-recipe merge (spec §5.7)', () {
    Recipe recipeA() => aRecipe(
      id: 'recipe-a',
      servings: 4,
      ingredients: <RecipeIngredient>[
        anIngredient('butter', amount: 2, unit: Units.tbsp),
        anIngredient('chicken breast', amount: 400, unit: Units.gram),
      ],
    );
    Recipe recipeB() => aRecipe(
      id: 'recipe-b',
      servings: 2,
      ingredients: <RecipeIngredient>[
        anIngredient('butter', amount: 50, unit: Units.gram),
      ],
    );

    test('combines the same ingredient across recipes', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[recipeA(), recipeB()]);
      final ConsolidatedIngredient butter = _byName(merged, 'butter');
      expect(
        butter.sourceRecipeIds,
        containsAll(<String>['recipe-a', 'recipe-b']),
      );
    });

    test('mixed units merge when a density is known', () {
      // 2 tbsp butter = 29.57 ml at 0.911 g/ml = 26.9 g, plus 50 g = 76.9 g.
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[recipeA(), recipeB()]);
      final ConsolidatedIngredient butter = _byName(merged, 'butter');

      expect(butter.isMixedUnit, isFalse);
      expect(butter.quantities.single.amountIn(Units.gram), closeTo(76.9, 0.2));
    });

    test('mixed units stay side by side when density is unknown', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[
            aRecipe(
              id: 'r1',
              ingredients: <RecipeIngredient>[
                anIngredient('fennel fronds', amount: 2, unit: Units.tbsp),
              ],
            ),
            aRecipe(
              id: 'r2',
              ingredients: <RecipeIngredient>[
                anIngredient('fennel fronds', amount: 50, unit: Units.gram),
              ],
            ),
          ]);
      final ConsolidatedIngredient fronds = _byName(merged, 'fennel fronds');

      expect(fronds.isMixedUnit, isTrue);
      expect(fronds.quantities, hasLength(2));
    });

    test('counts never merge into weight', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[
            aRecipe(
              id: 'r1',
              ingredients: <RecipeIngredient>[
                anIngredient('garlic', amount: 2, unit: Units.clove),
              ],
            ),
            aRecipe(
              id: 'r2',
              ingredients: <RecipeIngredient>[
                anIngredient('garlic', amount: 30, unit: Units.gram),
              ],
            ),
          ]);
      expect(_byName(merged, 'garlic').quantities, hasLength(2));
    });

    test('a recipe planned at half its yield contributes half', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(
            <Recipe>[recipeA()],
            servingsFor: <String, double>{'recipe-a': 2},
          );
      expect(
        _byName(
          merged,
          'chicken breast',
        ).quantities.single.amountIn(Units.gram),
        closeTo(200, 1e-9),
      );
    });

    test('an absent plan entry uses the recipe as written', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[recipeA()]);
      expect(
        _byName(
          merged,
          'chicken breast',
        ).quantities.single.amountIn(Units.gram),
        closeTo(400, 1e-9),
      );
    });

    test('optional ingredients stay off the shopping list', () {
      final List<ConsolidatedIngredient> merged =
          IngredientConsolidator.mergeRecipes(<Recipe>[
            aRecipe(
              id: 'r1',
              ingredients: <RecipeIngredient>[
                anIngredient(
                  'salt',
                  amount: 1,
                  unit: Units.tsp,
                  optional: true,
                ),
                anIngredient('butter', amount: 2, unit: Units.tbsp),
              ],
            ),
          ]);
      expect(merged, hasLength(1));
      expect(merged.single.displayName, 'butter');
    });
  });
}
