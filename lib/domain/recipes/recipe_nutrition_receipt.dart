import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../models/recipe.dart';
import 'macro_calculator.dart';

/// A read-only explanation of an already computed recipe, on the same basis
/// as the screen that opened it. No food selection or conversion is repeated.
@immutable
class RecipeNutritionReceipt {
  RecipeNutritionReceipt({
    required this.recipe,
    required this.calculation,
    required Map<String, Food> foods,
    required this.wholeDish,
    Recipe? authoredRecipe,
  }) : authoredRecipe = authoredRecipe ?? recipe {
    final List<RecipeIngredient> authored = this.authoredRecipe.allIngredients;
    // A scaled recipe keeps ingredient order. Editor previews can temporarily
    // reuse an id, so an id-keyed map would overwrite one line with another.
    ingredients = List<IngredientNutritionReceipt>.unmodifiable(
      <IngredientNutritionReceipt>[
        for (int i = 0; i < calculation.ingredients.length; i++)
          IngredientNutritionReceipt(
            authored: i < authored.length
                ? authored[i]
                : calculation.ingredients[i].ingredient,
            calculation: calculation.ingredients[i],
            food: foods[calculation.ingredients[i].ingredient.foodId],
            yieldServings: recipe.servings,
            wholeDish: wholeDish,
          ),
      ],
    );
  }

  final Recipe recipe;
  final Recipe authoredRecipe;
  final RecipeMacros calculation;
  final bool wholeDish;
  late final List<IngredientNutritionReceipt> ingredients;

  bool get hasValidYield => recipe.servings.isFinite && recipe.servings > 0;

  bool get isScaled =>
      hasValidYield &&
      authoredRecipe.servings.isFinite &&
      authoredRecipe.servings > 0 &&
      recipe.servings != authoredRecipe.servings;

  int get resolvedCount => calculation.ingredients
      .where((IngredientMacros row) => row.isResolved)
      .length;

  int get requiredCount => calculation.ingredients
      .where((IngredientMacros row) => row.isResolved || row.isDataGap)
      .length;

  /// An unresolved recipe has no available total, rather than a known zero.
  Macros? get shown => resolvedCount == 0 || (!wholeDish && !hasValidYield)
      ? null
      : wholeDish
      ? calculation.total
      : calculation.perServing;
}

@immutable
class IngredientNutritionReceipt {
  const IngredientNutritionReceipt({
    required this.authored,
    required this.calculation,
    required this.food,
    required this.yieldServings,
    required this.wholeDish,
  });

  final RecipeIngredient authored;
  final IngredientMacros calculation;
  final Food? food;
  final double yieldServings;
  final bool wholeDish;

  /// The calculator's zero placeholder for an uncounted line is not food
  /// nutrition. Only a resolved line can contribute a stated numeric zero.
  Macros? get contribution {
    if (!calculation.isResolved) return null;
    if (wholeDish) return calculation.macros;
    if (!yieldServings.isFinite || yieldServings <= 0) return null;
    return calculation.macros.scaledBy(1 / yieldServings);
  }
}
