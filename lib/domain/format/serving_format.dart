import '../models/food.dart';
import '../parsing/amount_parser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'quantity_format.dart';

/// How a serving reads in a list (spec §5.5).
///
/// Three rules, in order, and the order is the point:
///
///  1. **The packet's own words**, when the label has them — "1 container",
///     "½ cup", "2 pieces". A container is not a unit anything converts to,
///     which is why it is not stored as one, but it is what is printed on the
///     lid and what the person holding it is looking for.
///  2. **Imperial**, when the label gave only a metric figure. Every source
///     reports metrically however the box is written, and a US kitchen does
///     not measure in grams.
///  3. **The reference left alone.** A per-100 g figure is not a serving, and
///     converting it to 3.5 oz makes it look like one.
abstract final class ServingFormat {
  /// Words that name a portion without being a unit anything converts to.
  ///
  /// Values are what to print; keys include the abbreviations Open Food Facts
  /// actually ships — its US yogurt entries are full of "1 con (150 g)", which
  /// is not something to show anybody as written.
  static const Map<String, String> _packetWords = <String, String>{
    'container': 'container',
    'con': 'container',
    'cont': 'container',
    'ctn': 'container',
    'package': 'package',
    'pkg': 'package',
    'pack': 'pack',
    'packet': 'packet',
    'pouch': 'pouch',
    'piece': 'piece',
    'pc': 'piece',
    'pcs': 'piece',
    'bar': 'bar',
    'bottle': 'bottle',
    'btl': 'bottle',
    'can': 'can',
    'box': 'box',
    'bag': 'bag',
    'tub': 'tub',
    'stick': 'stick',
    'patty': 'patty',
    'scoop': 'scoop',
    'wrap': 'wrap',
    'roll': 'roll',
    'link': 'link',
    'cookie': 'cookie',
    'cracker': 'cracker',
    'biscuit': 'biscuit',
    'sandwich': 'sandwich',
    'burrito': 'burrito',
    'bun': 'bun',
    'egg': 'egg',
    'each': 'each',
    'ea': 'each',
  };

  /// A few plurals English does not make by adding an s.
  static const Map<String, String> _plurals = <String, String>{
    'patty': 'patties',
    'each': 'each',
  };

  /// Labels are written both ways — "2 piece" and "2 pieces" — and the table
  /// above is keyed in the singular.
  static String _singular(String word) {
    if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
    if (word.endsWith('s')) return word.substring(0, word.length - 1);
    return word;
  }

  static String describe(ServingOption serving) {
    // Rule 3 first: nothing below should get the chance to dress it up.
    if (serving.isReference) return serving.label;
    return packetPhrase(serving.label) ?? QuantityFormat.format(serving.amount);
  }

  /// The portion a label leads with, in words, or null when it names none.
  ///
  /// "1 CONTAINER (150 g)" reads back as "1 container"; "0.5 cup (89 g)" as
  /// "½ cup". A bare "150 g" returns null — there is no packet phrase there,
  /// only the metric figure every source already reports, and the caller has a
  /// better answer for that than repeating it.
  ///
  /// "1 serving (28 g)" returns null too. It is technically a portion and
  /// says nothing at all.
  static String? packetPhrase(String label) {
    final RegExpMatch? match = RegExp(
      '^\\s*((?:\\d+\\s*)?[${vulgarFractions.keys.join()}]'
      '|\\d+(?:[./\\s]\\d+)*)\\s*([a-zA-Z]+)',
    ).firstMatch(label);
    if (match == null) return null;

    final double? amount = parseAmount(match.group(1)!);
    if (amount == null || amount <= 0) return null;

    final String word = match.group(2)!.toLowerCase();

    final Unit? unit = Units.parse(word);
    // The metric figure is not a phrase; turning it into one is the caller's
    // job, and it has a better answer than repeating what the source said.
    if (unit != null && unit.system == UnitSystem.metric) return null;
    // A unit that prints as nothing — "ea", "item" — is a word to fall
    // through to the table with, not a measure to format.
    if (unit != null && unit.label.isNotEmpty) {
      return QuantityFormat.formatIn(Quantity.of(amount, unit), unit);
    }

    final String? printed = _packetWords[word] ?? _packetWords[_singular(word)];
    if (printed == null) return null;

    final String number = QuantityFormat.count(amount);
    return amount > 1
        ? '$number ${_plurals[printed] ?? '${printed}s'}'
        : '$number $printed';
  }
}
