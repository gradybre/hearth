import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../models/recipe.dart';
import 'macro_calculator.dart';

/// What is wrong with one recipe's nutrition, and how many of each (N04).
///
/// The three kinds are kept apart because they ask different things. A line
/// with no food wants a food; a line whose food has no serving in that unit
/// wants either a serving or a different food; a line with no amount wants an
/// amount. Telling somebody "four problems" and making them open the recipe
/// to find out which four is the state this queue exists to end.
@immutable
class RecipeRepair {
  const RecipeRepair({
    required this.recipe,
    required this.unmatched,
    required this.unconvertible,
    required this.withoutQuantity,
  });

  final Recipe recipe;

  /// Lines with no food matched to them.
  final List<RecipeIngredient> unmatched;

  /// Lines whose food has no serving the line's unit can reach.
  final List<RecipeIngredient> unconvertible;

  /// Lines with no amount, so nothing can be computed from them.
  final List<RecipeIngredient> withoutQuantity;

  int get total =>
      unmatched.length + unconvertible.length + withoutQuantity.length;

  /// The gaps in the order a fix would take them, worst first.
  ///
  /// Unmatched leads because it is the most common and the most mechanical;
  /// an amount is last because it usually means re-reading the source.
  List<RecipeIngredient> get all => <RecipeIngredient>[
    ...unmatched,
    ...unconvertible,
    ...withoutQuantity,
  ];
}

/// Why a food is in the queue.
enum FoodRepairKind {
  /// It cannot be logged at all: no serving, or every serving is zero and it
  /// has not been marked zero-calorie. [Food.needsAttention].
  cannotBeLogged,

  /// It states none of fibre, sodium or cholesterol.
  ///
  /// **Not a fault.** §5.6 has these as optional and nullable, and a food
  /// that never said is being honest rather than broken — the bars already
  /// say which silence it is. It is here because a recipe made of such foods
  /// can never total them, and somebody who cares about that wants the list.
  silentOnMinors,
}

@immutable
class FoodRepair {
  const FoodRepair({required this.food, required this.kind});

  final Food food;
  final FoodRepairKind kind;
}

/// Everything in the library that is not finished (review N04).
@immutable
class RepairQueue {
  const RepairQueue({required this.recipes, required this.foods});

  final List<RecipeRepair> recipes;
  final List<FoodRepair> foods;

  /// Foods that cannot be logged as they stand — the ones that are wrong.
  List<FoodRepair> get unloggable => <FoodRepair>[
    for (final FoodRepair f in foods)
      if (f.kind == FoodRepairKind.cannotBeLogged) f,
  ];

  /// Foods that simply never stated the three — the ones that are quiet.
  List<FoodRepair> get silent => <FoodRepair>[
    for (final FoodRepair f in foods)
      if (f.kind == FoodRepairKind.silentOnMinors) f,
  ];

  /// How many things are actually wrong.
  ///
  /// Deliberately excludes [FoodRepairKind.silentOnMinors]: a count that
  /// included them would never reach zero for a household whose foods came
  /// from a database, and a queue that cannot be emptied is a badge nobody
  /// reads twice.
  int get outstanding =>
      recipes.fold(0, (int n, RecipeRepair r) => n + r.total) +
      unloggable.length;

  bool get isEmpty => outstanding == 0 && silent.isEmpty;

  /// Reads the library and finds what is unfinished.
  ///
  /// Recipes with no ingredients at all are skipped: a recipe nobody has
  /// written the ingredients for yet is unwritten, not broken, and it would
  /// sit at the top of this list from the moment it was created.
  static RepairQueue build({
    required Iterable<Recipe> recipes,
    required Map<String, Food> foods,
  }) {
    final List<RecipeRepair> broken = <RecipeRepair>[];
    final Set<String> usedFoodIds = <String>{};

    for (final Recipe recipe in recipes) {
      if (recipe.allIngredients.isEmpty) continue;
      for (final RecipeIngredient line in recipe.allIngredients) {
        if (line.foodId case final String id) usedFoodIds.add(id);
      }

      final RecipeMacros macros = MacroCalculator.forRecipe(
        recipe,
        foods: foods,
      );
      if (!macros.isIncomplete) continue;
      broken.add(
        RecipeRepair(
          recipe: recipe,
          unmatched: macros.ingredientsMissingFood,
          unconvertible: macros.ingredientsUnconvertible,
          withoutQuantity: macros.ingredientsWithoutQuantity,
        ),
      );
    }

    // Worst first, so the recipe that would take longest is not the one you
    // have to scroll to find.
    broken.sort((RecipeRepair a, RecipeRepair b) => b.total.compareTo(a.total));

    final List<FoodRepair> foodRepairs = <FoodRepair>[
      for (final Food food in foods.values)
        if (food.needsAttention)
          FoodRepair(food: food, kind: FoodRepairKind.cannotBeLogged)
        // Only the ones a recipe actually uses. Every other food in a
        // database-sourced library would otherwise be on this list, which
        // would bury the two lines above it.
        else if (usedFoodIds.contains(food.id) && _statesNoMinors(food))
          FoodRepair(food: food, kind: FoodRepairKind.silentOnMinors),
    ];

    return RepairQueue(recipes: broken, foods: foodRepairs);
  }

  /// True when not one of this food's servings names fibre, sodium or
  /// cholesterol.
  ///
  /// One serving stating one of them is enough to keep it off the list: the
  /// point is foods that can never contribute, not foods that are partly
  /// filled in.
  static bool _statesNoMinors(Food food) => food.servingOptions.every(
    (ServingOption o) =>
        MinorNutrient.values.every((MinorNutrient n) => !o.macros.knows(n)),
  );
}
