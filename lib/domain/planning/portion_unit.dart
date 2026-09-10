import 'package:meta/meta.dart';

import '../models/food.dart';
import '../parsing/amount_parser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';

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
  /// against a mass needs a density the food has not stated, and §5.5's rule
  /// is that a figure nobody stated is not invented.
  double countOf(double servings, {required Quantity? standard}) {
    final Quantity unit = size;
    if (standard == null ||
        unit.kind != standard.kind ||
        unit.canonicalAmount <= 0) {
      return servings;
    }
    final double converted =
        servings * standard.canonicalAmount / unit.canonicalAmount;
    return converted.isFinite && converted > 0 ? converted : servings;
  }

  /// And back again, which is what actually gets stored.
  double toDefaultServings(double count, {required Quantity? standard}) {
    final Quantity unit = size;
    if (standard == null ||
        unit.kind != standard.kind ||
        standard.canonicalAmount <= 0) {
      return count;
    }
    final double converted =
        count * unit.canonicalAmount / standard.canonicalAmount;
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
List<PortionUnit> portionUnitsFor(Food? food) {
  final ServingOption? standard = food?.defaultServing;
  if (standard == null) return const <PortionUnit>[];
  final UnitKind kind = standard.amount.kind;
  return <PortionUnit>[
    for (final ServingOption option in food!.servingOptions)
      if (option.amount.kind == kind && option.amount.canonicalAmount > 0)
        PortionUnit.serving(option),
    for (final Unit unit in rawPortionUnits[kind] ?? const <Unit>[])
      PortionUnit.raw(unit),
  ];
}
