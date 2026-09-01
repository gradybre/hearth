import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/recipe.dart';
import 'ingredient_matcher.dart';

/// One ingredient line a default would now answer.
@immutable
class DefaultSweepChange {
  const DefaultSweepChange({
    required this.recipe,
    required this.ingredient,
    required this.food,
  });

  final Recipe recipe;
  final RecipeIngredient ingredient;
  final Food food;

  /// Identifies the line across a rebuild, so ticking one survives the list
  /// being recomputed.
  String get key => ingredient.id;
}

/// Applying newly-marked defaults to recipes already saved (spec §5.3).
///
/// Marking a default changes what *future* matching does; it says nothing
/// about the recipes already sitting in the library with lines nobody ever
/// matched. Those are exactly the ones worth fixing — the whole reason for
/// marking a default is that the question keeps being asked — but rewriting
/// saved recipe data in the background is not a thing to do quietly
/// (CLAUDE.md rule 4). So this proposes, and something else confirms.
///
/// Deliberately conservative in three ways:
///
///  * only lines with **no food attached** are touched, so nothing anybody
///    matched — or deliberately unmatched and left that way — is second-guessed;
///  * only lines exactly **one** default answers, for the same reason the
///    matcher itself stops there: "milk" against three milks has not said
///    which, and a sweep is the worst place to guess;
///  * optional lines are included, because a line being excluded from macros
///    does not make its food unknowable.
abstract final class DefaultSweep {
  /// Every change marking defaults would make, across the whole library.
  static List<DefaultSweepChange> proposals({
    required List<Recipe> recipes,
    required List<Food> library,
  }) {
    final Map<String, Food> byId = <String, Food>{
      for (final Food food in library) food.id: food,
    };

    return <DefaultSweepChange>[
      for (final Recipe recipe in recipes)
        if (!recipe.isDeleted)
          for (final RecipeIngredient ingredient in recipe.allIngredients)
            if (ingredient.foodId == null)
              if (IngredientMatcher.defaultsFor(ingredient.name, library)
                  case final List<Food> found when found.length == 1)
                if (byId[found.single.id] case final Food food)
                  DefaultSweepChange(
                    recipe: recipe,
                    ingredient: ingredient,
                    food: food,
                  ),
    ];
  }

  /// [recipe] with [changes] attached, or the recipe unchanged when none of
  /// them are its own.
  ///
  /// Rebuilds the sections rather than mutating: a `Recipe` is immutable, and
  /// the ingredient rows carry ids the store writes against, so this has to
  /// keep every one of them.
  static Recipe applyTo(Recipe recipe, List<DefaultSweepChange> changes) {
    final Map<String, String> foodByIngredient = <String, String>{
      for (final DefaultSweepChange change in changes)
        if (change.recipe.id == recipe.id) change.ingredient.id: change.food.id,
    };
    if (foodByIngredient.isEmpty) return recipe;

    return recipe.copyWith(
      sections: <RecipeSection>[
        for (final RecipeSection section in recipe.sections)
          section.copyWith(
            ingredients: <RecipeIngredient>[
              for (final RecipeIngredient ingredient in section.ingredients)
                if (foodByIngredient[ingredient.id] case final String foodId)
                  ingredient.copyWith(foodId: foodId)
                else
                  ingredient,
            ],
          ),
      ],
    );
  }

  /// The recipes [changes] actually touch, each already updated.
  static List<Recipe> apply(List<DefaultSweepChange> changes) {
    final Map<String, Recipe> byId = <String, Recipe>{
      for (final DefaultSweepChange change in changes)
        change.recipe.id: change.recipe,
    };

    return <Recipe>[
      for (final Recipe recipe in byId.values) applyTo(recipe, changes),
    ];
  }
}
