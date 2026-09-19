import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../parsing/amount_parser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'nutrient_coverage.dart';

/// One way a portion can be *typed* when logging (spec §5.6).
///
/// Either one of the food's own servings — "170 g pot", "100 g" — or a raw
/// unit of the same kind. A food served in 170 g pots could only ever be
/// counted in pots, so 125 g of it meant dividing by 170 in a kitchen and
/// typing 0.735 into a stepper that moves in quarters.
///
/// **This is only ever how the number is entered.** What is stored is a count
/// of the food's default serving, whichever unit typed it — that is what
/// `servings` has always meant, and what everything downstream rebuilds a
/// meal from. [toDefaultServings] is the one direction that reaches storage.
@immutable
class PortionUnit {
  /// One of the food's own servings, counted the way it always was.
  const PortionUnit.serving(ServingOption serving)
    : _serving = serving,
      _unit = null;

  /// A raw unit — grams, ounces — typed as an amount rather than a count.
  const PortionUnit.raw(Unit unit) : _unit = unit, _serving = null;

  final ServingOption? _serving;
  final Unit? _unit;

  /// The stored serving this counts. Null for a raw unit.
  ServingOption? get serving => _serving;

  /// True when the field holds an amount rather than a count of servings.
  bool get isRaw => _unit != null;

  /// Stable identity. Persisted as the remembered choice, so never localise
  /// it and never derive it from the label — a food's serving can be renamed.
  String get id {
    final Unit? unit = _unit;
    return unit == null ? 'serving:${_serving!.id}' : 'unit:${unit.id}';
  }

  /// How the chip reads: the food's own words, or the unit's.
  String get label => _unit?.label ?? _serving!.label;

  /// How much one of these is.
  Quantity get size {
    final Unit? unit = _unit;
    return unit == null ? _serving!.amount : Quantity.of(1, unit);
  }

  /// What the plus and minus buttons move by.
  ///
  /// Quarters of a serving, because half and quarter servings are what come
  /// up — but stepping a gram field by a quarter of a gram is forty taps to
  /// cross a portion, so a raw unit steps by something you would actually
  /// weigh.
  double get step => switch (_unit?.id) {
    'g' => 5,
    'oz' => 0.25,
    'ml' => 10,
    'fl_oz' => 0.5,
    _ => 0.25,
  };

  /// How many decimals the field shows in this unit, or null to show the
  /// value as it is.
  ///
  /// A serving count keeps every digit it has: `writeAmount` writes a third
  /// of a batch as "1/3", and rounding it first would take that away. An
  /// amount converted into a raw unit has no such luck — one pot in ounces is
  /// 5.996473604060913, and a field showing that is a field nobody can read.
  int? get _decimals => switch (_unit?.id) {
    'g' || 'ml' => 1,
    'oz' || 'fl_oz' => 2,
    _ => null,
  };

  /// [count], as this unit's field writes it.
  ///
  /// `writeAmount` spells halves and quarters as fractions, which is exactly
  /// what a count of servings wants — a third of a batch reads "1/3". A
  /// weight does not: 125.5 g came out as "125 1/2", and nobody writes a half
  /// gram that way. So a raw unit writes a plain decimal, trimmed of the
  /// zeros its precision does not need.
  String format(double count) {
    final int? decimals = _decimals;
    if (decimals == null || !count.isFinite) return writeAmount(count);
    final String text = count.toStringAsFixed(decimals);
    if (!text.contains('.')) return text;
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// [count], as this unit's field shows it.
  ///
  /// Display only: the rounding never reaches the stored portion, which moves
  /// only when somebody types or steps.
  double forDisplay(double count) {
    final int? decimals = _decimals;
    if (decimals == null || !count.isFinite) return count;
    final double factor = _pow10(decimals);
    return (count * factor).roundToDouble() / factor;
  }

  /// [servings] — a count of [standard] — expressed in this unit.
  ///
  /// Returns [servings] unchanged when the two cannot be compared: a volume
  /// against a mass needs a density, and §5.5's rule is that a figure nobody
  /// stated is not invented. Pass [food] and the two can be compared whenever
  /// that food really does state one — its own, or a reviewed package
  /// relationship (spec R12). Never a category average read off its name: a
  /// typed amount should log what this food is, not what its kind usually is.
  double countOf(double servings, {required Quantity? standard, Food? food}) {
    final Quantity unit = size;
    if (standard == null || unit.canonicalAmount <= 0) return servings;
    final double? amount = _across(
      servings * standard.canonicalAmount,
      standard.kind,
      unit.kind,
      _usableDensity(food?.effectiveGramsPerMillilitre),
    );
    if (amount == null) return servings;
    final double converted = amount / unit.canonicalAmount;
    return converted.isFinite && converted > 0 ? converted : servings;
  }

  /// And back again, which is what actually gets stored.
  double toDefaultServings(
    double count, {
    required Quantity? standard,
    Food? food,
  }) {
    final Quantity unit = size;
    if (standard == null || standard.canonicalAmount <= 0) return count;
    final double? amount = _across(
      count * unit.canonicalAmount,
      unit.kind,
      standard.kind,
      _usableDensity(food?.effectiveGramsPerMillilitre),
    );
    if (amount == null) return count;
    final double converted = amount / standard.canonicalAmount;
    return converted.isFinite && converted > 0 ? converted : count;
  }

  @override
  bool operator ==(Object other) => other is PortionUnit && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PortionUnit($id)';

  static double _pow10(int decimals) {
    double factor = 1;
    for (int i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return factor;
  }

  /// The one of [units] with this [id], or null — including for a null id, and
  /// for a remembered choice that no longer exists.
  static PortionUnit? withId(List<PortionUnit> units, String? id) {
    if (id == null) return null;
    for (final PortionUnit unit in units) {
      if (unit.id == id) return unit;
    }
    return null;
  }
}

/// The raw units a portion of each kind can be typed in.
///
/// Count is deliberately empty. A food sold by the bar is *already* counted in
/// bars — its serving is the unit — and offering grams for it would mean
/// inventing the weight of a bar, which is the one thing §5.5 forbids.
const Map<UnitKind, List<Unit>> rawPortionUnits = <UnitKind, List<Unit>>{
  UnitKind.mass: <Unit>[Units.gram, Units.ounce],
  UnitKind.volume: <Unit>[Units.millilitre, Units.flOz],
  UnitKind.count: <Unit>[],
};

/// Every way [food]'s portion can be typed: its own servings first, then the
/// raw units of the same kind.
///
/// Only servings that can be written as a multiple of the default one are
/// offered — the same kind, so the two are directly comparable. One that
/// cannot be converted is left out rather than offered and mis-stored.
List<PortionUnit> portionUnitsFor(Food? food, {ServingOption? standard}) {
  // No food, no units — checked before [standard] is consulted, because a
  // caller supplying one for a food that has not loaded yet would otherwise
  // reach the dereference below and throw (review F4).
  if (food == null) return const <PortionUnit>[];
  // The row the portion is actually counted in, which is not always the
  // food's first: a planned entry can name its own (spec R12).
  final ServingOption? base = standard ?? food.defaultServing;
  if (base == null) return const <PortionUnit>[];
  final UnitKind kind = base.amount.kind;
  // The other kind, when there is one. Count has none: a food sold by the bar
  // is already counted in bars.
  final UnitKind? other = kind == UnitKind.mass
      ? UnitKind.volume
      : kind == UnitKind.volume
      ? UnitKind.mass
      : null;
  // Offered only when this food can actually answer it — its own stated or
  // inferred density, or a reviewed package relationship that still matches
  // its current pack and serving (spec R12). A stale or missing relation
  // offers nothing, rather than offering a unit that would be guessed at.
  // A density that cannot answer anything is not a smaller answer. A stored
  // zero, negative or NaN would offer the chip and then convert to infinity
  // or NaN, and the fallback in countOf is to return the typed number
  // unchanged — so the guard has to be where the unit is *offered*.
  final double? crossDensity = _usableDensity(food.effectiveGramsPerMillilitre);
  final bool canCross = other != null && crossDensity != null;
  return <PortionUnit>[
    for (final ServingOption option in food.servingOptions)
      if (option.amount.kind == kind && option.amount.canonicalAmount > 0)
        PortionUnit.serving(option),
    for (final Unit unit in rawPortionUnits[kind] ?? const <Unit>[])
      PortionUnit.raw(unit),
    if (canCross)
      for (final Unit unit in rawPortionUnits[other] ?? const <Unit>[])
        PortionUnit.raw(unit),
  ];
}

/// Macros reached through a reviewed package relationship (spec R9–R12).
///
/// Carries the qualifier with the number rather than folding it in: an
/// 'about 2 servings' package gives an exact-looking total that is not an
/// exact measurement, and whoever shows it has to be able to say so.
@immutable
class PackagePortion {
  const PackagePortion({
    required this.macros,
    required this.serving,
    required this.coverage,
    required this.servingCount,
    required this.isApproximate,
  });

  /// The macros for the whole portion — already multiplied out.
  final Macros macros;

  /// The nutrition row those macros came from: the one the relationship was
  /// reviewed against, not whichever row happens to be first.
  ///
  /// Carried rather than left for the caller to look up again. Two rows can
  /// both read '1 cup' and know different nutrients, and a screen that took
  /// the macros from here and the coverage from the food's default serving
  /// would freeze a completeness claim about a row that never contributed a
  /// number (spec §5.6, R12).
  final ServingOption serving;

  /// How much of [macros]' minor nutrients [serving] actually speaks for.
  final NutrientCoverage coverage;

  /// How many of the *selected* nutrition serving that portion came to.
  final double servingCount;

  /// Whether the package's serving count was printed as 'about N'.
  final bool isApproximate;

  @override
  String toString() =>
      'PackagePortion($servingCount servings, approximate: $isApproximate)';
}

/// The macros for [servings] of [food], when the unit the amount was actually
/// entered in — [basis] — can only be answered through a reviewed package
/// relationship (spec R9–R12). Null in every ordinary case.
///
/// Three things this deliberately does not do.
///
/// It never overrides a food that can answer for itself: a stated or inferred
/// density comes first, and a package relation only fills a missing link.
///
/// It scales the *selected* serving's macros, not the food's first volume row.
/// Two rows can both read '1 cup' and carry different numbers, and the
/// relationship was reviewed against one of them.
///
/// And it derives the count from amounts alone, so a zero-calorie food still
/// converts — nothing here divides by energy.
PackagePortion? packagePortionFor({
  required Food? food,
  required PortionUnit? basis,
  required double servings,
  // Which row [servings] counts. The food's first when omitted, which is
  // what a bare count has always meant.
  ServingOption? standard,
}) {
  if (food == null || basis == null || !basis.isRaw) return null;
  if (!servings.isFinite || servings <= 0) return null;
  // Precedence (spec R12): a food with a *usable* density of its own uses
  // it. A stored zero, negative or NaN answers nothing, and must not block
  // the reviewed package relationship that can.
  if (_usableDensity(food.ownGramsPerMillilitre) != null) return null;

  final ServingOption? base = standard ?? food.defaultServing;
  final ServingOption? selected = food.activePackageServing;
  final double? density = _usableDensity(food.packageGramsPerMillilitre);
  if (base == null || selected == null || density == null) return null;
  if (base.amount.canonicalAmount <= 0) return null;
  if (selected.amount.canonicalAmount <= 0) return null;
  // Only when the unit it was entered in could not be answered directly.
  if (basis.size.kind == base.amount.kind) return null;

  final double? inSelected = _across(
    servings * base.amount.canonicalAmount,
    base.amount.kind,
    selected.amount.kind,
    density,
  );
  if (inSelected == null) return null;
  final double count = inSelected / selected.amount.canonicalAmount;
  if (!count.isFinite || count <= 0) return null;

  return PackagePortion(
    macros: selected.macros.scaledBy(count),
    serving: selected,
    coverage: NutrientCoverage.ofOne(selected.macros),
    servingCount: count,
    isApproximate: food.packageNutrition?.isApproximate ?? false,
  );
}

/// [density] when it can actually answer anything, else null.
///
/// Zero, a negative and a NaN are not smaller densities — they are no
/// density at all, and crossing with one yields infinity or NaN rather than
/// failing. Every crossing here goes through this, so a malformed figure
/// declines to convert instead of converting wrongly.
double? _usableDensity(double? density) =>
    density != null && density.isFinite && density > 0 ? density : null;

/// [amount], canonical in [from], expressed canonically in [to].
///
/// Null when the two kinds cannot be crossed at all, or when nothing has
/// stated a density to cross them with — never a guess.
double? _across(double amount, UnitKind from, UnitKind to, double? density) {
  if (from == to) return amount;
  if (density == null || !density.isFinite || density <= 0) return null;
  if (from == UnitKind.volume && to == UnitKind.mass) return amount * density;
  if (from == UnitKind.mass && to == UnitKind.volume) return amount / density;
  return null;
}
