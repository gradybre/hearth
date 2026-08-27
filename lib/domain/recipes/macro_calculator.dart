import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../models/recipe.dart';
import '../units/quantity.dart';
import '../units/unit_converter.dart';

/// Why an ingredient did or did not contribute to a recipe's macros.
///
/// The distinction that matters: [optionalExcluded] is a *deliberate*
/// exclusion, while the others are data gaps that must raise the recipe's
/// incomplete flag (spec §4, §5.2).
enum IngredientMacroStatus {
  /// Counted in full.
  resolved,

  /// Salt to taste, garnish — excluded on purpose, not a gap.
  optionalExcluded,

  /// No quantity on the line, so nothing can be computed.
  noQuantity,

  /// No food matched to this ingredient yet.
  noFoodMatch,

  /// Matched, but the ingredient's unit can't reach any of the food's serving
  /// sizes — a volume ingredient against a weight-only food with no known
  /// density.
  unconvertible,
}

/// One ingredient's contribution to a recipe.
@immutable
class IngredientMacros {
  const IngredientMacros({
    required this.ingredient,
    required this.macros,
    required this.status,
  });

  final RecipeIngredient ingredient;
  final Macros macros;
  final IngredientMacroStatus status;

  bool get isResolved => status == IngredientMacroStatus.resolved;

  /// True when this ingredient is a *gap* rather than a deliberate exclusion.
  bool get isDataGap => switch (status) {
    IngredientMacroStatus.resolved => false,
    IngredientMacroStatus.optionalExcluded => false,
    IngredientMacroStatus.noQuantity => true,
    IngredientMacroStatus.noFoodMatch => true,
    IngredientMacroStatus.unconvertible => true,
  };
}

/// A recipe's macros, whole and per serving, with the honesty flag attached.
@immutable
class RecipeMacros {
  const RecipeMacros({
    required this.total,
    required this.perServing,
    required this.ingredients,
  });

  /// Macros for the whole recipe as written.
  final Macros total;

  /// Macros for one serving — the default nutrition basis (spec §5.2).
  final Macros perServing;

  final List<IngredientMacros> ingredients;

  /// True when at least one ingredient couldn't be counted for want of data.
  ///
  /// Missing data flags, never blocks: the recipe still saves and still shows
  /// what is known (spec §5.3).
  bool get isIncomplete => ingredients.any((IngredientMacros i) => i.isDataGap);

  /// The ingredients behind [isIncomplete], for the UI to name explicitly.
  List<RecipeIngredient> get incompleteIngredients => <RecipeIngredient>[
    for (final IngredientMacros i in ingredients)
      if (i.isDataGap) i.ingredient,
  ];
}

/// Macro maths. Pure, exact, and unrounded (spec §9.1).
abstract final class MacroCalculator {
  /// Macros for [count] portions of one of a food's serving options — the
  /// logging path.
  static Macros forServings(ServingOption serving, double count) =>
      serving.macros.scaledBy(count);

  /// One ingredient's contribution, given the food it resolved to.
  static IngredientMacros forIngredient(
    RecipeIngredient ingredient, {
    Food? food,
  }) {
    if (ingredient.isOptional) {
      return IngredientMacros(
        ingredient: ingredient,
        macros: Macros.zero,
        status: IngredientMacroStatus.optionalExcluded,
      );
    }

    final Quantity? quantity = ingredient.quantity;
    if (quantity == null) {
      return IngredientMacros(
        ingredient: ingredient,
        macros: Macros.zero,
        status: IngredientMacroStatus.noQuantity,
      );
    }
    if (food == null || food.servingOptions.isEmpty) {
      return IngredientMacros(
        ingredient: ingredient,
        macros: Macros.zero,
        status: IngredientMacroStatus.noFoodMatch,
      );
    }

    // Prefer a serving measured the same way the ingredient is — no
    // conversion, no assumptions.
    final ServingOption? direct = food.servingForKind(quantity.kind);
    if (direct != null && direct.amount.canonicalAmount != 0) {
      final double ratio =
          quantity.canonicalAmount / direct.amount.canonicalAmount;
      return IngredientMacros(
        ingredient: ingredient,
        macros: direct.macros.scaledBy(ratio),
        status: IngredientMacroStatus.resolved,
      );
    }

    // Otherwise try to cross volume <-> weight, using the food's own density
    // first and the generic table only as a fallback.
    for (final ServingOption option in food.servingOptions) {
      if (option.amount.canonicalAmount == 0) continue;
      final ConversionResult converted = UnitConverter.crossKind(
        quantity,
        option.amount.kind,
        ingredient: food.name,
        gramsPerMillilitre: food.gramsPerMillilitre,
      );
      if (!converted.isExact) continue;
      final double ratio =
          converted.quantity.canonicalAmount / option.amount.canonicalAmount;
      return IngredientMacros(
        ingredient: ingredient,
        macros: option.macros.scaledBy(ratio),
        status: IngredientMacroStatus.resolved,
      );
    }

    return IngredientMacros(
      ingredient: ingredient,
      macros: Macros.zero,
      status: IngredientMacroStatus.unconvertible,
    );
  }

  /// A recipe's macros, derived live from its ingredients (spec §4).
  ///
  /// [foods] maps food id to food; an ingredient whose food is absent counts
  /// as unmatched rather than as zero calories.
  static RecipeMacros forRecipe(
    Recipe recipe, {
    Map<String, Food> foods = const <String, Food>{},
  }) {
    final List<IngredientMacros> parts = <IngredientMacros>[
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        forIngredient(
          ingredient,
          food: ingredient.foodId == null ? null : foods[ingredient.foodId],
        ),
    ];

    final Macros total = Macros.sum(
      parts.map((IngredientMacros p) => p.macros),
    );

    // Yield is required by spec §5.2, but a zero would turn every macro into
    // infinity — treat a missing yield as one serving rather than poisoning
    // the whole screen with NaN.
    final double servings = recipe.servings > 0 ? recipe.servings : 1;

    return RecipeMacros(
      total: total,
      perServing: total.scaledBy(1 / servings),
      ingredients: parts,
    );
  }
}
