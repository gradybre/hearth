import 'package:meta/meta.dart';

import '../units/mass_display_mode.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'macros.dart';
import 'package_nutrition.dart';

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

  /// Read off a restaurant's own published nutrition sheet (spec §5.2).
  ///
  /// Load-bearing, not decorative. A restaurant food is **never offered as an
  /// automatic match for a cooking recipe's ingredient** — see
  /// [IngredientMatcher]. Chipotle's menu contributes a Chicken, a Cheese, a
  /// Sour Cream and a Romaine Lettuce to the library, and without this they
  /// would join the pool every ingredient line is matched against. That is
  /// worse than a wrong suggestion: the matcher only answers a line when the
  /// answer is unambiguous, so a second Chicken makes lines that used to
  /// resolve cleanly stop resolving at all.
  ///
  /// A food that only exists inside somebody else's kitchen can never be an
  /// ingredient in yours. The rule is right regardless of Chipotle.
  restaurant,
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
    this.isReference = false,
  });

  final String id;

  /// How the portion reads in the UI: "1 slice", "100 g".
  final String label;

  /// Whether this is a source's per-100 reference rather than a portion.
  ///
  /// Open Food Facts and USDA both quote nutrition per 100 g and often know
  /// nothing else, so every food carries a 100 g option whether or not anybody
  /// eats 100 g of it. Saying which one that is stops a screen dressing it up
  /// as a serving — a search list that rendered it in ounces read as though
  /// every yogurt on the shelf came in identical 3.5 oz pots.
  ///
  /// Deliberately not persisted: once a human has reviewed a food and saved
  /// it, every serving on it is one they chose.
  final bool isReference;

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
    this.walmartItemId,
    this.packSize,
    this.barcode,
    this.menuGroup,
    this.menuOrder,
    this.gramsPerMillilitre,
    this.macrosOverridden = false,
    this.isDefault = false,
    this.isZeroCalorie = false,
    this.isModifier = false,
    this.isDeleted = false,
    this.updatedAt,
    this.massDisplayMode = MassDisplayMode.automatic,
    this.packageNutrition,
  });

  final String id;

  /// Null means a global food: world-readable, writes server-side only
  /// (spec §8.2).
  final String? householdId;

  final String name;
  final String? brand;

  /// Costco / Publix / Walmart, used to group the shopping list (spec §5.7).
  final String? storeTag;

  /// The Walmart item id for the product actually bought, so the shopping
  /// export can fill a basket rather than open a search (spec §5.7).
  ///
  /// Typed once per food you buy regularly. Null for most foods, and for
  /// everything Hearth has not been told about.
  final String? walmartItemId;

  /// How much comes in one of those, when it is known.
  ///
  /// What turns "2 lb of beef" into a number of packets. Optional, because a
  /// wrong pack size does not fail — it silently orders the wrong amount —
  /// so it is better absent than guessed.
  final Quantity? packSize;

  final String? barcode;

  /// The section of a restaurant's menu this sits in — "Proteins", "Salsas"
  /// (spec §5.2). Null for anything that is not off a menu.
  final String? menuGroup;

  /// Its position on the sheet. Orders items inside a section, and the
  /// sections against each other by where each one first appears — which is
  /// the only way to lay a menu out the way the restaurant does rather than
  /// alphabetically.
  final int? menuOrder;

  final List<ServingOption> servingOptions;

  /// Density supplied by the data source, when it gives both a volume serving
  /// and its weight. Beats the generic density table every time, because it
  /// describes *this* food rather than a category average.
  final double? gramsPerMillilitre;

  final FoodSource source;

  /// True once the user has corrected the source's numbers. Their correction
  /// wins for all future use (spec §4, "User overrides win").
  final bool macrosOverridden;

  /// One of the household's standing choices, matched to recipe lines that
  /// name the same thing (spec §5.3).
  ///
  /// Not one per food concept: whole, 2% and non-fat milk can all be defaults
  /// at once. What tells them apart is the variant in the name, and a recipe
  /// line that names no variant is answered by a short menu rather than a
  /// guess — see [FoodConcept].
  final bool isDefault;

  /// Confirmed to carry no macros at all — black coffee, sparkling water, a
  /// zero-calorie sweetener (spec §5.5).
  ///
  /// The distinction this exists to draw: a food whose macros are all zero is
  /// *usually* a half-filled import, and [needsAttention] is right to say so.
  /// But some foods really are zero, and without a way to say which, the
  /// warning could never be cleared — it would sit on the black coffee for
  /// ever, and a warning that cannot be cleared is one that stops being read.
  ///
  /// Only ever set deliberately. Inferring it from "the user saved this" would
  /// give the same answer for a food somebody saved without noticing the
  /// numbers were missing, which is the exact case the warning is for.
  final bool isZeroCalorie;

  /// A menu row a restaurant publishes as a **deduction** rather than as
  /// something you order (spec §5.2).
  ///
  /// Freddy's prints "Make any Sandwich a Lettuce Wrap" as −180 kcal, −25 g
  /// carbohydrate — and **+1 g of fibre**, because the bun is what was
  /// carrying the deficit. The mixed signs are why this is a flag on a food
  /// with genuinely signed macros rather than a positive amount that gets
  /// negated somewhere: negating everything would state that a lettuce wrap
  /// costs you a gram of fibre, which is the opposite of true.
  ///
  /// A modifier is what you log *against*, never what you log. It is kept out
  /// of ingredient matching, out of the food picker and out of the log sheet;
  /// the only place it can be chosen is the eat-out builder, once something
  /// real has been chosen for it to apply to.
  final bool isModifier;

  /// Foods are soft-deleted so historical logs keep resolving (spec §4).
  final bool isDeleted;

  /// When this food was last written, for sorting a library by recency.
  ///
  /// Null for a food that has not been through the household's own store — a
  /// lookup result, an unsaved draft. That is the honest answer rather than a
  /// stand-in date, and the sort puts them last rather than pretending they
  /// are new.
  final DateTime? updatedAt;

  /// How an imperial mass quantity for this food should be displayed —
  /// pinned to ounces, run through the ordinary oz/lb ladder, or decided
  /// automatically from pack size and source hints (spec R3–R4).
  ///
  /// A display preference only. Never changes what is stored, summed, or
  /// computed — only which unit a total is finally shown in.
  final MassDisplayMode massDisplayMode;

  /// A reviewed package amount, nutrition serving, and servings-per-package
  /// relationship (spec R9–R13), when the household has set one.
  ///
  /// Bridges mass and volume for a food that would otherwise have no way to
  /// answer a recipe measured in the other kind of unit — a jar of shredded
  /// cheddar whose label states 10 oz and "about 2 servings" of 1/4 cup,
  /// asked for by weight in a recipe. Only ever a *fallback*: this food's own
  /// stated or inferred density always answers first (spec R12), and this
  /// relationship is used only through [activePackageServing], which returns
  /// null the moment it no longer matches the food's current pack size or
  /// serving list.
  final PackageNutrition? packageNutrition;

  bool get isGlobal => householdId == null;

  /// Density stated explicitly by the source, or implied by this food's own
  /// serving sizes when it states more than one kind of measurement.
  ///
  /// Split out from [effectiveGramsPerMillilitre] so a package relationship
  /// (spec R9–R13) is only tried once this comes back empty, and so a caller
  /// wanting to flag a conflict (spec R12) can compare the two directly
  /// rather than one silently winning inside a single number.
  double? get ownGramsPerMillilitre =>
      _usableDensity(gramsPerMillilitre) ?? _densityFromServings();

  /// [value] when it is a figure something can actually be divided by, and
  /// null otherwise (review B1).
  ///
  /// A stored density arrives from sync as whatever the payload said, and
  /// `double.tryParse` accepts NaN and Infinity as readily as 1.03. A zero, a
  /// negative or a NaN is not a density: multiplying by it poisons every
  /// macro downstream, and -- worse -- its mere presence used to count as
  /// this food having answered, so a reviewed package relationship that could
  /// have answered properly was skipped in favour of it. One accessor, so
  /// there is a single meaning of usable rather than one per caller.
  static double? _usableDensity(double? value) =>
      value != null && value.isFinite && value > 0 ? value : null;

  /// The serving option a reviewed package/nutrition relationship (spec
  /// R9–R13) is anchored to, when that relationship exists, is well-formed,
  /// and still describes this food's *current* package size and serving.
  ///
  /// Null the instant any of those three drift apart — a changed pack size,
  /// a changed serving amount, or a deleted serving — because at that point
  /// the saved count no longer describes anything real (spec R10, R13).
  /// Looked up by id rather than list position, so reordering the serving
  /// list is harmless.
  ServingOption? get activePackageServing {
    final PackageNutrition? relation = packageNutrition;
    if (relation == null || !relation.isValid) return null;
    final ServingOption? serving = _servingById(relation.servingOptionId!);
    if (serving == null) return null;
    final bool stillMatches = relation.matches(
      pack: packSize,
      servingId: serving.id,
      servingAmount: serving.amount,
    );
    return stillMatches ? serving : null;
  }

  /// True when a package/nutrition relationship is saved but no longer
  /// matches this food's current package size or its selected serving.
  ///
  /// The editor's cue to show "Check package servings" (spec R10) rather than
  /// silently keep computing from stale facts, or silently drop them with no
  /// explanation.
  bool get hasStalePackageNutrition =>
      packageNutrition != null &&
      packageNutrition!.isValid &&
      activePackageServing == null;

  ServingOption? _servingById(String id) {
    for (final ServingOption option in servingOptions) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// Grams per millilitre implied by the active package relationship — null
  /// when there is none, it is invalid, or it has gone stale.
  double? get packageGramsPerMillilitre => activePackageServing == null
      ? null
      : packageNutrition?.gramsPerMillilitre;

  /// Whether the package relationship's implied density disagrees with this
  /// food's own by more than 5% (spec R12).
  ///
  /// A signal for a review screen to surface, never a reason to prefer one
  /// figure over the other — [effectiveGramsPerMillilitre] keeps its own
  /// precedence order regardless of this.
  bool get packageDensityConflictsWithOwn {
    final double? own = ownGramsPerMillilitre;
    final double? fromPackage = packageGramsPerMillilitre;
    if (own == null || fromPackage == null || own == 0) return false;
    return (fromPackage - own).abs() / own.abs() > 0.05;
  }

  /// This food's density: its own stated or inferred figure first, falling
  /// back to a reviewed package relationship only when the food has no
  /// density of its own to give (spec R12).
  ///
  /// A food that states both a volume serving and a weight serving has
  /// already told us how much a millilitre of it weighs, even when nobody
  /// filled in [gramsPerMillilitre] — the macros are the bridge. If 2 cups
  /// carries 200 kcal and 100 g carries 400 kcal, then 2 cups *is* 50 g, and
  /// that is arithmetic on what this food asserts rather than a guess from a
  /// table of category averages.
  ///
  /// This is what lets a recipe measured in cups use a food recorded in
  /// grams. Without it a perfectly well-described food still could not
  /// answer "how much is 2.5 cups of it", and the ingredient came back
  /// flagged with nothing obviously wrong.
  ///
  /// The package fallback never overrides a direct answer the food's own
  /// data already gives, and is never cached back into [gramsPerMillilitre]:
  /// a cached number would outlive the package review it came from and lose
  /// the provenance that makes it correctable (spec R12).
  double? get effectiveGramsPerMillilitre =>
      ownGramsPerMillilitre ?? packageGramsPerMillilitre;

  double? _densityFromServings() {
    final ({double amount, double scale})? volume = _bridge(UnitKind.volume);
    final ({double amount, double scale})? mass = _bridge(UnitKind.mass);
    if (volume == null || mass == null) return null;

    // How many of the mass serving one volume serving is worth.
    final double massServings = volume.scale / mass.scale;
    final double grams = mass.amount * massServings;
    final double density = grams / volume.amount;
    return density.isFinite && density > 0 ? density : null;
  }

  /// One serving of [kind] with something to scale by, in canonical units.
  ///
  /// The scale is whichever macro is non-zero on both sides of the
  /// comparison — energy usually, but a zero-calorie food still has a weight,
  /// so the others stand in rather than giving up.
  ({double amount, double scale})? _bridge(UnitKind kind) {
    for (final ServingOption option in servingOptions) {
      if (option.amount.kind != kind) continue;
      final double amount = option.amount.canonicalAmount;
      if (amount <= 0) continue;

      final Macros m = option.macros;
      final double scale = m.kcal != 0 ? m.kcal : m.proteinG + m.carbG + m.fatG;
      if (scale <= 0) continue;
      return (amount: amount, scale: scale);
    }
    return null;
  }

  /// Whether this food cannot actually be logged as it stands.
  ///
  /// Either it carries no serving at all, or every serving it has is zero
  /// across the board — both of which make it look like a real entry in a
  /// list while contributing nothing to a day's numbers. Crowd-sourced
  /// imports land in this state often enough to be worth filtering for
  /// deliberately (spec §5.5), which is the whole point of surfacing it.
  ///
  /// Unless [isZeroCalorie] says the zeros are the answer. A food with no
  /// serving at all is still flagged either way: there is nothing to log,
  /// whatever its macros would have been.
  bool get needsAttention =>
      servingOptions.isEmpty ||
      (!isZeroCalorie &&
          servingOptions.every((ServingOption o) => o.macros.isZero));

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
