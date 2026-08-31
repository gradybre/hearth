import 'package:meta/meta.dart';

import '../units/quantity.dart';
import '../units/unit.dart';

/// A free-typed or AI-imported ingredient line, broken into structured fields.
///
/// This structure is what makes scaling and shopping aggregation possible — a
/// raw string cannot be scaled (spec §5.2).
@immutable
class ParsedIngredient {
  const ParsedIngredient({
    required this.raw,
    required this.name,
    this.quantity,
    this.prepNote,
    this.isOptional = false,
  });

  /// The line exactly as it came in, kept so the user can see what the parser
  /// was working from.
  final String raw;

  /// The ingredient itself, with quantity and prep note removed.
  final String name;

  /// Null when the line carries no amount ("salt to taste").
  final Quantity? quantity;

  /// "minced", "finely chopped" — display only, never affects the maths.
  final String? prepNote;

  /// Set by phrases like "to taste" or a trailing "(optional)". Optional
  /// ingredients are excluded from macros and the shopping list (spec §5.2).
  final bool isOptional;

  bool get isQuantified => quantity != null;

  @override
  String toString() =>
      'ParsedIngredient($quantity $name${prepNote == null ? '' : ', $prepNote'})';
}

/// Parses ingredient lines into quantity / unit / item / prep-note (spec §5.2).
///
/// Deliberately conservative: when a line doesn't fit a pattern the parser
/// understands, it returns the whole thing as the name rather than guessing.
/// A wrong quantity is far more damaging than a missing one — it silently
/// corrupts macros and the shopping list.
abstract final class IngredientParser {
  static const Map<String, double> _vulgarFractions = <String, double>{
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

  /// Phrases that mark a line as optional / to taste.
  static final List<RegExp> _optionalMarkers = <RegExp>[
    RegExp(r'\bto taste\b', caseSensitive: false),
    RegExp(r'\(\s*optional\s*\)', caseSensitive: false),
    RegExp(r'\boptional\b', caseSensitive: false),
    RegExp(r'\bfor garnish\b', caseSensitive: false),
    RegExp(r'\bfor serving\b', caseSensitive: false),
  ];

  /// A leading amount: "2", "1.5", "1/2", "1 1/2", "1½", "½", "1-2".
  static final RegExp _leadingAmount = RegExp(
    r'^\s*(\d+\s*[-–]\s*\d+|\d+\s+\d+\s*/\s*\d+|\d+\s*/\s*\d+|\d+(?:\.\d+)?\s*[½⅓⅔¼¾⅕⅙⅚⅛⅜⅝⅞]|\d+(?:\.\d+)?|[½⅓⅔¼¾⅕⅙⅚⅛⅜⅝⅞])\s*',
  );

  /// A pack size following a count: the "x 400g" of "2 x 400g cans".
  ///
  /// Written this way across most of Europe, and read as a bare count it
  /// becomes "2 items" — which contributes nothing to a macro total and
  /// leaves a stray "x" at the front of the name.
  static final RegExp _packSize = RegExp(
    r'^[x×]\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]+)\b\s*',
    caseSensitive: false,
  );

  /// The same thing written the American way: the "(10 oz)" of
  /// "4 (10 oz) bags frozen chopped onion".
  ///
  /// Every US recipe site writes multipacks like this, and read as a bare
  /// count it is "4 items" — no macros at all, and a stray "(10 oz)" left at
  /// the front of the name. The size in the brackets is the whole point of
  /// the line: four of them is forty ounces.
  static final RegExp _parenthesisedPackSize = RegExp(
    r'^\(\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]+)\.?\s*\)\s*',
    caseSensitive: false,
  );

  /// What a pack comes in. Dropped from the name once its size has been
  /// counted, because "2 x 400g cans chopped tomatoes" is 800 g of chopped
  /// tomatoes, not of cans.
  static final RegExp _container = RegExp(
    r'^(?:cans?|tins?|jars?|packs?|packets?|sachets?|bottles?|tubs?|pots?|'
    r'boxes|box|bags?)\s+',
    caseSensitive: false,
  );

  /// Parses one line.
  static ParsedIngredient parse(String line) {
    final String raw = line;
    String working = line.trim();

    bool isOptional = false;
    for (final RegExp marker in _optionalMarkers) {
      if (marker.hasMatch(working)) {
        isOptional = true;
        working = working.replaceAll(marker, ' ');
      }
    }
    working = _tidy(working);

    // A trailing clause after a comma is the prep note: "garlic, minced".
    String? prepNote;
    final int comma = working.indexOf(',');
    if (comma >= 0) {
      final String tail = _tidy(working.substring(comma + 1));
      prepNote = tail.isEmpty ? null : tail;
      working = _tidy(working.substring(0, comma));
    }

    final Quantity? quantity;
    final RegExpMatch? amountMatch = _leadingAmount.firstMatch(working);
    if (amountMatch == null) {
      quantity = null;
    } else {
      final double? amount = _parseAmount(amountMatch.group(1)!);
      String rest = _tidy(working.substring(amountMatch.end));

      // A second, standalone number immediately following the first
      // ("1/4 1/2 small onion", or "1/4-1/2 small onion" — _tidy above
      // already dropped the connecting hyphen) is read as the other end of
      // a range, the same way "1-2 tbsp" always has been. The higher of the
      // two is used — see the note on [_higherOf] for why.
      //
      // "Standalone" is what keeps this from misreading a unit glued to a
      // number with no space — the "8" of "8oz cans" is not a second
      // quantity, and picking between it and the first would invent a number
      // with nothing behind it. That case is left unquantified instead, same
      // as before.
      double? effectiveAmount = amount;
      final RegExpMatch? secondMatch = amount == null
          ? null
          : _leadingAmount.firstMatch(rest);
      if (secondMatch != null) {
        final String secondToken = secondMatch.group(1)!;
        final int tokenEnd = secondMatch.start + secondToken.length;
        final bool standalone =
            tokenEnd >= rest.length || rest[tokenEnd] == ' ';

        final double? secondAmount = standalone
            ? _parseAmount(secondToken)
            : null;
        if (!standalone || secondAmount == null) {
          effectiveAmount = null;
        } else {
          effectiveAmount = _higherOf(amount!, secondAmount);
          rest = _tidy(rest.substring(secondMatch.end));
        }
      }

      Unit? unit;
      double multiplier = 1;

      // "2 x 400g cans" and "4 (10 oz) bags" before anything else: the real
      // amount is the count times the pack size, in the pack's own unit.
      // Both notations mean the same thing and neither is a bare count.
      final RegExpMatch? pack =
          _packSize.firstMatch(rest) ?? _parenthesisedPackSize.firstMatch(rest);
      final Unit? packUnit = pack == null ? null : Units.parse(pack.group(2)!);
      if (pack != null && packUnit != null) {
        unit = packUnit;
        multiplier = double.parse(pack.group(1)!);
        rest = _tidy(rest.substring(pack.end)).replaceFirst(_container, '');
        rest = _tidy(rest);
      } else {
        final int space = rest.indexOf(' ');
        final String firstToken = space < 0 ? rest : rest.substring(0, space);
        final Unit? parsedUnit = Units.parse(firstToken);
        if (parsedUnit != null) {
          unit = parsedUnit;
          rest = space < 0 ? '' : _tidy(rest.substring(space + 1));
        }
      }

      if (effectiveAmount == null) {
        quantity = null;
      } else {
        // A bare number with no unit is a count: "2 eggs".
        quantity = Quantity.of(
          effectiveAmount * multiplier,
          unit ?? Units.item,
        );
        working = rest.isEmpty ? working : rest;
      }
    }

    return ParsedIngredient(
      raw: raw,
      name: _tidy(working),
      quantity: quantity,
      prepNote: prepNote,
      isOptional: isOptional,
    );
  }

  /// A hyphenated or en-dash range: "1-2", "3–4".
  static final RegExp _hyphenRange = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');

  /// Brendan's call: a range resolves to one of its two stated numbers, not
  /// an average — a measuring cup has a line for "1/2", not for "3/8" — and
  /// between the two, the higher one. A macro tracker that quietly rounds
  /// down is the more dangerous failure: it is the well-known way a food log
  /// stops matching what was actually eaten without ever looking wrong, and
  /// it is a worse failure than the recipe coming out with a little extra
  /// onion in it.
  static double _higherOf(double a, double b) => a > b ? a : b;

  /// Parses a lone amount token into a number.
  static double? _parseAmount(String token) {
    final String text = token.trim();
    final RegExpMatch? range = _hyphenRange.firstMatch(text);
    if (range != null) {
      return _higherOf(
        double.parse(range.group(1)!),
        double.parse(range.group(2)!),
      );
    }

    // Whole number followed by a vulgar fraction: "1½".
    final RegExpMatch? mixedVulgar = RegExp(
      r'^(\d+(?:\.\d+)?)\s*([½⅓⅔¼¾⅕⅙⅚⅛⅜⅝⅞])$',
    ).firstMatch(text);
    if (mixedVulgar != null) {
      return double.parse(mixedVulgar.group(1)!) +
          _vulgarFractions[mixedVulgar.group(2)!]!;
    }

    final double? vulgar = _vulgarFractions[text];
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

    // Plain fraction: "1/2".
    final RegExpMatch? fraction = RegExp(r'^(\d+)\s*/\s*(\d+)$')
        .firstMatch(text);
    if (fraction != null) {
      final double denominator = double.parse(fraction.group(2)!);
      if (denominator == 0) return null;
      return double.parse(fraction.group(1)!) / denominator;
    }

    return double.tryParse(text);
  }

  static String _tidy(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[,;\-–]+|[,;\-–]+$'), '')
      .trim();
}
