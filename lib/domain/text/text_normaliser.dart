/// Shared text normalisation for matching ingredient strings.
///
/// One implementation, used by the density lookup, ingredient consolidation,
/// and (later) the remembered `ingredient_match` table — so "EVOO", "evoo",
/// and "evoo." are the same key everywhere.
library;

/// Lowercases, strips punctuation, and collapses whitespace.
///
/// Hyphens and slashes become **spaces**, not nothing, and not themselves.
/// Recipes spell the same ingredient both ways — "sun-dried tomatoes" and
/// "sun dried tomatoes", "extra-virgin" and "extra virgin" — and while the
/// hyphen survived, those were different keys everywhere this function is
/// used: the shopping list showed two lines for one ingredient, a duplicate
/// food was never flagged, a remembered match was asked again, and word
/// coverage scored 0.5 in one direction and 1.0 in the other depending on
/// which side happened to carry the hyphen.
///
/// A slash for the same reason, and it broke this file's own worked example:
/// "96/4 Ground Beef" used to normalise to "964 ground beef", fusing the
/// digits into a number that means nothing.
String normaliseKey(String raw) => raw
    .toLowerCase()
    // Separators first, so "sun-dried" becomes two words rather than one.
    .replaceAll(RegExp(r'[-/]'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Words shorter than this carry no meaning a match is obliged to honour —
/// articles and prepositions like "of" or "la" — so they are not required to
/// appear and do not count toward coverage.
const int _minimumMatchWordLength = 3;

/// How much of [query] is actually present in [haystack], as a 0..1 fraction
/// of [query]'s significant words.
///
/// Word-level, not substring: "lean ground beef" against a food named
/// "96/4 Ground Beef" shares every meaningful word but is not a substring of
/// it either way round, and a plain `contains` check — in either direction —
/// misses it entirely. Checking word-by-word is what a shopper actually means
/// by "does this match," and it is the same idea already scoring matches
/// against Open Food Facts and USDA results; this pulls just that piece out
/// so the household's own library is judged the same way.
///
/// Returns 0 when [query] has no significant words (nothing to require) or
/// when none of them appear.
double wordCoverage(String query, String haystack) {
  final List<String> words = <String>[
    for (final String word in normaliseKey(query).split(' '))
      if (word.length >= _minimumMatchWordLength) word,
  ];
  if (words.isEmpty) return 0;

  final List<String> haystackWords = <String>[
    for (final String word in normaliseKey(haystack).split(' '))
      if (word.isNotEmpty) word,
  ];

  final int hits = words
      .where(
        (String word) =>
            haystackWords.any((String other) => _sameWord(word, other)),
      )
      .length;
  return hits / words.length;
}

/// Whether two words are the same word, give or take a plural.
///
/// Substring matching used to do this job and could not: a recipe line saying
/// "apples" against a food called "Honeycrisp Apple" shares no substring in
/// either direction, so the food picker filtered out the very food that line
/// was already matched to and reported "None of your foods match".
///
/// Deliberately only plurals, and only when there is a real word left over.
/// Stemming that is too eager is worse than none — it attaches the wrong food,
/// which is the one failure a review screen cannot catch, because it looks
/// right. "Grass" is not "gras" and "beans" is not "beef".
/// [wanted] is a word from the query; [found] is one from the name.
///
/// Containment is one-directional, as it was before this gained stems: a
/// query word may be part of a longer name word — "oat" finds "Oatly" — but a
/// name word being part of the query must not count, or "grass" would find
/// "gras".
bool _sameWord(String wanted, String found) =>
    wanted == found ||
    found.contains(wanted) ||
    _stems(wanted).intersection(_stems(found)).isNotEmpty;

Set<String> _stems(String word) => <String>{
  word,
  if (word.length > 4 && word.endsWith('ies'))
    '${word.substring(0, word.length - 3)}y',
  if (word.length > 4 && word.endsWith('es'))
    word.substring(0, word.length - 2),
  // Four letters and an s: "eggs" has to reach "egg". Words ending "ss" are
  // excluded, so "bass" is not read as a plural of "bas".
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss'))
    word.substring(0, word.length - 1),
};
