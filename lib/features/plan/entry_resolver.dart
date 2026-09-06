import 'package:meta/meta.dart';

import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/recipes/macro_calculator.dart';

/// A plan entry with everything needed to draw and total it.
@immutable
class ResolvedEntry {
  const ResolvedEntry({
    required this.entry,
    required this.label,
    required this.perServing,
    this.liveCoverage = const NutrientCoverage.notRecorded(),
    required this.isResolvable,
    this.servingLabel,
  });

  final MealPlanEntry entry;

  /// What to show. For a logged entry this comes from the snapshot, so a
  /// renamed or deleted recipe cannot make history unreadable (spec §4).
  final String label;

  /// Live macros for one serving. Zero when the reference is gone.
  final Macros perServing;

  /// How much of [perServing]'s minor nutrients the numbers speak for, live.
  ///
  /// A logged entry answers from its frozen coverage instead; this is what a
  /// *planned* one is costed with, and what gets frozen when it is eaten.
  final NutrientCoverage liveCoverage;

  /// False when the recipe or food behind this entry no longer resolves.
  ///
  /// A logged entry stays perfectly readable in that state — its snapshot is
  /// the source of truth — but a *planned* one cannot be costed.
  final bool isResolvable;

  /// "per 100 g" and the like, for foods.
  final String? servingLabel;

  /// What this entry contributes to the day.
  ///
  /// Logged entries answer from their snapshot; planned ones are costed live.
  Macros get contribution => entry.contribution(plannedMacros: perServing);

  /// How much of [contribution]'s minor nutrients it speaks for.
  ///
  /// Frozen for a logged entry and live for a planned one, matching where the
  /// numbers themselves come from. Editing a recipe changes what tonight's
  /// plan is expected to cover; it cannot change what last night's dinner did
  /// (spec §4).
  NutrientCoverage get contributionCoverage =>
      entry.isLogged && entry.macroSnapshot != null
      ? entry.macroSnapshot!.coverage
      : liveCoverage;

  /// True when this is on the plan but not yet eaten.
  bool get isPending => !entry.isLogged;

  /// A planned entry that cannot be costed — worth flagging rather than
  /// silently contributing zero to a projection.
  bool get isUncostable => isPending && !isResolvable;
}

/// Turns plan entries into something displayable and totalable.
abstract final class EntryResolver {
  /// Resolves one entry against the current library.
  static ResolvedEntry resolve(
    MealPlanEntry entry, {
    required Map<String, Recipe> recipes,
    required Map<String, Food> foods,
  }) {
    final MacroSnapshot? snapshot = entry.macroSnapshot;

    switch (entry.refType) {
      case PlanRefType.recipe:
        final Recipe? recipe = recipes[entry.refId];
        if (recipe == null) {
          return ResolvedEntry(
            entry: entry,
            // The snapshot's label is what keeps a deleted recipe's log
            // readable; falling back to "Removed recipe" only matters for a
            // planned entry, which has no snapshot to speak from.
            label: snapshot?.label.isNotEmpty ?? false
                ? snapshot!.label
                : 'Removed recipe',
            perServing: Macros.zero,
            liveCoverage: const NutrientCoverage.notRecorded(),
            isResolvable: false,
          );
        }
        // The whole `RecipeMacros`, not just its per-serving total: the
        // coverage lives in the ingredients, and taking `.perServing` alone is
        // where the qualification used to be dropped (R06).
        final RecipeMacros macros = MacroCalculator.forRecipe(
          recipe,
          foods: foods,
        );
        return ResolvedEntry(
          entry: entry,
          label: recipe.title,
          perServing: macros.perServing,
          liveCoverage: macros.coverage,
          isResolvable: true,
        );

      case PlanRefType.food:
        final Food? food = foods[entry.refId];
        final ServingOption? serving = food?.defaultServing;
        if (food == null || serving == null) {
          return ResolvedEntry(
            entry: entry,
            label: snapshot?.label.isNotEmpty ?? false
                ? snapshot!.label
                : 'Removed food',
            perServing: Macros.zero,
            liveCoverage: const NutrientCoverage.notRecorded(),
            isResolvable: false,
          );
        }
        return ResolvedEntry(
          entry: entry,
          liveCoverage: NutrientCoverage.ofOne(serving.macros),
          label: food.name,
          // A food entry is counted in multiples of its first serving option.
          // The plan row stores only a food id and a count (spec §4), so the
          // default serving is what "one serving" has to mean.
          perServing: serving.macros,
          isResolvable: true,
          servingLabel: serving.label,
        );
    }
  }

  static List<ResolvedEntry> resolveAll(
    Iterable<MealPlanEntry> entries, {
    required Map<String, Recipe> recipes,
    required Map<String, Food> foods,
  }) => <ResolvedEntry>[
    for (final MealPlanEntry entry in entries)
      resolve(entry, recipes: recipes, foods: foods),
  ];

  /// What has actually been eaten — the basis for remaining-for-the-day.
  ///
  /// Planned-but-unconfirmed entries deliberately do not count: the number
  /// that matters is what you ate, not what you intended to (spec §5.6).
  static Macros eaten(Iterable<ResolvedEntry> entries) =>
      Macros.sum(eatenParts(entries));

  /// The same contributions, unsummed.
  ///
  /// A total says nothing about its own coverage: "12 g of fibre" looks
  /// identical whether it came from everything eaten or from one food out of
  /// six, and only one of those is worth reading (spec §5.6).
  static List<Macros> eatenParts(Iterable<ResolvedEntry> entries) => <Macros>[
    for (final ResolvedEntry entry in entries)
      if (entry.entry.isLogged) entry.contribution,
  ];

  /// What each logged contribution actually speaks for, in the same order.
  ///
  /// Counting entries told you how many meals said nothing at all. It could
  /// not see inside one: a recipe whose second ingredient never stated its
  /// fibre summed to a non-null number, so the entry read as knowing, and the
  /// day showed a partial total as though it were whole (R06).
  static List<NutrientCoverage> eatenCoverage(
    Iterable<ResolvedEntry> entries,
  ) => <NutrientCoverage>[
    for (final ResolvedEntry entry in entries)
      if (entry.entry.isLogged) entry.contributionCoverage,
  ];

  /// What the rest of the plan would add if every planned entry were eaten.
  static Macros stillPlanned(Iterable<ResolvedEntry> entries) => Macros.sum(
    entries
        .where((ResolvedEntry e) => e.isPending)
        .map((ResolvedEntry e) => e.contribution),
  );

  /// Entries in a slot, in the order they were added.
  static List<ResolvedEntry> inSlot(
    Iterable<ResolvedEntry> entries,
    MealSlot slot,
  ) => entries
      .where((ResolvedEntry e) => e.entry.slot == slot)
      .toList(growable: false);
}
