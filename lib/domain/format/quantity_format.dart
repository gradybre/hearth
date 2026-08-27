import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';

/// Display formatting for quantities.
///
/// **Rounding happens here and nowhere else.** Stored values keep full
/// canonical precision; this layer is the only place a number is shortened for
/// human eyes (spec §4, "Round on display only"). Volume and count read as
/// friendly fractions ("1 1/3 tbsp"), weight and metric read as decimals
/// ("50 g", "237 ml") — spec §5.2.
abstract final class QuantityFormat {
  /// Cooking fractions, largest denominator last so the closest match wins
  /// ties toward the simpler fraction.
  static const List<(double, String)> _fractionGlyphs = <(double, String)>[
    (0.5, '½'),
    (1 / 3, '⅓'),
    (2 / 3, '⅔'),
    (0.25, '¼'),
    (0.75, '¾'),
    (1 / 8, '⅛'),
    (3 / 8, '⅜'),
    (5 / 8, '⅝'),
    (7 / 8, '⅞'),
    (1 / 6, '⅙'),
    (5 / 6, '⅚'),
  ];

  /// How close a value must be to a cooking fraction to be shown as one.
  /// Wider than a rounding error, tighter than a lie: 4 tsp is 1.3333 tbsp and
  /// should read "1 1/3", but 1.4 tbsp should stay "1.4".
  static const double _fractionTolerance = 0.02;

  static const Map<String, String> _plurals = <String, String>{
    'cup': 'cups',
    'clove': 'cloves',
    'slice': 'slices',
    'pinch': 'pinches',
  };

  /// Formats [quantity] for display, choosing the unit automatically.
  static String format(
    Quantity quantity, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    final Unit unit = UnitConverter.displayUnitFor(quantity, system: system);
    return formatIn(quantity, unit);
  }

  /// Formats [quantity] in a specific [unit].
  static String formatIn(Quantity quantity, Unit unit) {
    final double amount = quantity.amountIn(unit);
    final String number = formatAmount(amount, unit);
    final String label = _label(unit, amount);
    return label.isEmpty ? number : '$number $label';
  }

  /// Formats a bare number the way [unit] should read.
  ///
  /// Imperial volume and counts get cooking fractions; weight and metric units
  /// get decimals. Nobody writes "1 1/3 ml".
  static String formatAmount(double amount, Unit unit) {
    final bool decimal =
        unit.kind == UnitKind.mass || unit.system == UnitSystem.metric;
    return decimal ? _decimal(amount) : _fractional(amount);
  }

  /// Weight: decimals, no fractions. Whole numbers above 10, one place below.
  static String _decimal(double amount) {
    if (amount.abs() >= 10) return amount.round().toString();
    final String oneDp = amount.toStringAsFixed(1);
    return oneDp.endsWith('.0') ? oneDp.substring(0, oneDp.length - 2) : oneDp;
  }

  /// Volume and count: mixed numbers with cooking fractions where one fits.
  static String _fractional(double amount) {
    if (amount == 0) return '0';
    final bool negative = amount < 0;
    final double value = amount.abs();
    final int whole = value.floor();
    final double remainder = value - whole;

    final String? glyph = _closestFraction(remainder);
    final String sign = negative ? '-' : '';

    if (glyph == null) {
      // No cooking fraction is close enough — show a short decimal rather than
      // pretend to a precision the cook can't measure.
      final String text = value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'\.?0+$'), '');
      return '$sign$text';
    }
    if (glyph.isEmpty) return '$sign$whole';
    if (whole == 0) return '$sign$glyph';
    return '$sign$whole$glyph';
  }

  /// Returns the glyph for the nearest cooking fraction, `''` when the
  /// remainder rounds away entirely, or null when nothing is close enough.
  static String? _closestFraction(double remainder) {
    if (remainder <= _fractionTolerance) return '';
    // Close enough to the next whole number that the caller should show a
    // decimal (or the whole number) rather than a 7/8-style fraction.
    if (remainder >= 1 - _fractionTolerance) return null;

    String? best;
    double bestDelta = double.infinity;
    for (final (double value, String glyph) in _fractionGlyphs) {
      final double delta = (remainder - value).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = glyph;
      }
    }
    return bestDelta <= _fractionTolerance ? best : null;
  }

  static String _label(Unit unit, double amount) {
    if (unit.label.isEmpty) return '';
    // English takes the singular for any amount up to one: "1/2 cup",
    // "3/4 cup", "1 cup" — but "1 1/2 cups" and "0 cups".
    final bool singular = amount > 0 && amount <= 1;
    if (singular) return unit.label;
    return _plurals[unit.label] ?? unit.label;
  }
}
