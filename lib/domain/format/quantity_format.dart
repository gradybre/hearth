import '../units/mass_display_mode.dart';
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
    'scoop': 'scoops',
    'bar': 'bars',
    'package': 'packages',
    'packet': 'packets',
    'container': 'containers',
    'bottle': 'bottles',
    'can': 'cans',
    'piece': 'pieces',
    'patty': 'patties',
    'stick': 'sticks',
    'square': 'squares',
    'tortilla': 'tortillas',
  };

  /// Formats [quantity] for display, choosing the unit automatically.
  ///
  /// [massDisplayMode], [packSize], and [packageUnit] feed the imperial mass
  /// unit policy in [UnitConverter.displayUnitFor]; they have no effect on
  /// non-mass quantities or under a metric [system].
  static String format(
    Quantity quantity, {
    UnitSystem system = UnitSystem.imperial,
    MassDisplayMode massDisplayMode = MassDisplayMode.automatic,
    Quantity? packSize,
    Unit? packageUnit,
  }) {
    final Unit unit = UnitConverter.displayUnitFor(
      quantity,
      system: system,
      massDisplayMode: massDisplayMode,
      packSize: packSize,
      packageUnit: packageUnit,
    );
    return formatIn(quantity, unit);
  }

  /// Formats [quantity] in the unit it was authored in, falling back to the
  /// reader's preference when there is no authored unit.
  ///
  /// This is for surfaces that are showing the user their own input back —
  /// an editor's parse preview, an import review screen. Converting there
  /// would answer a question nobody asked: typing "1.5 kg" and being shown
  /// "3.3 lb" makes it harder, not easier, to confirm the line parsed
  /// correctly. Reading surfaces use [format] and honour the reader's system
  /// (spec §4).
  static String formatAsAuthored(
    Quantity quantity, {
    UnitSystem system = UnitSystem.imperial,
  }) {
    final Unit? authored = quantity.preferredUnit;
    if (authored == null) return format(quantity, system: system);
    return formatIn(quantity, authored, preservePrecision: true);
  }

  /// Formats [quantity] in a specific [unit].
  static String formatIn(
    Quantity quantity,
    Unit unit, {
    bool preservePrecision = false,
  }) {
    final double amount = quantity.amountIn(unit);
    final String number =
        preservePrecision &&
            unit.kind == UnitKind.mass &&
            unit.system == UnitSystem.imperial
        ? _authoredMassDecimal(amount)
        : formatAmount(amount, unit);
    // Pluralisation has to agree with what [number] actually shows, not with
    // the unrounded amount. 240 ml is 1.0144 cup — greater than one, but it
    // *displays* as "1", and "1 cups" is what happens when the two disagree.
    //
    // The magnitude decides it, not the value: one cup taken back out of a
    // meal is "−1 cup", the same one cup it was on the way in.
    final String label = _label(unit, _displayedAmount(amount).abs());
    return label.isEmpty ? number : '$number $label';
  }

  /// The amount as it will actually print, snapped to a whole number within
  /// the same tolerance the cooking-fraction glyphs use.
  ///
  /// A source's conversion factor rarely lands on a clean number — 240 ml of
  /// broth is 1.0144 US cup — and the display layer already hides that by
  /// rounding to "1". Pluralisation has to see the same rounded value or it
  /// disagrees with the number sitting right next to it.
  static double _displayedAmount(double amount) {
    final double whole = amount.floorToDouble();
    final double remainder = amount - whole;
    if (remainder <= _fractionTolerance) return whole;
    if (remainder >= 1 - _fractionTolerance) return whole + 1;
    return amount;
  }

  /// Formats a bare number the way [unit] should read.
  ///
  /// Imperial mass (oz/lb) gets a trimmed decimal that never silently loses
  /// a package's real weight above ten units, nor rounds a tiny amount away
  /// to nothing. Imperial volume and counts get cooking fractions; metric
  /// units get plain decimals. Nobody writes "1 1/3 ml".
  static String formatAmount(double amount, Unit unit) {
    if (unit.kind == UnitKind.mass && unit.system == UnitSystem.imperial) {
      return _imperialMassDecimal(amount);
    }
    final bool decimal =
        unit.kind == UnitKind.mass || unit.system == UnitSystem.metric;
    return decimal ? _decimal(amount) : _fractional(amount);
  }

  /// A bare count — servings, multipliers — with no unit attached.
  ///
  /// Fractional rather than decimal: "½×" and "1½" are how a cook reads a
  /// half, and "0.5×" is how a spreadsheet does. Rounding lives here and
  /// nowhere else, so a screen cannot invent its own.
  static String count(double amount) => _fractional(amount);

  /// The character a number below zero is printed with.
  ///
  /// A quantity can be negative since a component can be taken out of a meal
  /// (spec §5.2), and on the line "−1 oz Lettuce" the sign is the entire
  /// difference between having lettuce and not. So it is the real minus
  /// U+2212, which a screen reader says out loud as "minus" — a hyphen is a
  /// dash, and never colour or punctuation alone for meaning (§6.3).
  static const String _minus = '−';

  /// Weight (metric mass) and metric volume: decimals, no fractions. Whole
  /// numbers above 10, one place below.
  static String _decimal(double amount) {
    if (amount < 0) return '$_minus${_decimal(-amount)}';
    if (amount >= 10) return amount.round().toString();
    final String oneDp = amount.toStringAsFixed(1);
    return oneDp.endsWith('.0') ? oneDp.substring(0, oneDp.length - 2) : oneDp;
  }

  /// Imperial mass (oz/lb): a trimmed decimal, up to two places, that never
  /// collapses a package's real weight to a whole number above ten ("14.5 oz"
  /// must not become "15 oz"), and never rounds a tiny amount all the way to
  /// zero.
  static String _imperialMassDecimal(double amount) {
    if (amount < 0) return '$_minus${_imperialMassDecimal(-amount)}';
    if (amount == 0) return '0';
    if (amount < 0.01) return _significantDecimal(amount);
    return _trimmedFixed(amount, 2);
  }

  static String _significantDecimal(double amount) {
    final String text = amount.toStringAsPrecision(2);
    if (text.contains('e')) return text.replaceFirst(RegExp(r'\.0+e'), 'e');
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  static String _authoredMassDecimal(double amount) {
    if (amount < 0) return '$_minus${_authoredMassDecimal(-amount)}';
    if (amount == 0) return '0';
    if (amount < 1e-8) return _significantDecimal(amount);
    // Remove conversion noise, retaining the precision printed on packages.
    return _trimmedFixed(amount, 9);
  }

  /// [amount] fixed to [decimals] places, with trailing zeros (and a bare
  /// trailing decimal point) trimmed away.
  static String _trimmedFixed(double amount, int decimals) {
    final String text = amount.toStringAsFixed(decimals);
    if (!text.contains('.')) return text;
    final String trimmed = text.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// Volume and count: mixed numbers with cooking fractions where one fits.
  static String _fractional(double amount) {
    if (amount == 0) return '0';
    final bool negative = amount < 0;
    final double value = amount.abs();
    final int whole = value.floor();
    final double remainder = value - whole;

    final String? glyph = _closestFraction(remainder);
    final String sign = negative ? _minus : '';

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
