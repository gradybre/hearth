import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

ConsolidatedIngredient _byName(
  List<ConsolidatedIngredient> list,
  String name,
) => list.firstWhere((ConsolidatedIngredient c) => c.displayName == name);

void main() {
  countTests();

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

/// Counted things, which cannot be added across their units.
///
/// Two cloves of garlic and a slice of bread are three things, and there is no
/// number that means both. `UnitConverter` has always refused this conversion
/// in either direction; the consolidator summed straight into the *kind*, so
/// it produced "3 items" and lost which three.
void countTests() {
  group('counted units are only summed with their own kind of thing', () {
    test('one thing counted two ways is two lines, not one sum', () {
      // Garlic by the clove in the marinade and by the head in the roast.
      // Both are counts, so both landed in the same bucket and came out as
      // "3 items" — a number that means neither.
      final Recipe recipe = aRecipe(
        id: 'r',
        servings: 2,
        sections: <RecipeSection>[
          aSection(
            id: 'a',
            name: 'Marinade',
            sortOrder: 0,
            ingredients: <RecipeIngredient>[
              anIngredient(
                'garlic',
                amount: 2,
                unit: Units.clove,
                sectionId: 'a',
              ),
            ],
          ),
          aSection(
            id: 'b',
            name: 'Roast',
            sortOrder: 1,
            ingredients: <RecipeIngredient>[
              anIngredient(
                'garlic',
                amount: 1,
                unit: Units.item,
                sectionId: 'b',
              ),
            ],
          ),
        ],
      );

      final ConsolidatedIngredient garlic = _byName(
        IngredientConsolidator.flatten(recipe),
        'garlic',
      );

      expect(garlic.quantities, hasLength(2));
      expect(garlic.isMixedUnit, isTrue);
      expect(
        garlic.quantities.map((Quantity q) => q.preferredUnit),
        containsAll(<Unit>[Units.clove, Units.item]),
      );
    });

    test('the same thing in the same unit still adds up', () {
      // The behaviour being protected: garlic in the marinade and garlic in
      // the sauce is one line at the shop.
      final Recipe recipe = aRecipe(
        id: 'r',
        servings: 2,
        sections: <RecipeSection>[
          aSection(
            id: 'a',
            name: 'Marinade',
            sortOrder: 0,
            ingredients: <RecipeIngredient>[
              anIngredient(
                'garlic',
                amount: 2,
                unit: Units.clove,
                sectionId: 'a',
              ),
            ],
          ),
          aSection(
            id: 'b',
            name: 'Sauce',
            sortOrder: 1,
            ingredients: <RecipeIngredient>[
              anIngredient(
                'garlic',
                amount: 3,
                unit: Units.clove,
                sectionId: 'b',
              ),
            ],
          ),
        ],
      );

      final List<ConsolidatedIngredient> flat = IngredientConsolidator.flatten(
        recipe,
      );

      expect(
        _byName(flat, 'garlic').quantities.single.amountIn(Units.clove),
        5,
      );
    });

    test('a counted line and a weighed one sit side by side', () {
      // Neither can be turned into the other, and §5.7 is explicit that both
      // are then listed rather than guessed at.
      final Recipe recipe = aRecipe(
        id: 'r',
        servings: 2,
        sections: <RecipeSection>[
          aSection(
            id: 'a',
            name: 'Main',
            sortOrder: 0,
            ingredients: <RecipeIngredient>[
              anIngredient(
                'tomatoes',
                amount: 2,
                unit: Units.item,
                sectionId: 'a',
              ),
              anIngredient(
                'tomatoes',
                amount: 200,
                unit: Units.gram,
                sectionId: 'a',
              ),
            ],
          ),
        ],
      );

      final ConsolidatedIngredient tomatoes = _byName(
        IngredientConsolidator.flatten(recipe),
        'tomatoes',
      );

      expect(tomatoes.isMixedUnit, isTrue);
      expect(tomatoes.quantities, hasLength(2));
    });
  });
}
