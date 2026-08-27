import 'package:meta/meta.dart';

import 'density.dart';
import 'quantity.dart';
import 'unit.dart';

/// The outcome of a conversion that may not have been exact.
///
/// Spec §5.2: when density is unknown we fall back to a literal multiply and
/// **flag it** rather than inventing a number.
@immutable
class ConversionResult {
  const ConversionResult({required this.quantity, this.densityMissing = false});

  final Quantity quantity;

  /// True when a volume<->weight conversion was requested for an ingredient
  /// with no known density. The quantity is returned unconverted and the UI
  /// must surface the flag.
  final bool densityMissing;

  bool get isExact => !densityMissing;
}

/// Conversion, normalisation, and display-unit selection.
///
/// Nothing here rounds — rounding is display-only and lives in
/// `format/quantity_format.dart` (spec §4, "Round on display only").
abstract final class UnitConverter {
  /// Units auto-selected when normalising volume. Pints, quarts, and gallons
  /// are deliberately excluded: recipes say "8 cups", not "2 quarts".
  static const List<Unit> _imperialVolumeLadder = <Unit>[
    Units.tsp,
    Units.tbsp,
    Units.cup,
  ];
  static const List<Unit> _metricVolumeLadder = <Unit>[
    Units.millilitre,
    Units.litre,
  ];
  static const List<Unit> _imperialMassLadder = <Unit>[
    Units.ounce,
    Units.pound,
  ];
  static const List<Unit> _metricMassLadder = <Unit>[
    Units.gram,
    Units.kilogram,
  ];

  /// Exact same-kind conversion of a bare number.
  static double convert(num amount, Unit from, Unit to) {
    if (from.kind != to.kind) {
      throw ArgumentError(
        'convert() is same-kind only; use crossKind() for '
        '${from.kind.name} -> ${to.kind.name}.',
      );
    }
    return amount.toDouble() * from.toCanonical / to.toCanonical;
  }

  /// Converts [quantity] to [targetKind], using [ingredient]'s density when the
  /// conversion crosses volume and mass.
  ///
  /// Returns the quantity untouched with [ConversionResult.densityMissing] set
  /// when no density is known. [gramsPerMillilitre] overrides the table lookup
  /// (used when a food carries its own measured density).
  static ConversionResult crossKind(
    Quantity quantity,
    UnitKind targetKind, {
    String? ingredient,
    double? gramsPerMillilitre,
  }) {
    if (quantity.kind == targetKind) {
      return ConversionResult(quantity: quantity);
    }
    if (quantity.kind == UnitKind.count || targetKind == UnitKind.count) {
      // "3 eggs" has no general conversion to grams; a per-food serving size
      // handles this, not a density.
      return ConversionResult(quantity: quantity, densityMissing: true);
    }

    final double? density =
        gramsPerMillilitre ??
        (ingredient == null ? null : DensityTable.lookup(ingredient));
    if (density == null) {
      return ConversionResult(quantity: quantity, densityMissing: true);
    }

    final double converted = targetKind == UnitKind.mass
        ? quantity.canonicalAmount *
              density // ml -> g
        : quantity.canonicalAmount / density; // g -> ml

    return ConversionResult(
      quantity: Quantity.canonical(
        canonicalAmount: converted,
        kind: targetKind,
      ),
    );
  }

  /// The ladder of display units for a kind in a given system.
  static List<Unit> ladderFor(UnitKind kind, UnitSystem system) =>
      switch ((kind, system)) {
        (UnitKind.volume, UnitSystem.metric) => _metricVolumeLadder,
        (UnitKind.volume, _) => _imperialVolumeLadder,
        (UnitKind.mass, UnitSystem.metric) => _metricMassLadder,
        (UnitKind.mass, _) => _imperialMassLadder,
        (UnitKind.count, _) => const <Unit>[Units.item],
      };

  /// Below this share of a unit, step down the ladder: an eighth of a cup
  /// reads better as 2 tbsp.
  static const double _minShareOfUnit = 0.25;

  /// Picks the friendliest unit to show [quantity] in.
  ///
  /// Starts from the authored unit when the reader's system shares it, then:
  ///  * **promotes** while the next unit up still leaves at least 1 of it —
  ///    3 tsp becomes 1 tbsp, 4 tsp becomes 1 1/3 tbsp (spec §5.2);
  ///  * **demotes** while less than a quarter of the current unit is left —
  ///    an eighth of a cup becomes 2 tbsp.
  ///
  /// Promotion never runs away with a well-formed authored unit: half a cup
  /// stays half a cup rather than becoming 8 tbsp, because cup is where the
  /// walk starts and tbsp is below it. Count units are always preserved as
  /// authored — "2 cloves" must not become "2 items".
  static Unit displayUnitFor(
    Quantity quantity, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    final Unit? preferred = quantity.preferredUnit;
    if (quantity.kind == UnitKind.count) {
      return preferred ?? Units.item;
    }

    final List<Unit> ladder = ladderFor(quantity.kind, system);
    int index = (preferred != null && ladder.contains(preferred))
        ? ladder.indexOf(preferred)
        : 0;
    if (quantity.isZero) return ladder[index];

    while (index + 1 < ladder.length &&
        quantity.amountIn(ladder[index + 1]).abs() >= 1) {
      index++;
    }
    while (index > 0 &&
        quantity.amountIn(ladder[index]).abs() < _minShareOfUnit) {
      index--;
    }
    return ladder[index];
  }

  /// Re-expresses [quantity] in the unit [displayUnitFor] would choose.
  ///
  /// This is the "3 tsp -> 1 tbsp" normalisation applied after scaling. The
  /// stored value is unchanged; only [Quantity.preferredUnit] moves, so this
  /// can never introduce drift.
  static Quantity normalise(
    Quantity quantity, {
    UnitSystem system = UnitSystem.imperial,
  }) => quantity.withPreferredUnit(displayUnitFor(quantity, system: system));
}
