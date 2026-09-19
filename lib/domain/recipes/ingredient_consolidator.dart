import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/recipe.dart';
import '../parsing/ingredient_parser.dart';
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
  /// [foods] is the library the lines are matched against, read for one
  /// thing: a group's density comes from *its own* food rather than from a
  /// table entry that happens to share its name (spec R12).
  ///
  /// [preferPackKind] is the shopping question, and is off here: a recipe
  /// measured in cups reads in cups, whatever the shop sells it in (spec R5).
  static List<ConsolidatedIngredient> flatten(
    Recipe recipe, {
    bool includeOptional = false,
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
    Map<String, Food> foods = const <String, Food>{},
    bool preferPackKind = false,
    bool sourceMode = false,
  }) => _group(
    <_Entry>[
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        if (includeOptional || !ingredient.isOptional)
          _Entry(ingredient: ingredient, recipeId: recipe.id),
    ],
    densityLookup,
    system,
    foods,
    preferPackKind,
    sourceMode,
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
    Map<String, Food> foods = const <String, Food>{},
    bool preferPackKind = false,
    bool sourceMode = false,
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
    return _group(
      entries,
      densityLookup,
      system,
      foods,
      preferPackKind,
      sourceMode,
    );
  }

  static List<ConsolidatedIngredient> _group(
    List<_Entry> entries,
    DensityLookup densityLookup,
    UnitSystem system,
    Map<String, Food> foods,
    bool preferPackKind,
    bool sourceMode,
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
        _consolidate(
          group.key,
          group.value,
          densityLookup,
          system,
          foods,
          preferPackKind,
          sourceMode,
        ),
    ];
  }

  static ConsolidatedIngredient _consolidate(
    String key,
    List<_Entry> entries,
    DensityLookup densityLookup,
    UnitSystem system,
    Map<String, Food> foods,
    bool preferPackKind,
    bool sourceMode,
  ) {
    final String displayName = entries.first.ingredient.name;

    // What the lines themselves said they came in: the "28 oz" of
    // "2 (28 oz) cans" (spec R3.3). Display evidence only — it is applied as
    // a preferred-unit hint on the per-source copy of the quantity and never
    // touches a canonical amount, because a recipe's mentioned package is not
    // proof of the product the shopper buys. Carried on the ask rather than
    // computed at render time, so it survives being persisted, rebuilt and
    // having another source taken back off.
    final Unit? rawPackageUnit = _rawPackageUnit(entries);

    bool hasUnquantified = false;
    final List<Quantity> amounts = <Quantity>[];
    for (final _Entry entry in entries) {
      final Quantity? quantity = entry.ingredient.quantity;
      if (quantity == null) {
        hasUnquantified = true;
        continue;
      }
      amounts.add(
        rawPackageUnit != null && quantity.kind == UnitKind.mass
            ? quantity.withPreferredUnit(rawPackageUnit)
            : quantity,
      );
    }

    // The food this group is matched to, by id — never by name. Two products
    // that read alike are still two products, and borrowing one's density for
    // the other is how a jar of one thing gets measured as another (spec R12).
    final String? foodId = entries
        .map((_Entry e) => e.ingredient.foodId)
        .firstWhere((String? id) => id != null, orElse: () => null);
    final Food? food = foodId == null ? null : foods[foodId];

    final List<Quantity> quantities = combine(
      amounts,
      displayName: displayName,
      densityLookup: densityLookup,
      system: system,
      food: food,
      preferPackKind: preferPackKind,
      packageUnit: rawPackageUnit,
      crossKind: !sourceMode,
    );

    return ConsolidatedIngredient(
      key: key,
      displayName: displayName,
      foodId: foodId,
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
    Food? food,
    bool preferPackKind = false,
    bool crossKind = true,
  }) {
    // The matched food answers first, and about itself: its own stated or
    // implied density, then a reviewed package relationship, then — only
    // then — the generic table (spec R12).
    //
    // None of which applies in source mode ([crossKind] false), which is how
    // a contribution is summed. An ask is a record of what somebody asked
    // for, in the measure they asked for it, and a mutable food link may not
    // rewrite it: converting there would store a recipe written in cups as
    // ounces, and then changing the servings per package — or removing the
    // relationship altogether — could never recompute it (spec R5, R12).
    final Quantity? pack = crossKind ? (packSize ?? food?.packSize) : null;
    final MassDisplayMode mode = crossKind
        ? (food?.massDisplayMode ?? massDisplayMode)
        : massDisplayMode;
    final double? matched = crossKind
        ? food?.effectiveGramsPerMillilitre
        : null;
    double? densityFor(String name) =>
        crossKind ? (matched ?? densityLookup(name)) : null;

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
      densityFor,
      system,
      mode,
      pack,
      packageUnit,
      crossKind && preferPackKind,
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
    double? Function(String name) densityFor,
    UnitSystem system,
    MassDisplayMode massDisplayMode,
    Quantity? packSize,
    Unit? packageUnit,
    bool preferPackKind,
  ) {
    if (byBucket.isEmpty) return const <Quantity>[];

    Quantity normalised(Quantity q) {
      // A derived total carries the package's own unit as its display hint,
      // never its canonical value: 2 cups of a food sold in a 10 oz bag reads
      // in ounces, and the source quantities are left exactly as authored so
      // a later change recomputes rather than compounds (spec R2, R3).
      final Quantity hinted =
          q.kind == UnitKind.mass &&
              (packageUnit != null || q.preferredUnit == null)
          ? _massHinted(q, packSize, packageUnit)
          : q;
      return UnitConverter.normalise(
        hinted,
        system: system,
        massDisplayMode: massDisplayMode,
        packSize: packSize,
        packageUnit: packageUnit,
      );
    }

    final bool hasVolume = byBucket.containsKey(_volume);
    final bool hasMass = byBucket.containsKey(_mass);
    final bool packIsMass =
        packSize != null &&
        packSize.kind == UnitKind.mass &&
        packSize.canonicalAmount.isFinite &&
        packSize.canonicalAmount > 0;

    // Weight is the more useful unit at the shop, so collapse into grams —
    // both when the two kinds are already side by side, and when a shopping
    // total has to be counted against a mass pack that nothing else in the
    // group is measured in (spec R7, R12).
    if (hasVolume && (hasMass || (preferPackKind && packIsMass))) {
      final double? density = densityFor(displayName);
      if (density != null) {
        final ConversionResult converted = UnitConverter.crossKind(
          byBucket[_volume]!,
          UnitKind.mass,
          gramsPerMillilitre: density,
        );
        if (converted.isExact) {
          final Quantity merged = hasMass
              ? _sum(byBucket[_mass]!, converted.quantity)
              : converted.quantity;
          final Map<String, Quantity> rest = <String, Quantity>{
            ...byBucket,
            _mass: merged,
          }..remove(_volume);
          return <Quantity>[
            for (final Quantity q in rest.values) normalised(q),
          ];
        }
      }
    }

    if (byBucket.length == 1) {
      return <Quantity>[normalised(byBucket.values.first)];
    }

    // Counts never convert, and without a density neither does volume<->mass.
    // List them together rather than inventing a total (spec §5.7).
    return <Quantity>[for (final Quantity q in byBucket.values) normalised(q)];
  }

  /// [q] wearing the package's unit as a display hint, where there is one.
  static Quantity _massHinted(
    Quantity q,
    Quantity? packSize,
    Unit? packageUnit,
  ) {
    final Unit? hint =
        _massUnit(packageUnit) ?? _massUnit(packSize?.preferredUnit);
    return hint == null ? q : q.withPreferredUnit(hint);
  }

  static Unit? _massUnit(Unit? unit) =>
      unit != null && unit.kind == UnitKind.mass ? unit : null;

  /// The mass unit named by explicit pack-size syntax on any of this group's
  /// raw lines (spec R3.3).
  ///
  /// Ranked the same way a mass sum's display hint is ranked, so the two
  /// cannot disagree about which unit a mixed group reads in. Applied to
  /// every mass quantity in the group, which is what keeps a group carrying
  /// ounce-package evidence in ounces even when another line was written in
  /// pounds.
  static Unit? _rawPackageUnit(List<_Entry> entries) {
    Unit? best;
    for (final _Entry entry in entries) {
      final String raw = _rawOf(entry.ingredient);
      if (raw.isEmpty) continue;
      final Unit? found = IngredientParser.packageUnitFor(raw);
      if (found == null || found.kind != UnitKind.mass) continue;
      if (best == null || _massRank(found) > _massRank(best)) best = found;
    }
    return best;
  }

  /// The line as it was typed or imported, or nothing at all.
  static String _rawOf(RecipeIngredient ingredient) {
    final Object? raw = ingredient.rawText;
    return raw is String ? raw : '';
  }
}

@immutable
class _Entry {
  const _Entry({required this.ingredient, required this.recipeId});

  final RecipeIngredient ingredient;
  final String recipeId;
}
