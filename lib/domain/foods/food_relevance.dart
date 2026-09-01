import 'package:meta/meta.dart';

import '../text/text_normaliser.dart';

/// How close a food's name is to what somebody typed (spec §5.5).
///
/// Ranking external search results by name similarity alone put snack food
/// above vegetables: a search for "red bell pepper" answered with red bell
/// pepper veggie chips, red bell pepper hummus, and creamy red bell pepper
/// sauce, with the pepper itself eight rows down. Every one of those names
/// really does contain every word that was typed — more of them, in fact, than
/// USDA's own "Peppers, red, cooked" does — so similarity was working exactly
/// as written and still answering the wrong question.
///
/// The question a person is actually asking is *what kind of thing is this*.
/// "Red bell pepper veggie chips" is chips. "Creamy red bell pepper sauce" is
/// sauce. English puts the head noun last, which is the same reading the
/// cook-along's step matching already relies on to tell "soy sauce" from the
/// sauce in the pan, so the head noun decides here too: results whose kind is
/// the kind that was asked for come first, and closeness of wording only
/// orders them once that is settled.
@immutable
class FoodRelevance {
  const FoodRelevance._({required this.sameKind, required this.score});

  /// How [name] answers a query already reduced to [terms] by [termsOf].
  factory FoodRelevance.of(String name, List<String> terms) {
    if (terms.isEmpty) {
      return const FoodRelevance._(sameKind: false, score: 0);
    }

    final List<String> whole = _significant(name);
    final List<String> kind = kindWords(name);

    final int answered = terms
        .where((String term) => whole.any((String word) => _same(word, term)))
        .length;
    final int surplus = kind
        .where((String word) => !terms.any((String term) => _same(word, term)))
        .length;

    final double coverage = answered * 100 / terms.length;
    final double spent = kind.isEmpty ? 0 : surplus / kind.length;

    final String? wanted = headOf(terms);
    final String? offered = kind.isEmpty ? null : headOf(kind);

    return FoodRelevance._(
      sameKind: wanted != null && offered != null && _same(wanted, offered),
      score: (coverage - _surplusWeight * spent).round(),
    );
  }

  /// Whether this names the same kind of thing the query asked for.
  ///
  /// The primary ordering, ahead of wording: a name that says chips is not a
  /// near miss for a pepper, however many of the query's words it repeats.
  final bool sameKind;

  /// 0..100-ish. How much of the query the name answers, less what the name
  /// spends on saying something else.
  final int score;

  /// How much a name is docked for the share of its kind spent on words
  /// nobody asked for.
  ///
  /// Larger than any single word is worth, deliberately: "chicken broth
  /// concentrate" adds one word to a two-word request and stays a broth,
  /// while "rice with chicken broth" is rice. Both contain the query, and the
  /// difference between them is entirely how much of the name is about
  /// something else.
  static const double _surplusWeight = 60;

  /// The words of a query worth matching on.
  ///
  /// Two letters and under carry no meaning a match is obliged to honour, and
  /// requiring them would make "cream of chicken" fail against "chicken
  /// cream".
  static List<String> termsOf(String query) => _significant(query);

  /// The head noun of [words] — the last one that is a word rather than a
  /// number.
  ///
  /// Sizes and percentages trail food names constantly ("ground beef 96/4",
  /// "milk 2"), and the head of that phrase is still the beef and the milk.
  static String? headOf(List<String> words) {
    for (int i = words.length - 1; i >= 0; i--) {
      if (words[i].contains(RegExp('[a-z]'))) return words[i];
    }
    return null;
  }

  /// The part of [name] that says what the thing *is*.
  ///
  /// Everything up to the first comma, dash, or bracket: USDA writes
  /// "Peppers, sweet, red, raw" and "FIORI, RED BELL PEPPER", where the first
  /// clause is the food and the rest is qualification or a repeat of the
  /// label. Then cut again at a preposition, because "rice with chicken
  /// broth" is rice — the words after "with" describe what was added to it.
  static List<String> kindWords(String name) {
    final String clause = name.split(RegExp(r'[,(\[:;–—]')).first;
    final List<String> words = _significant(clause);

    final int joiner = words.indexWhere(_joiners.contains);
    return joiner > 0 ? words.sublist(0, joiner) : words;
  }

  /// Words that mark what follows as an addition rather than the thing itself.
  static const Set<String> _joiners = <String>{
    'containing',
    'covered',
    'dipped',
    'filled',
    'flavored',
    'flavoured',
    'topped',
    'with',
    'without',
  };

  static List<String> _significant(String raw) => <String>[
    for (final String word in normaliseKey(raw).split(' '))
      if (word.length >= 3) word,
  ];

  /// Whether two words are the same word, give or take a plural.
  ///
  /// "Peppers" has to answer a search for "pepper", or USDA's entire produce
  /// catalogue — which is written in the plural — is invisible to anyone
  /// typing an ingredient in the singular.
  static bool _same(String a, String b) =>
      a == b || _stems(a).intersection(_stems(b)).isNotEmpty;

  static Set<String> _stems(String word) => <String>{
    word,
    if (word.length > 4 && word.endsWith('ies'))
      '${word.substring(0, word.length - 3)}y',
    if (word.length > 4 && word.endsWith('es'))
      word.substring(0, word.length - 2),
    if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss'))
      word.substring(0, word.length - 1),
  };
}
