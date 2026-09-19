/// A deterministic, non-destructive formatter that turns a stored recipe
/// step's instruction text into left-aligned reading blocks (loop
/// cook-directions-v1, P-HEARTH-COOK-002 R4).
///
/// This is presentation-only: it never touches storage, never rewrites,
/// summarizes or classifies the text, and never invents labels or extra
/// steps. It only decides where a long wall of prose may be broken into
/// separate paragraphs for readability, preferring a longer block whenever
/// a boundary is uncertain.
///
/// Two kinds of boundary are recognised:
///  * authored line breaks (the recipe's own newlines/list breaks), which
///    are always kept as separate blocks; and
///  * conservative sentence-ending punctuation within a single authored
///    line, guarded against unit abbreviations, decimals, ratios,
///    initials, ellipses and quoted punctuation.
///
/// The algorithm never splits on commas, never rewrites text and never
/// drops a non-whitespace character: joining the returned blocks and then
/// stripping all whitespace reproduces the same non-whitespace characters
/// in the same order as the input.
library;

/// Units, connectors and other short words that end in a period without
/// ending a sentence. Deliberately small and literal — this is not a
/// linguistic parser, and treating ordinary words as abbreviations would
/// silently glue unrelated sentences together.
const Set<String> _abbreviations = <String>{
  'tsp',
  'tbsp',
  'oz',
  'lb',
  'lbs',
  'min',
  'mins',
  'hr',
  'hrs',
  'approx',
  'etc',
  'vs',
  'no',
  'st',
  'dr',
  'mr',
  'mrs',
  'ms',
  'jr',
  'sr',
  'ft',
  'in',
  'cm',
  'mm',
  'ml',
  'kg',
  'gal',
  'pt',
  'qt',
};

final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
final RegExp _sentenceEnders = RegExp(r'[.!?]+');
final RegExp _wordChar = RegExp(r'[A-Za-z0-9]');
final RegExp _digit = RegExp(r'[0-9]');
final RegExp _initial = RegExp(r'^[A-Za-z]$');
final RegExp _numberedPrefix = RegExp(r'(?:[-*•]\s+)?[0-9]+\.');
final RegExp _boundaryStart = RegExp(r'[A-Z0-9"\u201c\u2018\u2019]');
final RegExp _whitespace = RegExp(r'\s');
const String _closingMarks = '"\'\u2019\u201d';

/// Splits [text] into ordered, trimmed reading blocks.
///
/// Authored newlines/list breaks are always kept as block boundaries.
/// Within an authored line, a `.`/`!`/`?` is only treated as a sentence
/// boundary when it is not immediately preceded by a known unit
/// abbreviation, a single initial, or a decimal number, and (unless it is
/// the end of the line) is followed by whitespace and then a capital
/// letter, digit or opening quote. A run of two or more dots (an ellipsis)
/// never counts as a boundary on its own.
///
/// Returns an empty list for whitespace-only input. Never splits on
/// commas and never removes or reorders any non-whitespace character.
List<String> cookInstructionBlocks(String text) {
  if (text.trim().isEmpty) return const <String>[];

  final List<String> blocks = <String>[];
  for (final String rawLine in text.split(_lineBreak)) {
    final String line = rawLine.trim();
    if (line.isEmpty) continue;
    blocks.addAll(_splitSentences(line));
  }
  return blocks;
}

/// Splits a single authored line into sentence-level blocks. A single
/// linear pass over the line's `.`/`!`/`?` matches — no whole-prefix
/// rescans, and each abbreviation/initial look-back is bounded to a short
/// fixed window (abbreviations are always short).
List<String> _splitSentences(String line) {
  final List<String> result = <String>[];
  int start = 0;
  // A leading “1.” is a list marker; a number ending a sentence is not.
  int? prefixEnd = _numberedPrefix.matchAsPrefix(line)?.end;

  for (final RegExpMatch match in _sentenceEnders.allMatches(line)) {
    if (match.start < start) continue; // inside an already-consumed block
    final String punct = match.group(0)!;

    // An ellipsis (two or more dots) never ends a sentence by itself — the
    // thought continues past it.
    if (punct.length >= 2 && punct.split('').every((String c) => c == '.')) {
      continue;
    }

    int end = match.end;
    // A closing quote/apostrophe belongs with the sentence it closes.
    while (end < line.length && _closingMarks.contains(line[end])) {
      end++;
    }

    if (punct == '.') {
      if (match.end == prefixEnd) continue;
      // A decimal number: a digit immediately on either side of the dot.
      final bool digitBefore =
          match.start > 0 && _digit.hasMatch(line[match.start - 1]);
      final bool digitAfter =
          match.end < line.length && _digit.hasMatch(line[match.end]);
      if (digitBefore && digitAfter) continue;

      // A known unit/word abbreviation, or a single initial, right before
      // the dot (this also protects each dot of "U.S.", "e.g.", "i.e.").
      final String word = _wordBefore(line, match.start);
      if (word.isNotEmpty &&
          (_abbreviations.contains(word.toLowerCase()) ||
              _initial.hasMatch(word))) {
        continue;
      }
    }

    if (end == line.length) {
      // The end of the authored line is always a valid final boundary.
      result.add(line.substring(start, end).trim());
      start = end;
      continue;
    }

    int j = end;
    while (j < line.length && _whitespace.hasMatch(line[j])) {
      j++;
    }
    final bool hasSpaceAfter = j > end;
    if (!hasSpaceAfter) continue; // punctuation glued to the next character
    if (j >= line.length) continue; // trailing whitespace only
    if (!_boundaryStart.hasMatch(line[j])) continue; // lowercase continuation

    result.add(line.substring(start, end).trim());
    start = j;
    // Recheck at the next block too: inline “1. Chop. 2. Fry.” stays tidy.
    prefixEnd = _numberedPrefix.matchAsPrefix(line, start)?.end;
  }

  final String rest = line.substring(start).trim();
  if (rest.isNotEmpty) result.add(rest);
  return result;
}

/// The run of letters/digits immediately before [end], bounded to a short
/// look-back so this stays cheap and does not rescan the whole line —
/// abbreviations and initials are always short.
String _wordBefore(String line, int end) {
  int i = end;
  const int maxLookBack = 16;
  while (i > 0 && end - i < maxLookBack && _wordChar.hasMatch(line[i - 1])) {
    i--;
  }
  return line.substring(i, end);
}
