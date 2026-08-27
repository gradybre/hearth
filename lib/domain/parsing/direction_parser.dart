import 'package:meta/meta.dart';

/// How the incoming directions text was already structured, if at all.
enum DirectionFormat {
  /// "1. Season the ribs" / "1) Season" / "Step 1: Season".
  numbered,

  /// "- Season the ribs" / "• Season the ribs".
  bulleted,

  /// One step per line, with no marker.
  lineBreaks,

  /// A single prose blob that had to be split into sentences.
  prose,
}

/// One direction step.
@immutable
class ParsedStep {
  const ParsedStep({required this.number, required this.text});

  /// 1-based, matching `recipe_step.step_number` (spec §4).
  final int number;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ParsedStep && other.number == number && other.text == text;

  @override
  int get hashCode => Object.hash(number, text);

  @override
  String toString() => '$number. $text';
}

/// The result of parsing a directions blob.
@immutable
class ParsedDirections {
  const ParsedDirections({required this.steps, required this.format});

  final List<ParsedStep> steps;

  /// What the input already looked like. Useful on the import review screen:
  /// [DirectionFormat.prose] means the split was *inferred* and deserves a
  /// closer look, while the others were merely transcribed.
  final DirectionFormat format;

  /// True when the steps were inferred rather than read off explicit markers.
  bool get wasInferred => format == DirectionFormat.prose;

  bool get isEmpty => steps.isEmpty;
}

/// Turns a directions blob into numbered steps (spec §5.2, "two structured
/// areas: Ingredients and Directions").
///
/// Structured steps are what cook-along walks through one card at a time, so
/// getting them out of free text is what makes a pasted or AI-imported recipe
/// cookable rather than just readable.
///
/// The parser prefers the structure it is given: explicit numbers, bullets, or
/// line breaks are transcribed rather than second-guessed. Only a single prose
/// blob is split, and that split is reported via [ParsedDirections.format] so
/// the review screen can flag it.
abstract final class DirectionParser {
  /// Words ending in a period that do not end a sentence.
  static const Set<String> _abbreviations = <String>{
    'approx',
    'tbsp',
    'tsp',
    'oz',
    'lb',
    'lbs',
    'qt',
    'pt',
    'gal',
    'ml',
    'temp',
    'deg',
    'min',
    'mins',
    'hr',
    'hrs',
    'sec',
    'secs',
    'pkg',
    'st',
    'no',
    'vs',
    'etc',
    'e.g',
    'i.e',
  };

  /// Imperative verbs a cooking step tends to open with. Used only to decide
  /// whether an "and" joins two genuine instructions.
  static const Set<String> _stepVerbs = <String>{
    'add',
    'arrange',
    'bake',
    'beat',
    'blend',
    'boil',
    'break',
    'bring',
    'broil',
    'brown',
    'brush',
    'chill',
    'chop',
    'combine',
    'cook',
    'cool',
    'cover',
    'cut',
    'deglaze',
    'dice',
    'discard',
    'divide',
    'drain',
    'drizzle',
    'dust',
    'fill',
    'flip',
    'fold',
    'fry',
    'garnish',
    'grate',
    'grill',
    'heat',
    'knead',
    'layer',
    'let',
    'lower',
    'marinate',
    'mash',
    'melt',
    'mince',
    'mix',
    'peel',
    'place',
    'pour',
    'preheat',
    'press',
    'puree',
    'reduce',
    'refrigerate',
    'remove',
    'repeat',
    'reserve',
    'rest',
    'return',
    'roast',
    'roll',
    'saute',
    'sauté',
    'scrape',
    'sear',
    'season',
    'serve',
    'set',
    'simmer',
    'slice',
    'spread',
    'sprinkle',
    'stir',
    'strain',
    'taste',
    'toss',
    'transfer',
    'trim',
    'turn',
    'whisk',
    'whip',
    'wipe',
  };

  static final RegExp _numberedMarker = RegExp(
    r'^\s*(?:step\s*)?(\d{1,2})\s*[.):\-]\s+',
    caseSensitive: false,
  );
  static final RegExp _bulletMarker = RegExp(r'^\s*[-*•·–]\s+');

  /// Parses [text] into numbered steps.
  ///
  /// [splitConjunctions] controls whether a sentence joining two instructions
  /// with "and" becomes two steps — "Season the ribs and sear them until
  /// browned" turning into a step each. It only fires when both halves open
  /// with a recognised cooking verb, so "salt and pepper the ribs" and "add
  /// the carrots, celery, and onion" stay whole.
  static ParsedDirections parse(String text, {bool splitConjunctions = true}) {
    final List<String> lines = text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ParsedDirections(
        steps: <ParsedStep>[],
        format: DirectionFormat.prose,
      );
    }

    final DirectionFormat format = _detectFormat(lines);
    final List<String> raw = switch (format) {
      DirectionFormat.numbered => <String>[
        for (final String l in lines) l.replaceFirst(_numberedMarker, ''),
      ],
      DirectionFormat.bulleted => <String>[
        for (final String l in lines) l.replaceFirst(_bulletMarker, ''),
      ],
      DirectionFormat.lineBreaks => lines,
      DirectionFormat.prose => _splitSentences(lines.join(' ')),
    };

    final List<String> pieces = <String>[
      for (final String piece in raw)
        if (format == DirectionFormat.prose && splitConjunctions)
          ..._splitOnConjunction(piece)
        else
          piece,
    ];

    final List<ParsedStep> steps = <ParsedStep>[];
    for (final String piece in pieces) {
      final String cleaned = _tidy(piece);
      if (cleaned.isEmpty) continue;
      steps.add(ParsedStep(number: steps.length + 1, text: cleaned));
    }

    return ParsedDirections(steps: steps, format: format);
  }

  static DirectionFormat _detectFormat(List<String> lines) {
    if (lines.length > 1) {
      // Half the lines carrying a marker is enough: real recipes drop the
      // number on a continuation line often enough that demanding every line
      // match would misread them as unstructured prose.
      final int threshold = (lines.length / 2).ceil();

      final int numbered = lines
          .where((String l) => _numberedMarker.hasMatch(l))
          .length;
      if (numbered >= threshold) {
        return DirectionFormat.numbered;
      }

      final int bulleted = lines
          .where((String l) => _bulletMarker.hasMatch(l))
          .length;
      if (bulleted >= threshold) {
        return DirectionFormat.bulleted;
      }

      return DirectionFormat.lineBreaks;
    }
    // A single line that is itself numbered is still explicit structure.
    if (_numberedMarker.hasMatch(lines.first)) return DirectionFormat.numbered;
    if (_bulletMarker.hasMatch(lines.first)) return DirectionFormat.bulleted;
    return DirectionFormat.prose;
  }

  /// Splits prose on sentence boundaries, stepping around decimals and the
  /// abbreviations a recipe is full of ("approx. 5 min.", "1.5 cups").
  static List<String> _splitSentences(String prose) {
    final List<String> sentences = <String>[];
    final StringBuffer current = StringBuffer();

    final List<String> tokens = prose.split(' ');
    for (int i = 0; i < tokens.length; i++) {
      final String token = tokens[i];
      if (current.isNotEmpty) current.write(' ');
      current.write(token);

      if (!RegExp(r'[.!?]["\x27)]?$').hasMatch(token)) continue;

      final String bare = token
          .replaceAll(RegExp(r'[.!?"\x27)]+$'), '')
          .toLowerCase();
      // "1.5" or "350." followed by more numbers is not a sentence end.
      if (RegExp(r'^\d+$').hasMatch(bare) && i + 1 < tokens.length) {
        final String next = tokens[i + 1];
        if (RegExp(r'^\d').hasMatch(next)) continue;
      }
      if (_abbreviations.contains(bare)) {
        // A unit abbreviation is ambiguous: "simmer for 20 min." ends a
        // sentence, while "approx. 20 min" does not. Treat it as an ending
        // only when what follows opens like a new instruction — that keeps
        // "20 min. Serve hot" apart while leaving "2 tbsp. Dijon mustard"
        // whole.
        final String? next = i + 1 < tokens.length ? tokens[i + 1] : null;
        final bool nextIsInstruction = next != null && _opensWithStepVerb(next);
        if (!nextIsInstruction) continue;
      }
      // A single capital letter is an initial, not a sentence end.
      if (RegExp(r'^[A-Z]$').hasMatch(bare)) continue;

      sentences.add(current.toString());
      current.clear();
    }

    if (current.isNotEmpty) sentences.add(current.toString());
    return sentences;
  }

  /// Splits "Season the ribs and sear them until browned" into two steps.
  ///
  /// Both sides must read as a step worth its own line: each has to open with
  /// a cooking verb, the head needs at least three words and the tail at least
  /// two. That keeps "Season the ribs generously and sear them until browned"
  /// as two steps while leaving "Cover and cook for 3 hr" and "Stir and serve"
  /// whole — a bare "Cover" is not an instruction anyone needs numbered.
  /// Fewest words a clause needs before it earns its own numbered step.
  static const int _minHeadWords = 3;
  static const int _minTailWords = 2;

  static List<String> _splitOnConjunction(String sentence) {
    final String trimmed = sentence.trim();
    if (!_opensWithStepVerb(trimmed)) return <String>[trimmed];

    final List<String> parts = <String>[];
    String remaining = trimmed;

    while (true) {
      final Match? match = RegExp(
        r'\s+and\s+',
        caseSensitive: false,
      ).firstMatch(remaining);
      if (match == null) break;

      final String head = remaining.substring(0, match.start).trim();
      final String tail = remaining.substring(match.end).trim();

      final bool headIsSubstantial =
          head.split(RegExp(r'\s+')).length >= _minHeadWords;
      final bool tailIsInstruction =
          _opensWithStepVerb(tail) &&
          tail.split(RegExp(r'\s+')).length >= _minTailWords;
      if (head.isEmpty || !headIsSubstantial || !tailIsInstruction) break;

      parts.add(head);
      remaining = tail;
    }

    parts.add(remaining.trim());
    return parts;
  }

  static bool _opensWithStepVerb(String text) {
    final Match? first = RegExp(r'^[A-Za-z]+').firstMatch(text.trim());
    if (first == null) return false;
    return _stepVerbs.contains(first.group(0)!.toLowerCase());
  }

  /// Trims stray punctuation and capitalises the opening letter, so a clause
  /// lifted out of the middle of a sentence still reads as a step.
  static String _tidy(String value) {
    String text = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[,;:]+'), '')
        .trim();
    if (text.isEmpty) return text;
    final String first = text[0].toUpperCase();
    text = first + text.substring(1);
    return text;
  }
}
