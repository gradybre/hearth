import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../models/recipe.dart';
import '../recipes/macro_calculator.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'restaurant_menu.dart';

/// A published menu adjustment is one reviewed portion applied once. Used at
/// both usual entry and preselected portion-save boundaries; historical logs
/// do not go through this current-menu policy.
String? usualOrderModifierProblem(Recipe recipe, Map<String, Food> foods) {
  final Map<String, int> occurrences = <String, int>{};
  for (final RecipeIngredient ingredient in recipe.allIngredients) {
    if (ingredient.isOptional || ingredient.needsNoMatch) continue;
    if (ingredient.foodId case final String id) {
      occurrences[id] = (occurrences[id] ?? 0) + 1;
    }
  }
  for (final RecipeIngredient ingredient in recipe.allIngredients) {
    if (ingredient.isOptional || ingredient.needsNoMatch) continue;
    final Food? food = foods[ingredient.foodId];
    if (food == null || food.isDeleted || !food.isModifier) continue;
    final UsualOrderComponent component = UsualOrderProjection._resolve(
      ingredient,
      food,
      food.brand ?? '',
      repeated: (occurrences[food.id] ?? 0) > 1,
    );
    if (component.pick == null || component.pick!.count != 1) {
      return 'A published menu adjustment can be applied only once. '
          'Review the saved order in Details before logging.';
    }
  }
  return null;
}

/// What a saved restaurant recipe can faithfully restore into today's menu.
/// Quantities describe the whole recipe; its yield is never a pick multiplier.
@immutable
class UsualOrderProjection {
  const UsualOrderProjection._({
    required this.recipe,
    required this.restaurant,
    required this.components,
  });

  factory UsualOrderProjection.resolve({
    required Recipe recipe,
    required String restaurant,
    required Map<String, Food> foods,
  }) {
    final Map<String, int> occurrences = <String, int>{};
    for (final RecipeIngredient ingredient in recipe.allIngredients) {
      if (ingredient.foodId case final String id) {
        occurrences[id] = (occurrences[id] ?? 0) + 1;
      }
    }
    return UsualOrderProjection._(
      recipe: recipe,
      restaurant: restaurant,
      components: <UsualOrderComponent>[
        for (final RecipeIngredient ingredient in recipe.allIngredients)
          _resolve(
            ingredient,
            foods[ingredient.foodId],
            restaurant,
            repeated: (occurrences[ingredient.foodId] ?? 0) > 1,
          ),
      ],
    );
  }

  final Recipe recipe;
  final String restaurant;
  final List<UsualOrderComponent> components;

  List<MenuPick> get picks => <MenuPick>[
    for (final UsualOrderComponent component in components)
      if (component.pick case final MenuPick pick) pick,
  ];

  List<UsualOrderComponent> get unresolved => components
      .where((UsualOrderComponent component) => component.reason != null)
      .toList();

  /// Nutrients from current, available menu foods, with exclusions and gaps
  /// still represented by the shared recipe calculator.
  RecipeMacros get nutrition => MacroCalculator.forRecipe(
    recipe,
    foods: <String, Food>{
      for (final UsualOrderComponent component in components)
        if (component.food case final Food food) food.id: food,
    },
  );

  /// A changed portion definition cannot reinterpret a held selection. The
  /// caller asks the person to reset/review instead; nutrient-only changes
  /// are safe to read live because the selected quantity has not changed.
  bool hasSamePortionBasis(UsualOrderProjection current) {
    if (recipe.id != current.recipe.id ||
        recipe.servings != current.recipe.servings) {
      return false;
    }
    if (components.length != current.components.length) return false;
    for (int i = 0; i < components.length; i++) {
      final UsualOrderComponent before = components[i];
      final UsualOrderComponent after = current.components[i];
      if (before.ingredient.id != after.ingredient.id ||
          before.ingredient.foodId != after.ingredient.foodId ||
          before.ingredient.quantity != after.ingredient.quantity ||
          before.ingredient.quantity?.preferredUnit !=
              after.ingredient.quantity?.preferredUnit ||
          before.ingredient.isOptional != after.ingredient.isOptional ||
          before.ingredient.needsNoMatch != after.ingredient.needsNoMatch ||
          before.reason != after.reason ||
          before.pick?.count != after.pick?.count ||
          before.food?.defaultServing?.amount !=
              after.food?.defaultServing?.amount ||
          before.food?.defaultServing?.amount.preferredUnit !=
              after.food?.defaultServing?.amount.preferredUnit ||
          before.food?.isModifier != after.food?.isModifier) {
        return false;
      }
    }
    return true;
  }

  static UsualOrderComponent _resolve(
    RecipeIngredient ingredient,
    Food? candidate,
    String restaurant, {
    required bool repeated,
  }) {
    final Food? food =
        candidate != null &&
            !candidate.isDeleted &&
            candidate.source == FoodSource.restaurant &&
            candidate.brand?.trim().toLowerCase() ==
                restaurant.trim().toLowerCase()
        ? candidate
        : null;
    String? reason;
    double? count;
    final Quantity? amount = ingredient.quantity;
    final ServingOption? serving = food?.defaultServing;
    if (ingredient.isOptional || ingredient.needsNoMatch) {
      reason = 'Excluded from the saved nutrition; kept for recipe review.';
    } else if (food == null) {
      reason = 'This component is unavailable on the current menu.';
    } else if (repeated) {
      reason = 'Used on more than one saved line; review the amounts together.';
    } else if (amount == null ||
        !amount.canonicalAmount.isFinite ||
        amount.isZero) {
      reason = 'The saved line has no usable amount.';
    } else if (serving == null ||
        !serving.amount.canonicalAmount.isFinite ||
        serving.amount.canonicalAmount <= 0) {
      reason = 'The current menu has no usable portion for this component.';
    } else if (amount.kind != serving.amount.kind ||
        (amount.kind == UnitKind.count &&
            amount.preferredUnit != serving.amount.preferredUnit)) {
      // The menu picker is expressed in its current default portion. A
      // second serving or a density may cost the original recipe, but it
      // does not prove that changing its basis keeps those same nutrients.
      reason = 'The saved unit differs from the menu portion; review it.';
    } else {
      count = amount.canonicalAmount / serving.amount.canonicalAmount;
      if (!count.isFinite || count == 0) {
        reason = 'The saved amount cannot be represented as a menu portion.';
      } else if (food.isModifier && count != 1) {
        reason = 'A published menu adjustment can be applied only once.';
      }
    }
    return UsualOrderComponent(
      ingredient: ingredient,
      food: food,
      reason: reason,
      pick: reason == null ? MenuPick(food: food!, count: count!) : null,
    );
  }
}

@immutable
class UsualOrderComponent {
  const UsualOrderComponent({
    required this.ingredient,
    required this.food,
    required this.reason,
    required this.pick,
  });

  final RecipeIngredient ingredient;
  final Food? food;
  final String? reason;
  final MenuPick? pick;
}

/// A signed change from the saved whole order, retaining each nutrient's sign.
@immutable
class UsualOrderChange {
  const UsualOrderChange({required this.pick});

  final MenuPick pick;
  bool get added => pick.count > 0;
  Macros? get nutrients =>
      pick.food.defaultServing?.macros.scaledBy(pick.count);

  static List<UsualOrderChange> between(
    List<MenuPick> base,
    List<MenuPick> selected,
  ) {
    final Map<String, MenuPick> before = <String, MenuPick>{
      for (final MenuPick pick in base) pick.food.id: pick,
    };
    final Map<String, MenuPick> after = <String, MenuPick>{
      for (final MenuPick pick in selected) pick.food.id: pick,
    };
    return <UsualOrderChange>[
      for (final String id in <String>{...before.keys, ...after.keys})
        if ((after[id]?.count ?? 0) != (before[id]?.count ?? 0))
          UsualOrderChange(
            pick: MenuPick(
              food: (after[id] ?? before[id])!.food,
              count: (after[id]?.count ?? 0) - (before[id]?.count ?? 0),
            ),
          ),
    ];
  }
}
