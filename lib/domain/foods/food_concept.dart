import 'package:meta/meta.dart';

/// What a food name actually says: a thing, and which kind of that thing.
///
/// "96/4 ground beef", "96% ground beef" and "96% lean ground beef" name one
/// product three ways; "88% ground beef" names a different one. "2% milk",
/// "whole milk" and "non-fat milk" are three different milks, while a recipe
/// asking for plain "milk" has not said which. Every one of those judgements
/// is the same rule: **the thing has to agree, and the kind must not
/// disagree.**
///
/// Deliberately not built on [normaliseKey]: that strips punctuation, so
/// "96/4" arrives as "964" and "96%" as "96" — it destroys the exact
/// distinction this exists to make. The raw string is tokenised here instead,
/// keeping the digits and the marks that carry the meaning.
///
/// The vocabularies below are finite and always will be. That is why an
/// unrecognised word is kept as part of the *thing* rather than guessed at as
/// a kind: an unknown qualifier then makes a name narrower and matches less,
/// which fails closed. The alternative — ignoring what it does not recognise —
/// would silently match "smoked paprika" to paprika.
@immutable
class FoodConcept {
  const FoodConcept({required this.base, required this.variants});

  /// The thing itself: {"ground", "beef"}, {"milk"}.
  final Set<String> base;

  /// Which kind of it, canonicalised: {"96%"}, {"nonfat"}. Empty when the
  /// name does not say — which is a real answer, not a missing one.
  final Set<String> variants;

  bool get isEmpty => base.isEmpty;

  /// Whether this food can answer [line].
  ///
  /// Asymmetric on purpose, and both halves earn their keep:
  ///
  ///  * every word of the line's thing must be in this food's thing, so
  ///    "ground beef" is answered by "Maverick Ranch 96/4 Ground Beef" — the
  ///    brand is extra, not a contradiction — while "almond milk" is not
  ///    answered by "milk", because "almond" is a word the food never says;
  ///  * every kind the line names must be one this food is. "88%" is not
  ///    answered by a 96% food. "whole" is not answered by a plain "Milk":
  ///    the line asked for something specific and this food never claimed it.
  ///
  /// A line naming no kind passes the second test with nothing to check,
  /// which is what lets bare "milk" be answered by all three milks at once —
  /// the ambiguity a caller turns into a short menu rather than a guess.
  bool covers(FoodConcept line) {
    if (isEmpty || line.isEmpty) return false;
    return line.base.every(base.contains) &&
        line.variants.every(variants.contains);
  }

  /// How closely this answers [line] — fewer words of its own that the line
  /// did not ask for is a tighter fit. Only meaningful between foods that
  /// both [covers] it.
  int distanceFrom(FoodConcept line) =>
      (base.length - line.base.length) +
      (variants.length - line.variants.length);

  static FoodConcept of(String text) {
    final Set<String> base = <String>{};
    final Set<String> variants = <String>{};

    for (final String token in _tokenise(text)) {
      // Checked against the singular too, so the list below stays singular
      // and a plural nobody thought to add still drops out.
      if (_noise.contains(token) || _noise.contains(_singular(token))) continue;

      final String? variant = _asVariant(token);
      if (variant != null) {
        variants.add(variant);
        continue;
      }

      // An amount is not a food. Numbers and cooking fractions reach here
      // only when [_asVariant] has already ruled them out as grades, so
      // "1/4" and "2" drop out while "96/4" and "2%" never arrive.
      if (RegExp(r'^[\d/.]+$').hasMatch(token)) continue;

      // Two letters or fewer carry nothing a match is obliged to honour —
      // the same threshold `wordCoverage` already uses for the same reason.
      final String word = _singular(token);
      if (word.length > 2) base.add(word);
    }

    return FoodConcept(base: base, variants: variants);
  }

  /// Splits [text] into comparable tokens, keeping what punctuation means.
  ///
  /// Two-word kinds are joined first: "non fat", "fat free", "extra virgin"
  /// and "steel cut" each say one thing, and splitting them on the space
  /// would leave "fat" and "free" as two words of the *thing* — which is how
  /// non-fat milk would stop being milk.
  static List<String> _tokenise(String text) {
    String working = text.toLowerCase();
    for (final MapEntry<String, String> phrase in _phrases.entries) {
      working = working.replaceAll(phrase.key, phrase.value);
    }

    // Hyphens separate, they do not vanish. Deleting one made "low-sodium"
    // a single word "lowsodium" while "low sodium" stayed two, so a saved
    // "Low Sodium Soy Sauce" could never meet a recipe line that spelled it
    // with the hyphen. The phrase pass above has already collapsed the
    // hyphenated kinds Hearth knows, so "non-fat" is "nonfat" before it gets
    // here and only the ordinary hyphens are left to split.
    return <String>[
      for (final String raw in working.split(RegExp(r'[\s,()\-–—]+')))
        if (_clean(raw) case final String token when token.isNotEmpty) token,
    ];
  }

  /// Strips what a token does not need, keeping `%` and `/`.
  static String _clean(String raw) =>
      raw.replaceAll(RegExp(r'[^a-z0-9%/]'), '');

  /// A crude singular, so "onions" and "onion" are the same food.
  ///
  /// Both sides of a comparison go through this, so being consistently wrong
  /// costs nothing — "tomatoes" and "tomatoes" agree whatever they become.
  /// Being wrong in *different directions* would, which is the only thing
  /// worth guarding: words ending in a doubled or Latin s ("hummus",
  /// "molasses", "couscous") keep it rather than losing a letter each time.
  static String _singular(String word) {
    if (word.length < 4) return word;
    if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
    if (word.endsWith('ss') || word.endsWith('us') || word.endsWith('is')) {
      return word;
    }
    if (word.endsWith('es')) {
      final String stem = word.substring(0, word.length - 2);
      // "tomatoes" and "dishes" lose both letters; "grapes" loses one.
      if (RegExp(r'(o|s|x|z|ch|sh)$').hasMatch(stem)) return stem;
      return word.substring(0, word.length - 1);
    }
    if (word.endsWith('s')) return word.substring(0, word.length - 1);
    return word;
  }

  /// The canonical kind this token names, or null when it names none.
  static String? _asVariant(String token) {
    final String? named = _namedVariants[token];
    if (named != null) return named;

    if (RegExp(r'^\d+(\.\d+)?%$').hasMatch(token)) return token;

    // A lean/fat ratio is a fat percentage written the butcher's way. Guarded
    // on the two halves summing to about a hundred, so "1/4" and "2/3" — the
    // fractions an ingredient line is full of — are never read as one.
    final RegExpMatch? ratio = RegExp(r'^(\d+)/(\d+)$').firstMatch(token);
    if (ratio != null) {
      final int lean = int.parse(ratio.group(1)!);
      final int fat = int.parse(ratio.group(2)!);
      if ((lean + fat - 100).abs() <= 1) return '$lean%';
    }

    return null;
  }

  /// Two-word kinds, joined before tokenising.
  static const Map<String, String> _phrases = <String, String>{
    'non-fat': 'nonfat',
    'non fat': 'nonfat',
    'fat-free': 'nonfat',
    'fat free': 'nonfat',
    'low-fat': 'lowfat',
    'low fat': 'lowfat',
    'reduced-fat': 'reducedfat',
    'reduced fat': 'reducedfat',
    'extra-virgin': 'extravirgin',
    'extra virgin': 'extravirgin',
    'steel-cut': 'steelcut',
    'steel cut': 'steelcut',
    'whole-wheat': 'wholewheat',
    'whole wheat': 'wholewheat',
    'all-purpose': 'allpurpose',
    'all purpose': 'allpurpose',
  };

  /// Words that name which kind of a thing something is.
  ///
  /// Values are the canonical form, so equivalent spellings collide: "skim"
  /// and "non-fat" are the same milk, and a recipe written either way finds a
  /// default saved as the other.
  static const Map<String, String> _namedVariants = <String, String>{
    'whole': 'whole',
    'skim': 'nonfat',
    'skimmed': 'nonfat',
    'nonfat': 'nonfat',
    'lowfat': 'lowfat',
    'reducedfat': 'reducedfat',
    'unsweetened': 'unsweetened',
    'sweetened': 'sweetened',
    'salted': 'salted',
    'unsalted': 'unsalted',
    'heavy': 'heavy',
    'light': 'light',
    'dark': 'dark',
    'white': 'white',
    'brown': 'brown',
    'extravirgin': 'extravirgin',
    'virgin': 'extravirgin',
    'instant': 'instant',
    'rolled': 'rolled',
    'steelcut': 'steelcut',
    'wholewheat': 'wholewheat',
    'allpurpose': 'allpurpose',
    'smoked': 'smoked',
    'roasted': 'roasted',
    'creamy': 'creamy',
    'crunchy': 'crunchy',
    'plain': 'plain',
    'greek': 'greek',
  };

  /// Words that describe without distinguishing.
  ///
  /// This list is what makes "96% **lean** ground beef" the same product as
  /// "96/4 ground beef" — and what lets a default called "Frozen chopped
  /// onions" answer a recipe that just says "onion". Prep and packaging change
  /// what is in your hand, not what the food is.
  ///
  /// "ground" is deliberately absent: it is half of what "ground beef" *is*.
  static const Set<String> _noise = <String>{
    'lean',
    'extra',
    'fresh',
    'frozen',
    'organic',
    'raw',
    'cooked',
    'chopped',
    'diced',
    'minced',
    'sliced',
    'shredded',
    'grated',
    'crushed',
    'large',
    'small',
    'medium',
    'boneless',
    'skinless',
    'ripe',
    'the',
    'and',
    // Units and containers. A caller normally passes an already-parsed
    // ingredient name with these stripped, but the sweep reads stored lines
    // and a food's own name can carry one, and "1 cup milk" must not end up
    // as a different food from "milk".
    'cup',
    'tbsp',
    'tablespoon',
    'tsp',
    'teaspoon',
    'ounce',
    'pound',
    // Too short for [_singular] to touch, so it is listed as written.
    'lbs',
    'gram',
    'kilogram',
    'millilitre',
    'litre',
    'liter',
    'quart',
    'pint',
    'gallon',
    'pinch',
    'dash',
    'handful',
    'clove',
    'slice',
    'piece',
    'can',
    'jar',
    'bag',
    'box',
    'package',
    'packet',
    'container',
  };

  @override
  bool operator ==(Object other) =>
      other is FoodConcept &&
      other.base.length == base.length &&
      other.base.containsAll(base) &&
      other.variants.length == variants.length &&
      other.variants.containsAll(variants);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(base),
    Object.hashAllUnordered(variants),
  );

  @override
  String toString() =>
      'FoodConcept(${base.join(' ')}${variants.isEmpty ? '' : ' [${variants.join(' ')}]'})';
}
