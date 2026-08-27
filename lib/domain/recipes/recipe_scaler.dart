import 'package:meta/meta.dart';

import '../models/recipe.dart';
import '../text/text_normaliser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';

/// Something scaling can't safely do for the cook (spec §5.2).
enum ScalingWarningKind {
  /// Salt and other seasoning: doubling a recipe rarely means doubling this.
  seasoning,

  /// Baking powder, soda, yeast: leavening does not scale linearly.
  leavening,

  /// Bake and cook times change with pan size and volume, not with a
  /// multiplier. Timers are never auto-adjusted.
  cookTime,
}

/// A flag shown alongside a scaled recipe. Advisory only — nothing is silently
/// adjusted on the cook's behalf.
@immutable
class ScalingWarning {
  const ScalingWarning({required this.kind, required this.subject});

  final ScalingWarningKind kind;

  /// The ingredient name, or the step text, the warning is about.
  final String subject;

  @override
  bool operator ==(Object other) =>
      other is ScalingWarning && other.kind == kind && other.subject == subject;

  @override
  int get hashCode => Object.hash(kind, subject);
}

/// The result of scaling: the new recipe plus anything the cook should check.
@immutable
class ScaledRecipe {
  const ScaledRecipe({
    required this.recipe,
    required this.factor,
    required this.warnings,
  });

  final Recipe recipe;
  final double factor;
  final List<ScalingWarning> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Recipe scaling with unit normalisation (spec §5.2).
///
/// Scaling multiplies stored canonical amounts and then re-picks a display
/// unit, so 1 tsp tripled reads as 1 tbsp. The stored value is never rounded,
/// so scaling up and back down returns the original.
abstract final class RecipeScaler {
  static const List<String> _seasonings = <String>[
    'salt',
    'kosher salt',
    'sea salt',
    'table salt',
    'pepper',
    'black pepper',
    'cayenne',
    'red pepper flakes',
  ];

  static const List<String> _leaveners = <String>[
    'baking powder',
    'baking soda',
    'yeast',
    'active dry yeast',
    'instant yeast',
    'cream of tartar',
  ];

  /// Scales a whole recipe by [factor] — the "2x" control.
  ///
  /// [servings] scales with it, so per-serving macros are unchanged, which is
  /// the correct behaviour: scaling changes how much you make, not what a
  /// serving is.
  static ScaledRecipe byMultiplier(
    Recipe recipe,
    double factor, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    if (factor <= 0) {
      throw ArgumentError.value(factor, 'factor', 'must be greater than zero');
    }
    final Recipe scaled = recipe.copyWith(
      servings: recipe.servings * factor,
      sections: <RecipeSection>[
        for (final RecipeSection section in recipe.sections)
          _scaleSection(section, factor, system),
      ],
    );
    return ScaledRecipe(
      recipe: scaled,
      factor: factor,
      warnings: warningsFor(recipe, factor),
    );
  }

  /// Scales to a target yield — "I want 6" — the primary control (spec §5.2).
  static ScaledRecipe toServings(
    Recipe recipe,
    double targetServings, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    if (targetServings <= 0) {
      throw ArgumentError.value(
        targetServings,
        'targetServings',
        'must be greater than zero',
      );
    }
    if (recipe.servings <= 0) {
      throw ArgumentError.value(
        recipe.servings,
        'recipe.servings',
        'recipe has no yield to scale from',
      );
    }
    return byMultiplier(
      recipe,
      targetServings / recipe.servings,
      system: system,
    );
  }

  /// Scales a single section — "scale just the sauce".
  ///
  /// Available but not the default path (spec §5.2). The recipe's yield is
  /// deliberately left alone: making double sauce doesn't double the dish.
  static ScaledRecipe section(
    Recipe recipe,
    String sectionId,
    double factor, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    if (factor <= 0) {
      throw ArgumentError.value(factor, 'factor', 'must be greater than zero');
    }
    if (!recipe.sections.any((RecipeSection s) => s.id == sectionId)) {
      throw ArgumentError.value(sectionId, 'sectionId', 'no such section');
    }
    final Recipe scaled = recipe.copyWith(
      sections: <RecipeSection>[
        for (final RecipeSection s in recipe.sections)
          if (s.id == sectionId) _scaleSection(s, factor, system) else s,
      ],
    );
    final RecipeSection target = recipe.sections.firstWhere(
      (RecipeSection s) => s.id == sectionId,
    );
    return ScaledRecipe(
      recipe: scaled,
      factor: factor,
      warnings: <ScalingWarning>[
        ..._ingredientWarnings(target.ingredients),
        if (factor != 1) ..._timerWarnings(target.steps),
      ],
    );
  }

  /// What the cook should double-check after scaling by [factor].
  static List<ScalingWarning> warningsFor(Recipe recipe, double factor) {
    if (factor == 1) return const <ScalingWarning>[];
    return <ScalingWarning>[
      ..._ingredientWarnings(recipe.allIngredients),
      ..._timerWarnings(recipe.allSteps),
    ];
  }

  static RecipeSection _scaleSection(
    RecipeSection section,
    double factor,
    UnitSystem system,
  ) => section.copyWith(
    ingredients: <RecipeIngredient>[
      for (final RecipeIngredient ingredient in section.ingredients)
        _scaleIngredient(ingredient, factor, system),
    ],
  );

  static RecipeIngredient _scaleIngredient(
    RecipeIngredient ingredient,
    double factor,
    UnitSystem system,
  ) {
    final Quantity? quantity = ingredient.quantity;
    if (quantity == null) return ingredient;
    return ingredient.copyWith(
      quantity: UnitConverter.normalise(
        quantity.scaledBy(factor),
        system: system,
      ),
    );
  }

  static List<ScalingWarning> _ingredientWarnings(
    Iterable<RecipeIngredient> ingredients,
  ) {
    final List<ScalingWarning> warnings = <ScalingWarning>[];
    for (final RecipeIngredient ingredient in ingredients) {
      final String key = normaliseKey(ingredient.name);
      if (key.isEmpty) continue;
      if (_matches(key, _leaveners)) {
        warnings.add(
          ScalingWarning(
            kind: ScalingWarningKind.leavening,
            subject: ingredient.name,
          ),
        );
      } else if (_matches(key, _seasonings)) {
        warnings.add(
          ScalingWarning(
            kind: ScalingWarningKind.seasoning,
            subject: ingredient.name,
          ),
        );
      }
    }
    return warnings;
  }

  static List<ScalingWarning> _timerWarnings(
    Iterable<RecipeStep> steps,
  ) => <ScalingWarning>[
    for (final RecipeStep step in steps)
      if (step.hasTimer)
        ScalingWarning(kind: ScalingWarningKind.cookTime, subject: step.text),
  ];

  static bool _matches(String key, List<String> terms) =>
      terms.any((String term) => key == term || key.contains(term));
}
