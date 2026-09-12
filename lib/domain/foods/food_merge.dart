import 'package:meta/meta.dart';

import '../models/food.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';

/// One planned meal's fate when the food under it is retired (review N05).
///
/// A planned entry stores `servings` as a count of its food's **default**
/// serving, so retiring a food whose default was 170 g in favour of one whose
/// default is 100 g silently turns "1 serving" into less food. The count has
/// to move with the size or the plan quietly means something else.
@immutable
class PlannedMealMove {
  const PlannedMealMove({
    required this.entryId,
    required this.was,
    required this.becomes,
    required this.fromServings,
    required this.toServings,
  });

  final String entryId;

  /// The portion one serving used to mean, and what it will mean.
  final Quantity was;
  final Quantity becomes;

  final double fromServings;

  /// The count that preserves the amount of food, or null when no conversion
  /// exists — a count against a weight, with no serving size to bridge them.
  final double? toServings;

  bool get canConvert => toServings != null;

  /// True when the count does not have to change at all.
  bool get isUnchanged => toServings == fromServings;
}

/// A recipe line that would stop counting after the merge.
@immutable
class StrandedLine {
  const StrandedLine({
    required this.recipeId,
    required this.recipeTitle,
    required this.ingredientName,
    required this.unitLabel,
  });

  final String recipeId;
  final String recipeTitle;
  final String ingredientName;

  /// The unit the line is written in, which the survivor cannot answer.
  final String unitLabel;
}

/// What merging two foods would do, worked out before anything is written.
///
/// Review before commit applies to a data operation as much as to an import
/// (CLAUDE.md rule 4): every figure here is counted first and shown, and the
/// merge is refused outright rather than half-done when a planned meal cannot
/// be converted.
///
/// **Logged meals are not in this list at all**, and that is the whole reason
/// a merge is safe. A logged entry freezes its macros *and* its name —
/// `MacroSnapshot.label` is "what the food or recipe was called at log time,
/// so a later rename doesn't make old history unreadable" — so a past day
/// needs no reference to follow and is never recalculated or renamed (rule 3).
@immutable
class MergePlan {
  const MergePlan({
    required this.survivor,
    required this.retiring,
    required this.mergedServings,
    required this.adoptedBarcode,
    required this.recipeLines,
    required this.stranded,
    required this.plannedMeals,
    required this.shoppingLines,
    required this.rememberedMatches,
    required this.loggedMeals,
  });

  final Food survivor;
  final Food retiring;

  /// Both foods' servings, the survivor's winning where they collide.
  ///
  /// A food that knew grams and a food that knew cups become one that knows
  /// both, which is strictly better for every reference either of them had —
  /// and is what keeps most recipe lines counting through the merge.
  final List<ServingOption> mergedServings;

  /// The retired food's barcode, when the survivor has none.
  ///
  /// A barcode is how a packet is found again; dropping one costs a future
  /// scan, and the survivor having none means there is nothing to overwrite.
  final String? adoptedBarcode;

  /// Recipe lines that move and keep counting.
  final int recipeLines;

  /// Recipe lines that move and stop counting, named.
  final List<StrandedLine> stranded;

  final List<PlannedMealMove> plannedMeals;
  final int shoppingLines;
  final int rememberedMatches;

  /// Logged meals pointing at the retired food. Reported, never touched.
  final int loggedMeals;

  /// Everything that would move.
  int get moves =>
      recipeLines +
      stranded.length +
      plannedMeals.length +
      shoppingLines +
      rememberedMatches;

  /// Planned meals whose serving cannot be converted.
  List<PlannedMealMove> get unconvertible => <PlannedMealMove>[
    for (final PlannedMealMove move in plannedMeals)
      if (!move.canConvert) move,
  ];

  /// Whether the merge may go ahead.
  ///
  /// Refused rather than half-done: a plan somebody made must not come out the
  /// other side meaning a different amount of food, and there is no honest
  /// default for "1 egg" against a food measured in grams.
  bool get canProceed => unconvertible.isEmpty;

  /// The survivor as it will be saved.
  ///
  /// Written out rather than copied: `Food` has no `copyWith`, and spelling
  /// every field means a field added later cannot be silently dropped here —
  /// the analyzer will not let this compile without it.
  Food get merged => Food(
    id: survivor.id,
    name: survivor.name,
    servingOptions: mergedServings,
    source: survivor.source,
    householdId: survivor.householdId,
    brand: survivor.brand,
    storeTag: survivor.storeTag,
    walmartItemId: survivor.walmartItemId,
    packSize: survivor.packSize,
    barcode: survivor.barcode ?? adoptedBarcode,
    menuGroup: survivor.menuGroup,
    menuOrder: survivor.menuOrder,
    // The retired food's density when the survivor has none, for the same
    // reason as the barcode: it is knowledge, and there is nothing to
    // overwrite.
    gramsPerMillilitre:
        survivor.gramsPerMillilitre ?? retiring.gramsPerMillilitre,
    macrosOverridden: survivor.macrosOverridden,
    isDefault: survivor.isDefault,
    isZeroCalorie: survivor.isZeroCalorie,
    isModifier: survivor.isModifier,
    updatedAt: survivor.updatedAt,
  );

  /// Works out what a merge would do, without doing any of it.
  ///
  /// [plannedEntries] is the unlogged plan entries pointing at [retiring],
  /// as `(id, servings)`; logged ones are deliberately not accepted, because
  /// nothing here may touch them.
  static MergePlan build({
    required Food survivor,
    required Food retiring,
    required int recipeLines,
    required List<StrandedLine> stranded,
    required List<({String id, double servings})> plannedEntries,
    required int shoppingLines,
    required int rememberedMatches,
    required int loggedMeals,
  }) {
    final List<ServingOption> servings = unionServings(survivor, retiring);

    final ServingOption? from = retiring.defaultServing;
    final ServingOption? to = servings.isEmpty ? null : servings.first;

    return MergePlan(
      survivor: survivor,
      retiring: retiring,
      mergedServings: servings,
      adoptedBarcode: survivor.barcode == null ? retiring.barcode : null,
      recipeLines: recipeLines,
      stranded: stranded,
      plannedMeals: <PlannedMealMove>[
        for (final ({String id, double servings}) entry in plannedEntries)
          _move(entry, from: from, to: to, retiring: retiring),
      ],
      shoppingLines: shoppingLines,
      rememberedMatches: rememberedMatches,
      loggedMeals: loggedMeals,
    );
  }

  static PlannedMealMove _move(
    ({String id, double servings}) entry, {
    required ServingOption? from,
    required ServingOption? to,
    required Food retiring,
  }) {
    final Quantity was = from?.amount ?? Quantity.of(1, Units.item);
    final Quantity becomes = to?.amount ?? Quantity.of(1, Units.item);

    return PlannedMealMove(
      entryId: entry.id,
      was: was,
      becomes: becomes,
      fromServings: entry.servings,
      toServings: _convertCount(
        entry.servings,
        was: was,
        becomes: becomes,
        gramsPerMillilitre: retiring.gramsPerMillilitre,
      ),
    );
  }

  /// The count that holds the amount of food still, or null.
  ///
  /// Same kind converts exactly. Volume against mass converts when the food
  /// carries its own density — a food that knows what a cup of it weighs can
  /// answer for both. A count against anything else cannot: nothing says what
  /// one of a thing weighs, which is the case the merge refuses on.
  static double? _convertCount(
    double servings, {
    required Quantity was,
    required Quantity becomes,
    double? gramsPerMillilitre,
  }) {
    // A serving of nothing cannot be divided by, and a food whose default
    // serving is zero is one the repair queue is already shouting about.
    if (becomes.isZero) return null;

    // Both are already in their kind's canonical unit — ml, g or items — so
    // same-kind conversion is a ratio and needs no unit arithmetic at all.
    if (was.kind == becomes.kind) {
      return servings * was.canonicalAmount / becomes.canonicalAmount;
    }

    final ConversionResult crossed = UnitConverter.crossKind(
      was,
      becomes.kind,
      gramsPerMillilitre: gramsPerMillilitre,
    );
    if (crossed.densityMissing) return null;
    return servings *
        crossed.quantity.canonicalAmount /
        becomes.canonicalAmount;
  }

  /// Both foods' servings, the survivor's first and winning a collision.
  ///
  /// Two servings collide when they measure the same portion — 100 g and
  /// 100 g — whatever they claim about its macros. The survivor is the one
  /// being kept, so its answer is the one kept.
  static List<ServingOption> unionServings(Food survivor, Food retiring) {
    String key(ServingOption o) =>
        '${o.amount.kind.name}:${o.amount.canonicalAmount}';

    final Set<String> seen = <String>{
      for (final ServingOption o in survivor.servingOptions) key(o),
    };

    return <ServingOption>[
      ...survivor.servingOptions,
      for (final ServingOption o in retiring.servingOptions)
        if (seen.add(key(o)))
          // A fresh id, because the old one still belongs to the retired
          // food's own row — servings are keyed by id across both foods, and
          // adopting one unchanged collides on insert. Derived rather than
          // random so the same merge planned twice proposes the same thing.
          ServingOption(
            id: '${survivor.id}:${o.id}',
            label: o.label,
            amount: o.amount,
            macros: o.macros,
            isReference: o.isReference,
          ),
    ];
  }
}

/// Foods in one library that look like the same thing (review N05).
///
/// Grouped on an identical barcode where there is one, and on an identical
/// normalised name otherwise.
///
/// Slightly stricter than the editor's duplicate warning, which matches on
/// barcode *or* name: two foods called the same thing with two different
/// barcodes are two different packets, and offering to merge them would be
/// offering to lose one of the codes. The warning is right to mention them
/// and this is right not to merge them.
///
/// Groups of one are not groups. Order within a group is the library's, so
/// the food somebody is most likely to think of as the real one leads.
List<List<Food>> duplicateGroups(
  Iterable<Food> foods, {
  required String Function(String) normalise,
}) {
  final Map<String, List<Food>> byKey = <String, List<Food>>{};
  for (final Food food in foods) {
    final String barcode = food.barcode ?? '';
    final String key = barcode.isNotEmpty
        ? 'barcode:$barcode'
        : 'name:${normalise(food.name)}';
    (byKey[key] ??= <Food>[]).add(food);
  }
  return <List<Food>>[
    for (final List<Food> group in byKey.values)
      if (group.length > 1) group,
  ];
}
