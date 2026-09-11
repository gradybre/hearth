import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/repair_queue.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Everything in the library that is not finished (review N04).
///
/// The three gap kinds already existed on one recipe's macros; what did not
/// exist was a way to ask the whole library. Finding the four recipes with
/// unmatched lines meant opening every recipe in turn, which is why nobody
/// did it.
void main() {
  Food flour() => aFood(
    'Plain flour',
    id: 'f-flour',
    servingOptions: <ServingOption>[
      aServing(
        id: 's-flour',
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 364, proteinG: 10, carbG: 76, fatG: 1),
      ),
    ],
  );

  /// A food that only knows itself by the each, for a line written by weight.
  ///
  /// Cups against a gram-only food converts fine — the converter knows water
  /// and the fixture density — so the honest unconvertible pair is a count
  /// against a weight: nothing can say what one egg weighs.
  Food egg() => aFood(
    'Egg',
    id: 'f-egg',
    servingOptions: <ServingOption>[
      aServing(
        id: 's-egg',
        amount: 1,
        unit: Units.item,
        macros: const Macros(kcal: 78, proteinG: 6, carbG: 1, fatG: 5),
      ),
    ],
  );

  Recipe recipeWith(List<RecipeIngredient> lines, {String id = 'r-1'}) =>
      aRecipe(
        id: id,
        title: 'Something',
        sections: <RecipeSection>[aSection(id: 's1', ingredients: lines)],
      );

  Map<String, Food> library(List<Food> foods) => <String, Food>{
    for (final Food f in foods) f.id: f,
  };

  group('what lands in the queue', () {
    test('a line with no food matched', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient('shallots', amount: 2, unit: Units.item),
          ]),
        ],
        foods: library(<Food>[]),
      );

      expect(queue.recipes, hasLength(1));
      expect(queue.recipes.single.unmatched, hasLength(1));
      expect(queue.outstanding, 1);
    });

    test('a line whose food has no serving in that unit', () {
      // The one the summary used to hide: linked, and still unusable.
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient('egg', amount: 50, unit: Units.gram, foodId: 'f-egg'),
          ]),
        ],
        foods: library(<Food>[egg()]),
      );

      expect(queue.recipes.single.unconvertible, hasLength(1));
      expect(queue.recipes.single.unmatched, isEmpty);
    });

    test('a line with no amount on it', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient('flour', foodId: 'f-flour'),
          ]),
        ],
        foods: library(<Food>[flour()]),
      );

      expect(queue.recipes.single.withoutQuantity, hasLength(1));
    });

    test('and a food that cannot be logged at all', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: const <Recipe>[],
        foods: library(<Food>[aFood('Half an import', id: 'f-empty')]),
      );

      expect(queue.unloggable, hasLength(1));
      expect(queue.outstanding, 1);
    });
  });

  group('what stays out of it', () {
    test('a finished recipe', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient(
              'flour',
              amount: 200,
              unit: Units.gram,
              foodId: 'f-flour',
            ),
          ]),
        ],
        foods: library(<Food>[flour()]),
      );

      expect(queue.recipes, isEmpty);
      expect(queue.outstanding, 0);
      // Not `isEmpty`: the flour states no fibre, sodium or cholesterol, so
      // it is on the quiet list. Nothing is *wrong* with this recipe, which
      // is what `outstanding` is for.
      expect(queue.silent, hasLength(1));
    });

    test('a seasoning marked as needing no match', () {
      // Salt in a bread recipe is not a gap, and saying it is would make this
      // list permanently full of the one thing that is already answered.
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient(
              'flour',
              amount: 200,
              unit: Units.gram,
              foodId: 'f-flour',
            ),
            anIngredient(
              'salt',
              amount: 1,
              unit: Units.tsp,
              needsNoMatch: true,
            ),
          ]),
        ],
        foods: library(<Food>[flour()]),
      );

      expect(queue.recipes, isEmpty);
    });

    test('an optional line excluded on purpose', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient(
              'flour',
              amount: 200,
              unit: Units.gram,
              foodId: 'f-flour',
            ),
            anIngredient('parsley to garnish', optional: true),
          ]),
        ],
        foods: library(<Food>[flour()]),
      );

      expect(queue.recipes, isEmpty);
    });

    test('a recipe nobody has written the ingredients for yet', () {
      // Unwritten, not broken — and it would otherwise sit at the top of this
      // list from the moment somebody created it.
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[aRecipe(id: 'r-blank', title: 'Something')],
        foods: library(<Food>[]),
      );

      expect(queue.recipes, isEmpty);
      expect(queue.isEmpty, isTrue);
    });
  });

  group('the quiet ones', () {
    Food silent() => aFood(
      'Own-brand oats',
      id: 'f-oats',
      servingOptions: <ServingOption>[
        aServing(
          id: 's-oats',
          amount: 40,
          unit: Units.gram,
          macros: const Macros(kcal: 150, proteinG: 5, carbG: 27, fatG: 3),
        ),
      ],
    );

    Food speaks() => aFood(
      'Wholemeal bread',
      id: 'f-bread',
      servingOptions: <ServingOption>[
        aServing(
          id: 's-bread',
          amount: 1,
          unit: Units.slice,
          macros: const Macros(
            kcal: 90,
            proteinG: 4,
            carbG: 15,
            fatG: 1,
            fiberG: 2.4,
          ),
        ),
      ],
    );

    test('a food a recipe uses that states none of the three', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient(
              'oats',
              amount: 40,
              unit: Units.gram,
              foodId: 'f-oats',
            ),
          ]),
        ],
        foods: library(<Food>[silent()]),
      );

      expect(queue.silent, hasLength(1));
      // Not a fault: §5.6 has these as optional and nullable, so the count of
      // things actually wrong stays at nothing.
      expect(queue.outstanding, 0);
      expect(queue.isEmpty, isFalse);
    });

    test('but not one no recipe uses', () {
      // Every food from a database would otherwise be on this list, and it
      // would bury the lines above it.
      final RepairQueue queue = RepairQueue.build(
        recipes: const <Recipe>[],
        foods: library(<Food>[silent()]),
      );

      expect(queue.silent, isEmpty);
    });

    test('and not one that states even a single nutrient', () {
      final RepairQueue queue = RepairQueue.build(
        recipes: <Recipe>[
          recipeWith(<RecipeIngredient>[
            anIngredient(
              'bread',
              amount: 2,
              unit: Units.slice,
              foodId: 'f-bread',
            ),
          ]),
        ],
        foods: library(<Food>[speaks()]),
      );

      expect(queue.silent, isEmpty);
    });
  });

  test('the worst recipe is first', () {
    // Sorted rather than left in library order, so the one that will take
    // longest is not the one you have to scroll to find.
    final RepairQueue queue = RepairQueue.build(
      recipes: <Recipe>[
        recipeWith(<RecipeIngredient>[
          anIngredient('a', amount: 1, unit: Units.item),
        ], id: 'r-one'),
        recipeWith(<RecipeIngredient>[
          anIngredient('a', amount: 1, unit: Units.item),
          anIngredient('b', amount: 1, unit: Units.item),
          anIngredient('c', amount: 1, unit: Units.item),
        ], id: 'r-three'),
      ],
      foods: library(<Food>[]),
    );

    expect(queue.recipes.first.recipe.id, 'r-three');
    expect(queue.recipes.first.total, 3);
    expect(queue.outstanding, 4);
  });
}
