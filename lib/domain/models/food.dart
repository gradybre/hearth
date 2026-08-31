import 'package:meta/meta.dart';

import '../units/quantity.dart';
import '../units/unit.dart';
import 'macros.dart';

/// Where a food's nutrition data came from (spec §5.5).
///
/// Shown as a source badge on the match review screen so the user can judge
/// how much to trust a number at a glance (spec §5.3).
enum FoodSource {
  /// Open Food Facts.
  openFoodFacts,

  /// USDA FoodData Central.
  usda,

  /// Entered by hand, usually after a barcode miss.
  manual,

  /// Produced by AI generation and not yet verified against a real source.
  /// Always labelled as an estimate (spec §5.4).
  aiEstimate,
}

/// One way a food can be portioned, with the macros for that portion.
///
/// A food carries several: "1 cup", "100 g", "1 slice" (spec §5.5).
@immutable
class ServingOption {
  const ServingOption({
    required this.id,
    required this.label,
    required this.amount,
    required this.macros,
  });

  final String id;

  /// How the portion reads in the UI: "1 slice", "100 g".
  final String label;

  /// The measured size of this portion. Its [Quantity.kind] decides whether an
  /// ingredient measured by volume, weight, or count can use it directly.
  final Quantity amount;

  /// Macros for exactly [amount] of this food.
  final Macros macros;

  @override
  bool operator ==(Object other) => other is ServingOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A food in the shared household library or the global catalogue (spec §4).
@immutable
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.servingOptions,
    required this.source,
    this.householdId,
    this.brand,
    this.storeTag,
    this.barcode,
    this.gramsPerMillilitre,
    this.macrosOverridden = false,
    this.isDeleted = false,
    this.updatedAt,
  });

  final String id;

  /// Null means a global food: world-readable, writes server-side only
  /// (spec §8.2).
  final String? householdId;

  final String name;
  final String? brand;

  /// Costco / Publix / Walmart, used to group the shopping list (spec §5.7).
  final String? storeTag;

  final String? barcode;

  final List<ServingOption> servingOptions;

  /// Density supplied by the data source, when it gives both a volume serving
  /// and its weight. Beats the generic density table every time, because it
  /// describes *this* food rather than a category average.
  final double? gramsPerMillilitre;

  final FoodSource source;

  /// True once the user has corrected the source's numbers. Their correction
  /// wins for all future use (spec §4, "User overrides win").
  final bool macrosOverridden;

  /// Foods are soft-deleted so historical logs keep resolving (spec §4).
  final bool isDeleted;

  /// When this food was last written, for sorting a library by recency.
  ///
  /// Null for a food that has not been through the household's own store — a
  /// lookup result, an unsaved draft. That is the honest answer rather than a
  /// stand-in date, and the sort puts them last rather than pretending they
  /// are new.
  final DateTime? updatedAt;

  bool get isGlobal => householdId == null;

  /// Whether this food cannot actually be logged as it stands.
  ///
  /// Either it carries no serving at all, or every serving it has is zero
  /// across the board — both of which make it look like a real entry in a
  /// list while contributing nothing to a day's numbers. Crowd-sourced
  /// imports land in this state often enough to be worth filtering for
  /// deliberately (spec §5.5), which is the whole point of surfacing it.
  bool get needsAttention =>
      servingOptions.isEmpty ||
      servingOptions.every((ServingOption o) => o.macros.isZero);

  /// The serving option to offer first — the first declared one.
  ServingOption? get defaultServing =>
      servingOptions.isEmpty ? null : servingOptions.first;

  /// The first serving measured in [kind], if any.
  ServingOption? servingForKind(UnitKind kind) {
    for (final ServingOption option in servingOptions) {
      if (option.amount.kind == kind) return option;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is Food && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Food($id, $name)';
}
