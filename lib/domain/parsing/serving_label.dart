import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';
import 'amount_parser.dart';

/// The household measure a serving label leads with, when it names one.
///
/// Nutrition sources report serving sizes metrically whatever the packet
/// says: Open Food Facts' `serving_quantity` is grams for every US product
/// checked, and the USDA function returns `serving_grams`. Read only those and
/// every scanned food comes back in grams however its label was written —
/// which is what Brendan hit scanning a Kirkland cheddar whose box says
/// "1/4 cup".
///
/// The measure usually survives in the label text beside the metric figure
/// ("3/4 cup (28 g)", "1 oz (28 g)", "2 Tbsp"), and that is the one printed on
/// the box, so it is worth recovering.
///
/// "1 serving (28 g)", "1 bar (43 g)" and "0.5 Can (207 g)" name nothing a
/// cook can measure out, so those come back null and the grams stand.
Quantity? statedHouseholdMeasure(String text) {
  // A vulgar glyph is part of the number, not the unit: "¾ cup (28 g)" is
  // printed exactly that way on a box, and a digits-only pattern read it as
  // no amount at all.
  final RegExpMatch? match = RegExp(
    '^\\s*((?:\\d+\\s*)?[${vulgarFractions.keys.join()}]'
    '|\\d+(?:[./\\s]\\d+)*)\\s*([a-zA-Z]+)',
  ).firstMatch(text);
  if (match == null) return null;

  final double? amount = parseAmount(match.group(1)!);
  if (amount == null || amount <= 0) return null;

  final Unit? unit = Units.parse(match.group(2)!);
  if (unit == null) return null;
  // Already the metric figure, so there is nothing to restore.
  if (unit == Units.gram || unit == Units.millilitre) return null;
  if (unit.kind == UnitKind.count) return null;

  return Quantity.of(amount, unit);
}

/// How to store a serving of [grams] whose packet reads [label].
///
/// A stated *volume* is kept as the volume: "1/4 cup (28 g)" against a weight
/// of grams is not a rounding of it — it is the density of this food, stated
/// by its own maker, and often the only place that fact exists.
///
/// A stated *mass* re-expresses the exact grams instead of trusting the
/// label's own rounding, so "1 oz (28 g)" stores 28 g shown as ounces rather
/// than 28.35.
Quantity servingAmountFor(String label, {required double grams}) {
  final Quantity? stated = statedHouseholdMeasure(label);
  if (stated == null) return Quantity.of(grams, Units.gram);
  if (stated.kind == UnitKind.volume) return stated;
  return UnitConverter.normalise(
    Quantity.of(grams, Units.gram),
    system: UnitSystem.imperial,
  );
}
