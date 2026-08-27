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
