/// Ingredient densities in grams per millilitre, for volume <-> weight
/// conversion (spec §5.2).
///
/// **Scope is deliberately small and is an open decision (spec §12), parked for
/// now.** The expectation is that per-food serving weights coming from Open
/// Food Facts / USDA (spec §5.5) will supply most real conversions once Phase 2
/// lands — a food record that says "1 cup = 240 g" beats any generic table.
/// `UnitConverter.crossKind` already takes a `gramsPerMillilitre` override for
/// exactly that hand-off.
///
/// Until then this covers pantry staples where a cup-to-gram figure is stable
/// and well documented. Anything absent is *flagged* rather than silently
/// guessed — an unflagged wrong conversion is worse than an honest
/// "we don't know".
library;

import '../text/text_normaliser.dart';
import 'unit.dart';

/// A density lookup over a normalised ingredient name.
abstract final class DensityTable {
  /// Grams per millilitre. Values chosen from standard baking references
  /// (e.g. all-purpose flour at 125 g per US cup = 0.528 g/ml).
  static const Map<String, double> gramsPerMillilitre = <String, double>{
    // Liquids
    'water': 1.0,
    'milk': 1.03,
    'buttermilk': 1.03,
    'heavy cream': 0.994,
    'greek yogurt': 1.03,
    'yogurt': 1.03,
    'chicken broth': 1.0,
    'chicken stock': 1.0,
    'vegetable broth': 1.0,
    'soy sauce': 1.11,
    'vinegar': 1.01,
    'olive oil': 0.918,
    'vegetable oil': 0.92,
    'canola oil': 0.92,
    'butter': 0.911,
    'honey': 1.42,
    'maple syrup': 1.32,
    'molasses': 1.4,
    'peanut butter': 1.08,

    // Dry goods
    'all-purpose flour': 0.528,
    'bread flour': 0.55,
    'whole wheat flour': 0.51,
    'granulated sugar': 0.845,
    'brown sugar': 0.93,
    'powdered sugar': 0.53,
    'cornstarch': 0.51,
    'cocoa powder': 0.42,
    'rolled oats': 0.4,
    'white rice': 0.85,
    'breadcrumbs': 0.42,
    'grated parmesan': 0.4,
    'table salt': 1.22,
    'kosher salt': 0.6,
    'baking soda': 0.92,
    'baking powder': 0.9,
  };

  /// Aliases mapping common ingredient spellings onto a table key.
  static const Map<String, String> _aliases = <String, String>{
    'flour': 'all-purpose flour',
    'plain flour': 'all-purpose flour',
    'ap flour': 'all-purpose flour',
    'sugar': 'granulated sugar',
    'white sugar': 'granulated sugar',
    'caster sugar': 'granulated sugar',
    'confectioners sugar': 'powdered sugar',
    'icing sugar': 'powdered sugar',
    'light brown sugar': 'brown sugar',
    'dark brown sugar': 'brown sugar',
    'salt': 'table salt',
    'evoo': 'olive oil',
    'extra virgin olive oil': 'olive oil',
    'unsalted butter': 'butter',
    'salted butter': 'butter',
    'melted butter': 'butter',
    'whole milk': 'milk',
    'skim milk': 'milk',
    'double cream': 'heavy cream',
    'whipping cream': 'heavy cream',
    'parmesan': 'grated parmesan',
    'parmigiano reggiano': 'grated parmesan',
    'oats': 'rolled oats',
    'rice': 'white rice',
    'cocoa': 'cocoa powder',
    'corn starch': 'cornstarch',
    'cornflour': 'cornstarch',
  };

  /// Normalises an ingredient string for lookup.
  ///
  /// Delegates to the shared normaliser so density lookup, consolidation, and
  /// remembered matches all key on the same string.
  /// The key this table matches on.
  ///
  /// A hyphen separates rather than binds: `normaliseKey` keeps hyphens, so
  /// "extra-virgin olive oil" arrived as the single word "extra-virgin" and
  /// missed the qualifier list that "extra virgin" walks straight through.
  /// The result was a null density for a spelling half of every recipe uses,
  /// and a null density is an ingredient that cannot cross between cups and
  /// grams at all.
  static String normalise(String raw) =>
      normaliseKey(raw.replaceAll(RegExp(r'[-–—]+'), ' '));

  /// Density for [ingredient] in g/ml, or null when unknown.
  ///
  /// Strips the words that say how much or how prepared — amounts, units, and
  /// the qualifiers in [_qualifiers] — and then requires what is left to name
  /// a food this table actually knows. "Freshly grated parmesan" and
  /// "2 cups warm water" both resolve; "cauliflower rice" and "almond flour"
  /// deliberately do not.
  ///
  /// The rule used to be a plain substring match, which silently handed
  /// cauliflower rice white rice's 0.85 g/ml — roughly five times its real
  /// weight, buried in a macro total nobody would think to question. English
  /// puts the head noun last, so "grated parmesan" is parmesan while
  /// "cauliflower rice" is not rice, and nothing short of a vocabulary can
  /// tell those apart. Anything this cannot name is left unknown and flagged
  /// upstream: a wrong density is worse than a missing one.
  static double? lookup(String ingredient) {
    final String key = normalise(ingredient);
    if (key.isEmpty) return null;

    for (final String candidate in <String>{key, _stripQualifiers(key)}) {
      if (candidate.isEmpty) continue;
      final double? exact = _byNormalisedName[candidate];
      if (exact != null) return exact;

      final String? aliased = _byNormalisedAlias[candidate];
      if (aliased != null) return _byNormalisedName[aliased];
    }
    return null;
  }

  /// The tables above, keyed the way a query arrives.
  ///
  /// Built rather than hand-maintained: the table writes "all-purpose flour"
  /// and a recipe may write either spelling, so both sides have to go through
  /// [normalise] or the two drift the moment somebody adds an entry with a
  /// hyphen in it — which is exactly how "extra-virgin olive oil" came to have
  /// no density.
  static final Map<String, double> _byNormalisedName = <String, double>{
    for (final MapEntry<String, double> entry in gramsPerMillilitre.entries)
      normalise(entry.key): entry.value,
  };

  static final Map<String, String> _byNormalisedAlias = <String, String>{
    for (final MapEntry<String, String> entry in _aliases.entries)
      normalise(entry.key): normalise(entry.value),
  };

  /// Drops amounts, units, and preparation words, leaving what the thing is.
  static String _stripQualifiers(String key) => key
      .split(' ')
      .where(
        (String word) =>
            word.isNotEmpty &&
            !_qualifiers.contains(word) &&
            double.tryParse(word) == null &&
            Units.parse(word) == null,
      )
      .join(' ');

  /// Words that describe how an ingredient was prepared or graded, rather
  /// than what it is.
  ///
  /// This list is what makes the match safe. "Freshly grated parmesan" is
  /// parmesan — every extra word only says what was done to it. "Cauliflower
  /// rice" is not rice and "almond flour" is not flour, because those words
  /// name a different substance. So this is the vocabulary of words that may
  /// be ignored, and any word outside it makes the phrase a different food.
  static const Set<String> _qualifiers = <String>{
    'boiling',
    'chilled',
    'chopped',
    'coarsely',
    'cold',
    'cooked',
    'cracked',
    'crushed',
    'cubed',
    'diced',
    'dried',
    'extra',
    'fine',
    'finely',
    'firm',
    'flaked',
    'freeze-dried',
    'fresh',
    'freshly',
    'frozen',
    'grated',
    'ground',
    'hot',
    'large',
    'lukewarm',
    'medium',
    'melted',
    'minced',
    'organic',
    'plain',
    'pure',
    'raw',
    'roughly',
    'roasted',
    'salted',
    'shredded',
    'sifted',
    'sliced',
    'small',
    'softened',
    'divided',
    'drained',
    'rinsed',
    'thawed',
    'toasted',
    'unsalted',
    'virgin',
    'warm',
    'whole',
  };

  /// True when a real density is known for [ingredient].
  static bool knows(String ingredient) => lookup(ingredient) != null;
}
