import 'package:meta/meta.dart';

import '../models/recipe.dart';
import '../text/text_normaliser.dart';
import '../units/density.dart';
import '../units/mass_display_mode.dart';
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

    bool hasUnquantified = false;
    final List<Quantity> amounts = <Quantity>[];
    for (final _Entry entry in entries) {
      final Quantity? quantity = entry.ingredient.quantity;
      if (quantity == null) {
        hasUnquantified = true;
        continue;
      }
      amounts.add(quantity);
    }

    final List<Quantity> quantities = combine(
      amounts,
      displayName: displayName,
      densityLookup: densityLookup,
      system: system,
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

  /// Adds quantities of the same thing together.
  ///
  /// The arithmetic of a shopping line, extracted from the middle of
  /// [mergeRecipes] so that it has one implementation rather than two. A line
  /// now totals up several *contributions* — what the plan asks for, plus
  /// each recipe somebody added to the list by hand — and summing those has
  /// to mean exactly what summing an ingredient across recipes has always
  /// meant: volume pools with volume, mass with mass, a clove never with a
  /// head, and the two collapse into grams only where a density says they
  /// may (spec §5.7).
  ///
  /// Within a mass bucket, the resulting quantity's display hint is chosen by
  /// an explicit priority (pound > ounce > kilogram > gram) rather than by
  /// which contribution happened to arrive first, so "1 lb + 8 oz" and
  /// "8 oz + 1 lb" both read as "1.5 lb". [massDisplayMode], [packSize], and
  /// [packageUnit] are accepted for callers that also want them applied when
  /// the combined quantity is normalised, but they never get baked into the
  /// stored preferred-unit hint itself — that would overwrite authorship the
  /// way [UnitConverter.normalise] is careful not to.
  ///
  /// [displayName] is what the density table is asked about, so pass the
  /// line's name where there is one.
  static List<Quantity> combine(
    Iterable<Quantity> quantities, {
    String displayName = '',
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
    MassDisplayMode massDisplayMode = MassDisplayMode.automatic,
    Quantity? packSize,
    Unit? packageUnit,
  }) {
    // Sum within each bucket first — that part is always exact.
    final Map<String, Quantity> byBucket = <String, Quantity>{};
    for (final Quantity quantity in quantities) {
      final String bucket = _bucketFor(quantity);
      final Quantity? existing = byBucket[bucket];
      byBucket[bucket] = existing == null ? quantity : _sum(existing, quantity);
    }
    return _unify(
      byBucket,
      displayName,
      densityLookup,
      system,
      massDisplayMode,
      packSize,
      packageUnit,
    );
  }

  /// Adds two same-kind quantities, picking the preferred-unit hint of the
  /// sum explicitly rather than leaning on "whichever came first".
  ///
  /// For mass this is the pound > ounce > kilogram > gram priority described
  /// on [combine]. For volume and count — which don't have that ambiguity in
  /// practice — this keeps the original left-operand-wins behaviour.
  static Quantity _sum(Quantity a, Quantity b) {
    final double total = a.canonicalAmount + b.canonicalAmount;
    if (a.kind == UnitKind.mass) {
      return Quantity.canonical(
        canonicalAmount: total,
        kind: a.kind,
        preferredUnit: _preferMassUnit(a.preferredUnit, b.preferredUnit),
      );
    }
    return Quantity.canonical(
      canonicalAmount: total,
      kind: a.kind,
      preferredUnit: a.preferredUnit ?? b.preferredUnit,
    );
  }

  static int _massRank(Unit? unit) {
    if (unit == Units.pound) return 4;
    if (unit == Units.ounce) return 3;
    if (unit == Units.kilogram) return 2;
    if (unit == Units.gram) return 1;
    return 0;
  }

  static Unit? _preferMassUnit(Unit? a, Unit? b) {
    if (_massRank(a) == 0 && _massRank(b) == 0) return a ?? b;
    return _massRank(a) >= _massRank(b) ? a : b;
  }

  /// What may be added to what.
  ///
  /// Volume and mass each pool into one running total, because everything
  /// inside a kind converts exactly. Counts do not: a clove and a head are
  /// both "1 item" canonically and adding them gives a number that describes
  /// neither, so each counted unit keeps its own bucket. [UnitConverter] has
  /// always refused to convert a count in either direction; this is the
  /// consolidator agreeing with it.
  static String _bucketFor(Quantity quantity) => quantity.kind == UnitKind.count
      ? 'count:${quantity.preferredUnit?.id ?? Units.item.id}'
      : quantity.kind.name;

  static const String _volume = 'volume';
  static const String _mass = 'mass';

  /// Reduces the buckets to one quantity where density allows, and leaves them
  /// side by side where it doesn't.
  static List<Quantity> _unify(
    Map<String, Quantity> byBucket,
    String displayName,
    DensityLookup densityLookup,
    UnitSystem system,
    MassDisplayMode massDisplayMode,
    Quantity? packSize,
    Unit? packageUnit,
  ) {
    if (byBucket.isEmpty) return const <Quantity>[];

    Quantity normalised(Quantity q) => UnitConverter.normalise(
      q,
      system: system,
      massDisplayMode: massDisplayMode,
      packSize: packSize,
      packageUnit: packageUnit,
    );

    if (byBucket.length == 1) {
      return <Quantity>[normalised(byBucket.values.first)];
    }

    final double? density = densityLookup(displayName);
    final bool hasVolume = byBucket.containsKey(_volume);
    final bool hasMass = byBucket.containsKey(_mass);

    if (density != null && hasVolume && hasMass) {
      // Weight is the more useful unit at the shop, so collapse into grams.
      final ConversionResult converted = UnitConverter.crossKind(
        byBucket[_volume]!,
        UnitKind.mass,
        gramsPerMillilitre: density,
      );
      if (converted.isExact) {
        final Quantity merged = _sum(byBucket[_mass]!, converted.quantity);
        final Map<String, Quantity> rest = <String, Quantity>{
          ...byBucket,
          _mass: merged,
        }..remove(_volume);
        return <Quantity>[for (final Quantity q in rest.values) normalised(q)];
      }
    }

    // Counts never convert, and without a density neither does volume<->mass.
    // List them together rather than inventing a total (spec §5.7).
    return <Quantity>[for (final Quantity q in byBucket.values) normalised(q)];
  }
}

@immutable
class _Entry {
  const _Entry({required this.ingredient, required this.recipeId});

  final RecipeIngredient ingredient;
  final String recipeId;
}
