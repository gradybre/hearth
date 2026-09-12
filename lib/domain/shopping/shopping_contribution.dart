import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../recipes/ingredient_consolidator.dart';
import '../units/density.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'shopping_line.dart';

/// Who asked for how much of a line (spec §5.7).
///
/// A shopping list used to be one thing the plan owned: a rebuild recomputed
/// every [ShoppingLine.planned] from the week's recipes, and anything else on
/// the list was a manual item the plan had no vote on. That worked while the
/// plan was the only way to fill a list.
///
/// It stops working the moment a recipe can be added to the list directly. Two
/// pounds of beef on a line is then the sum of several separate asks — the
/// plan's Tuesday chilli, and the bolognese somebody added on Saturday — and a
/// total cannot be taken apart again. The next rebuild would either wipe the
/// hand-added half or silently double it, and removing one recipe from the
/// list would be impossible in either case.
///
/// So the line keeps the asks and adds them up, rather than keeping the sum.
enum ShoppingSourceKind {
  /// The meal plan, over the range the list was last built for.
  ///
  /// At most one per line, and replaced wholesale by a rebuild — the plan is
  /// recomputed as a unit, so its contribution is too.
  plan,

  /// A recipe somebody added to the list themselves.
  recipe,

  /// A food added on its own, without a recipe around it.
  food,

  /// Typed in by hand — coffee, paper towels. No recipe asked for it and no
  /// rebuild can take it away.
  manual,
}

/// One ask: what a single source wants of one line.
@immutable
class ShoppingContribution {
  const ShoppingContribution({
    required this.kind,
    required this.quantities,
    this.refId,
    this.label,
    this.servings,
    this.hasUnquantified = false,
  });

  final ShoppingSourceKind kind;

  /// What this source alone calls for. More than one entry where the amounts
  /// could not be reconciled, exactly as on the line itself.
  final List<Quantity> quantities;

  /// The recipe or food this came from. Null for [ShoppingSourceKind.plan] and
  /// [ShoppingSourceKind.manual], neither of which points at one thing.
  final String? refId;

  /// What to call the source on screen — "Weeknight chilli". Stored rather
  /// than looked up, so a line can still say where its amounts came from
  /// after the recipe behind it is renamed or deleted.
  final String? label;

  /// How many servings were asked for, where that is a meaningful question.
  final double? servings;

  final bool hasUnquantified;

  /// What makes two contributions the same ask.
  ///
  /// The plan is one ask however many recipes are behind it. A recipe added
  /// twice is one ask for the total, not two asks to disentangle later —
  /// which is what makes "take this recipe back off the list" a single,
  /// unambiguous act.
  String get sourceKey => switch (kind) {
    ShoppingSourceKind.plan => 'plan',
    ShoppingSourceKind.manual => 'manual',
    ShoppingSourceKind.recipe => 'recipe:$refId',
    ShoppingSourceKind.food => 'food:$refId',
  };

  ShoppingContribution copyWith({
    List<Quantity>? quantities,
    double? servings,
    String? label,
    bool? hasUnquantified,
  }) => ShoppingContribution(
    kind: kind,
    quantities: quantities ?? this.quantities,
    refId: refId,
    label: label ?? this.label,
    servings: servings ?? this.servings,
    hasUnquantified: hasUnquantified ?? this.hasUnquantified,
  );

  @override
  bool operator ==(Object other) =>
      other is ShoppingContribution &&
      other.kind == kind &&
      other.refId == refId &&
      other.label == label &&
      other.servings == servings &&
      other.hasUnquantified == hasUnquantified &&
      const ListEquality<Quantity>().equals(other.quantities, quantities);

  @override
  int get hashCode => Object.hash(
    kind,
    refId,
    label,
    servings,
    hasUnquantified,
    const ListEquality<Quantity>().hash(quantities),
  );

  @override
  String toString() => 'ShoppingContribution($sourceKey, $quantities)';
}

/// Keeping a line's total and its asks in step.
///
/// The invariant every one of these preserves: [ShoppingLine.planned] is
/// exactly the sum of [ShoppingLine.contributions], and nothing else may set
/// it. A line assembled any other way can disagree with its own arithmetic,
/// which is the bug this whole type exists to make impossible.
abstract final class ShoppingContributions {
  /// A line whose total is recomputed from [contributions].
  ///
  /// The summing is [IngredientConsolidator.combine] — the same arithmetic
  /// that adds an ingredient across a week of recipes, rather than a second
  /// implementation free to drift from it.
  static ShoppingLine settle(
    ShoppingLine line, {
    required List<ShoppingContribution> contributions,
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
  }) {
    final List<ShoppingContribution> kept = <ShoppingContribution>[
      for (final ShoppingContribution c in contributions)
        if (c.quantities.isNotEmpty || c.hasUnquantified || c.servings != null)
          c,
    ];

    return line.copyWith(
      contributions: kept,
      planned: IngredientConsolidator.combine(
        <Quantity>[for (final ShoppingContribution c in kept) ...c.quantities],
        displayName: line.name,
        densityLookup: densityLookup,
        system: system,
      ),
      hasUnquantified: kept.any((ShoppingContribution c) => c.hasUnquantified),
    );
  }

  /// [incoming] folded into [existing], one ask per source.
  ///
  /// Adding the same recipe twice sums the servings and the amounts rather
  /// than listing it twice — see [ShoppingContribution.sourceKey]. Order is
  /// preserved so a line's provenance reads in the order it accumulated.
  static List<ShoppingContribution> merge(
    List<ShoppingContribution> existing,
    List<ShoppingContribution> incoming, {
    DensityLookup densityLookup = DensityTable.lookup,
    UnitSystem system = UnitSystem.imperial,
    String displayName = '',
  }) {
    final List<ShoppingContribution> out = <ShoppingContribution>[...existing];
    for (final ShoppingContribution add in incoming) {
      final int at = out.indexWhere(
        (ShoppingContribution c) => c.sourceKey == add.sourceKey,
      );
      if (at < 0) {
        out.add(add);
        continue;
      }
      final ShoppingContribution was = out[at];
      out[at] = was.copyWith(
        quantities: IngredientConsolidator.combine(
          <Quantity>[...was.quantities, ...add.quantities],
          displayName: displayName,
          densityLookup: densityLookup,
          system: system,
        ),
        servings: was.servings == null && add.servings == null
            ? null
            : (was.servings ?? 0) + (add.servings ?? 0),
        label: add.label ?? was.label,
        hasUnquantified: was.hasUnquantified || add.hasUnquantified,
      );
    }
    return out;
  }

  /// [existing] with the plan's ask replaced by [planContribution].
  ///
  /// The whole point of the split: a rebuild is authoritative about the plan
  /// and about nothing else. Recipes and foods somebody added by hand, and
  /// anything typed in, come through untouched — which is what stops a
  /// rebuild quietly undoing them.
  ///
  /// A null [planContribution] means the plan no longer asks for this line at
  /// all, which is how a line drops off a rebuild without taking a
  /// hand-added ask with it.
  static List<ShoppingContribution> replacePlan(
    List<ShoppingContribution> existing,
    ShoppingContribution? planContribution,
  ) => <ShoppingContribution>[
    ?planContribution,
    for (final ShoppingContribution c in existing)
      if (c.kind != ShoppingSourceKind.plan) c,
  ];

  /// [existing] without one source's ask.
  static List<ShoppingContribution> without(
    List<ShoppingContribution> existing,
    String sourceKey,
  ) => <ShoppingContribution>[
    for (final ShoppingContribution c in existing)
      if (c.sourceKey != sourceKey) c,
  ];

  /// What a line reads as older data.
  ///
  /// Every row written before this existed has a total and no asks. Read as
  /// one plan contribution carrying that total, which is what it was: the
  /// plan owned every number on the list. Manual lines become a manual ask
  /// for the same reason — otherwise the first rebuild after an update would
  /// treat a typed-in line as the plan's and take it away.
  static List<ShoppingContribution> legacy(ShoppingLine line) {
    if (line.planned.isEmpty && !line.hasUnquantified) {
      return const <ShoppingContribution>[];
    }
    return <ShoppingContribution>[
      ShoppingContribution(
        kind: line.isManual
            ? ShoppingSourceKind.manual
            : ShoppingSourceKind.plan,
        quantities: line.planned,
        hasUnquantified: line.hasUnquantified,
      ),
    ];
  }
}
