/// Shared text normalisation for matching ingredient strings.
///
/// One implementation, used by the density lookup, ingredient consolidation,
/// and (later) the remembered `ingredient_match` table — so "EVOO", "evoo",
/// and "evoo." are the same key everywhere.
library;

/// Lowercases, strips punctuation, and collapses whitespace.
String normaliseKey(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
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

  final String normalisedHaystack = normaliseKey(haystack);
  final int hits = words.where(normalisedHaystack.contains).length;
  return hits / words.length;
}
