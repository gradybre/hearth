/// Reading the numbers people actually write for amounts.
///
/// Kitchens are the last place decimals won: a measuring cup is marked ⅓ and
/// ⅔, a spoon is a half, and a recipe says "1 1/2 cups". Anywhere Hearth asks
/// for an amount it has to read those back, or the answer is "type 0.6667",
/// which nobody is going to do.
///
/// Shared rather than owned by the ingredient parser, which is where this
/// logic started: a serving size typed into the food editor needs exactly the
/// same reading, and two copies of it would drift.
library;

/// Single-character fractions, as typed on a phone or pasted from the web.
const Map<String, double> vulgarFractions = <String, double>{
  '½': 0.5,
  '⅓': 1 / 3,
  '⅔': 2 / 3,
  '¼': 0.25,
  '¾': 0.75,
  '⅕': 0.2,
  '⅙': 1 / 6,
  '⅚': 5 / 6,
  '⅛': 0.125,
  '⅜': 0.375,
  '⅝': 0.625,
  '⅞': 0.875,
};

/// The characters an amount can legitimately contain.
///
/// Used to keep a full keyboard from putting letters into a number field on
/// the platforms that have no numeric pad carrying both "." and "/".
final RegExp amountCharacters = RegExp(
  '[0-9 ./${vulgarFractions.keys.join()}]',
);

/// Parses one written amount into a number, or null when it is not one.
///
/// Understands "2", "1.5", "1/2", "2 1/3", "1½" and a bare "½". Returns null
/// rather than a guess for anything else — a serving size nobody can read
/// back is better left empty than silently turned into a number the user did
/// not mean.
double? parseAmount(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return null;

  // Whole number followed by a vulgar fraction: "1½".
  final RegExpMatch? mixedVulgar = RegExp(
    '^(\\d+(?:\\.\\d+)?)\\s*([${vulgarFractions.keys.join()}])\$',
  ).firstMatch(text);
  if (mixedVulgar != null) {
    return double.parse(mixedVulgar.group(1)!) +
        vulgarFractions[mixedVulgar.group(2)!]!;
  }

  final double? vulgar = vulgarFractions[text];
  if (vulgar != null) return vulgar;

  // Mixed number: "1 1/2".
  final RegExpMatch? mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$')
      .firstMatch(text);
  if (mixed != null) {
    final double denominator = double.parse(mixed.group(3)!);
    if (denominator == 0) return null;
    return double.parse(mixed.group(1)!) +
        double.parse(mixed.group(2)!) / denominator;
  }

  // Plain fraction: "2/3".
  final RegExpMatch? fraction = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(text);
  if (fraction != null) {
    final double denominator = double.parse(fraction.group(2)!);
    if (denominator == 0) return null;
    return double.parse(fraction.group(1)!) / denominator;
  }

  return double.tryParse(text);
}

/// Writes a number back the way it would be typed — the inverse of
/// [parseAmount], and its round-trip partner.
///
/// A ⅔ cup serving stored as a double is 0.6666666666666666, which is neither
/// what anybody typed nor anything they would type over. Only the fractions a
/// kitchen actually uses are recognised; anything else keeps its digits rather
/// than being rounded into a number the user never entered.
///
/// Fractions are written "2/3" and "1 1/2" rather than as ⅔ and 1½ glyphs,
/// because this is what goes *into an editable field*: a glyph is harder to
/// correct than the characters a keyboard can produce. Read-only surfaces use
/// `QuantityFormat`, which prefers the glyphs.
String writeAmount(double value) {
  if (value == value.roundToDouble()) return value.round().toString();

  const Map<String, double> fractions = <String, double>{
    '1/2': 0.5,
    '1/3': 1 / 3,
    '2/3': 2 / 3,
    '1/4': 0.25,
    '3/4': 0.75,
    '1/8': 0.125,
    '3/8': 0.375,
    '5/8': 0.625,
    '7/8': 0.875,
  };

  final double whole = value - value % 1;
  final double fraction = value - whole;
  for (final MapEntry<String, double> entry in fractions.entries) {
    if ((fraction - entry.value).abs() < 1e-9) {
      return whole == 0 ? entry.key : '${whole.round()} ${entry.key}';
    }
  }
  return '$value';
}
