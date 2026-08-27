import 'package:meta/meta.dart';

import '../models/recipe.dart';
import '../text/text_normaliser.dart';
import '../units/density.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';

/// Looks up a density in g/ml for an ingredient name, or null when unknown.
///
/// Defaults to the generic [DensityTable], but the data layer can pass a
/// lookup backed by the matched food's own serving weights, which are far more
/// accurate than a category average (spec §5.5).
typedef DensityLookup = double? Function(String ingredientName);

/// One ingredient after duplicates have been summed.
///
/// [quantities] normally holds a single entry. It holds more when the same
/// ingredient appeared in units that can't be reconciled — 2 tbsp of butter in
/// one recipe and 50 g in another with no density known. Spec §5.7 is explicit
/// that both are then listed under one line item rather than guessed at.
@immutable
class ConsolidatedIngredient {
  const ConsolidatedIngredient({
    required this.key,
    required this.displayName,
    required this.quantities,
    this.foodId,
    this.hasUnquantified = false,
    this.sourceRecipeIds = const <String>[],
  });

  /// The normalised string duplicates were matched on.
  final String key;

  /// The name as first encountered, for display.
  final String displayName;

  final String? foodId;

  /// Summed amounts, one per unit kind that could not be merged into another.
  final List<Quantity> quantities;

  /// True when at least one contributing line had no quantity ("to taste"),
  /// so the total understates what's needed.
  final bool hasUnquantified;

  /// Which recipes this line came from, for the shopping list (spec §4).
  final List<String> sourceRecipeIds;

  bool get isMixedUnit => quantities.length > 1;

  @override
  String toString() => 'ConsolidatedIngredient($displayName, $quantities)';
}

/// Section flatten and cross-recipe merge — the two stages of shopping
/// aggregation (spec §5.7), and the basis of whole-recipe nutrition.
///
/// Grouped view is for cooking; flattened view is for shopping and nutrition
/// (spec §5.2).
abstract final class IngredientConsolidator {
  /// Stage one: roll a recipe's sections up into a single list, summing
  /// ingredients that appear in more than one section (olive oil in both the
  /// sauce and the main).
  ///
  /// Optional/to-taste ingredients are excluded by default — they belong on
  /// neither the shopping list nor the macro total (spec §5.2).
  static List<ConsolidatedIngredient> flatten(
    Recipe recipe, {
    bool includeOptional = false,
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
  }) => _group(
    <_Entry>[
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        if (includeOptional || !ingredient.isOptional)
          _Entry(ingredient: ingredient, recipeId: recipe.id),
    ],
    densityLookup,
    system,
  );

  /// Stage two: merge the week's recipes into one list, combining ingredients
  /// that appear in several of them.
  ///
  /// [servingsFor] gives the number of servings planned for each recipe, so a
  /// recipe planned at half its yield contributes half its ingredients. Absent
  /// entries default to the recipe as written.
  static List<ConsolidatedIngredient> mergeRecipes(
    Iterable<Recipe> recipes, {
    Map<String, double> servingsFor = const <String, double>{},
    bool includeOptional = false,
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
  }) {
    final List<_Entry> entries = <_Entry>[];
    for (final Recipe recipe in recipes) {
      final double planned = servingsFor[recipe.id] ?? recipe.servings;
      final double factor = recipe.servings > 0 && planned > 0
          ? planned / recipe.servings
          : 1;
      for (final RecipeIngredient ingredient in recipe.allIngredients) {
        if (!includeOptional && ingredient.isOptional) continue;
        entries.add(
          _Entry(
            ingredient: factor == 1
                ? ingredient
                : ingredient.copyWith(
                    quantity: ingredient.quantity?.scaledBy(factor),
                  ),
            recipeId: recipe.id,
          ),
        );
      }
    }
    return _group(entries, densityLookup, system);
  }

  static List<ConsolidatedIngredient> _group(
    List<_Entry> entries,
    DensityLookup densityLookup,
    UnitSystem system,
  ) {
    final Map<String, List<_Entry>> grouped = <String, List<_Entry>>{};
    for (final _Entry entry in entries) {
      // Match on the food when one is attached — two different strings that
      // resolved to the same food are the same shopping line.
      final String key =
          entry.ingredient.foodId ?? normaliseKey(entry.ingredient.name);
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => <_Entry>[]).add(entry);
    }

    return <ConsolidatedIngredient>[
      for (final MapEntry<String, List<_Entry>> group in grouped.entries)
        _consolidate(group.key, group.value, densityLookup, system),
    ];
  }

  static ConsolidatedIngredient _consolidate(
    String key,
    List<_Entry> entries,
    DensityLookup densityLookup,
    UnitSystem system,
  ) {
    final String displayName = entries.first.ingredient.name;

    // Sum within each unit kind first — that part is always exact.
    final Map<UnitKind, Quantity> byKind = <UnitKind, Quantity>{};
    bool hasUnquantified = false;
    for (final _Entry entry in entries) {
      final Quantity? quantity = entry.ingredient.quantity;
      if (quantity == null) {
        hasUnquantified = true;
        continue;
      }
      final Quantity? existing = byKind[quantity.kind];
      byKind[quantity.kind] = existing == null ? quantity : existing + quantity;
    }

    final List<Quantity> quantities = _unify(
      byKind,
      displayName,
      densityLookup,
      system,
    );

    return ConsolidatedIngredient(
      key: key,
      displayName: displayName,
      foodId: entries
          .map((_Entry e) => e.ingredient.foodId)
          .firstWhere((String? id) => id != null, orElse: () => null),
      quantities: quantities,
      hasUnquantified: hasUnquantified,
      sourceRecipeIds: entries
          .map((_Entry e) => e.recipeId)
          .toSet()
          .toList(growable: false),
    );
  }

  /// Reduces per-kind totals to one quantity where density allows, and leaves
  /// them side by side where it doesn't.
  static List<Quantity> _unify(
    Map<UnitKind, Quantity> byKind,
    String displayName,
    DensityLookup densityLookup,
    UnitSystem system,
  ) {
    if (byKind.isEmpty) return const <Quantity>[];
    if (byKind.length == 1) {
      return <Quantity>[
        UnitConverter.normalise(byKind.values.first, system: system),
      ];
    }

    final double? density = densityLookup(displayName);
    final bool hasVolume = byKind.containsKey(UnitKind.volume);
    final bool hasMass = byKind.containsKey(UnitKind.mass);

    if (density != null && hasVolume && hasMass) {
      // Weight is the more useful unit at the shop, so collapse into grams.
      final ConversionResult converted = UnitConverter.crossKind(
        byKind[UnitKind.volume]!,
        UnitKind.mass,
        gramsPerMillilitre: density,
      );
      if (converted.isExact) {
        final Quantity merged = byKind[UnitKind.mass]! + converted.quantity;
        final Map<UnitKind, Quantity> rest = <UnitKind, Quantity>{
          ...byKind,
          UnitKind.mass: merged,
        }..remove(UnitKind.volume);
        return <Quantity>[
          for (final Quantity q in rest.values)
            UnitConverter.normalise(q, system: system),
        ];
      }
    }

    // Counts never convert, and without a density neither does volume<->mass.
    // List them together rather than inventing a total (spec §5.7).
    return <Quantity>[
      for (final Quantity q in byKind.values)
        UnitConverter.normalise(q, system: system),
    ];
  }
}

@immutable
class _Entry {
  const _Entry({required this.ingredient, required this.recipeId});

  final RecipeIngredient ingredient;
  final String recipeId;
}
