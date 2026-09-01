import '../../domain/models/food.dart';
import '../../domain/text/text_normaliser.dart';
import 'barcode_scanner.dart';
import 'nutrition_source.dart';

/// The lookup chain: library → Open Food Facts → USDA → manual (spec §5.5).
///
/// Order is the whole design. The household's own library is asked first
/// because it works offline and because a food this household has already
/// corrected must outrank a stranger's version of it. External sources follow
/// in the order the spec sets, and a miss everywhere is not an error — it is
/// the manual-entry path, which is a first-class outcome rather than a
/// failure.
class NutritionLookup {
  NutritionLookup(this.sources);

  /// In priority order. The first source with an answer wins for a barcode;
  /// search gathers from all of them.
  final List<NutritionSource> sources;

  /// The first match for a barcode, or null when nobody has heard of it.
  ///
  /// Stops at the first hit rather than polling everything: the library
  /// answering means the answer is already the household's own, and asking
  /// the internet afterwards could only produce a worse one.
  Future<NutritionMatch?> byBarcode(String barcode) async {
    // Every form of the number, not just the digits as scanned. UPC-A is
    // EAN-13 with a leading zero and the databases disagree about which they
    // store, so looking up only what the camera read misses half the shelf
    // for no reason anyone could understand.
    final List<String> variants = BarcodeVariants.of(barcode);
    for (final NutritionSource source in sources) {
      for (final String variant in variants) {
        final NutritionMatch? match = await source.byBarcode(variant);
        if (match != null) return match;
      }
    }
    return null;
  }

  /// The household's own library only, by barcode.
  ///
  /// For codes that mean something here and nothing outside — a produce PLU
  /// saved against a food is this household's decision about what 4011 means
  /// to them, and asking the internet about the number would fetch an
  /// unrelated product rather than a better answer.
  Future<NutritionMatch?> fromLibraryByBarcode(String barcode) async {
    for (final NutritionSource source in sources) {
      final NutritionMatch? match = await source.byBarcode(barcode);
      if (match != null && match.fromLibrary) return match;
    }
    return null;
  }

  /// Search results from every source, the household's own first.
  ///
  /// Every source is asked at once and each gets a guaranteed share of the
  /// results. Taking them strictly in order looked right and was not: Open
  /// Food Facts returns a full page for almost any word, so it filled the
  /// whole quota and USDA — much the better source for unbranded staples —
  /// was never reached at all. A search for "cheddar cheese" came back with
  /// bottled water and no cheese.
  ///
  /// Priority still decides ties: shares are filled in order, leftover slots
  /// go to the earlier sources, and duplicates collapse onto the first
  /// source that offered them.
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    if (sources.isEmpty || limit <= 0) return const <NutritionMatch>[];

    // Concurrently, because these are independent network calls and asking
    // them in turn makes the user wait for the sum of every timeout.
    final List<List<NutritionMatch>> perSource = await Future.wait(
      <Future<List<NutritionMatch>>>[
        for (final NutritionSource source in sources)
          source.search(query, limit: limit),
      ],
    );

    final List<List<NutritionMatch>> relevant = <List<NutritionMatch>>[
      for (final List<NutritionMatch> matches in perSource)
        <NutritionMatch>[
          for (final NutritionMatch match in matches)
            if (_isRelevant(match, query)) match,
        ],
    ];

    final int share = (limit / sources.length).ceil();
    final Set<String> seenBarcodes = <String>{};
    final List<NutritionMatch> found = <NutritionMatch>[];

    void take(int sourceIndex, int upTo) {
      for (final NutritionMatch match in relevant[sourceIndex]) {
        if (found.length >= limit || upTo <= 0) return;
        if (found.contains(match)) continue;
        final String? barcode = match.food.barcode;
        if (barcode != null && !seenBarcodes.add(barcode)) continue;
        found.add(match);
        upTo--;
      }
    }

    for (int i = 0; i < sources.length; i++) {
      take(i, share);
    }
    // Slack from sources that had little or nothing goes to the trusted ones.
    for (int i = 0; i < sources.length && found.length < limit; i++) {
      take(i, limit);
    }

    return _ranked(found, query);
  }

  /// Puts the likeliest answer first.
  ///
  /// Source order alone decided this before, which meant the list was whatever
  /// Open Food Facts happened to return followed by whatever USDA happened to
  /// return — relevant, after the filter, but in no order a person could see a
  /// reason for.
  ///
  /// The household's own foods stay on top regardless: they are few, they are
  /// already vouched for, and burying one under a stranger's product would
  /// undo the point of keeping a library.
  static List<NutritionMatch> _ranked(
    List<NutritionMatch> matches,
    String query,
  ) {
    final List<String> terms = _terms(query);

    final List<NutritionMatch> ordered = <NutritionMatch>[...matches];
    ordered.sort((NutritionMatch a, NutritionMatch b) {
      if (a.fromLibrary != b.fromLibrary) return a.fromLibrary ? -1 : 1;

      final int byName = _nameScore(b, terms).compareTo(_nameScore(a, terms));
      if (byName != 0) return byName;

      // Something with no numbers on it cannot be logged, so it sinks — but
      // it is still shown, flagged as incomplete, rather than hidden.
      final int byUsable = _usable(b).compareTo(_usable(a));
      if (byUsable != 0) return byUsable;

      return b.confidence.compareTo(a.confidence);
    });
    return ordered;
  }

  /// How well a result's name answers what was asked.
  ///
  /// An exact name beats a name that merely starts with the words, which beats
  /// one that happens to contain them somewhere — "Chicken broth" over
  /// "Chicken broth concentrate" over "Rice with chicken broth".
  static int _nameScore(NutritionMatch match, List<String> terms) {
    if (terms.isEmpty) return 0;

    final String name = normaliseKey(match.food.name);
    final String wanted = terms.join(' ');
    if (name == wanted) return 100;
    if (name.startsWith(wanted)) return 80;
    if (name.contains(wanted)) return 60;

    final String haystack = normaliseKey(
      '${match.food.name} ${match.food.brand ?? ''}',
    );
    return (terms.where(haystack.contains).length * 40) ~/ terms.length;
  }

  static int _usable(NutritionMatch match) =>
      match.food.servingOptions.any(
        (ServingOption option) => !option.macros.isZero,
      )
      ? 1
      : 0;

  static List<String> _terms(String query) => <String>[
    for (final String word in normaliseKey(query).split(' '))
      if (word.isNotEmpty) word,
  ];

  /// Whether a result has anything to do with what was asked for.
  ///
  /// Open Food Facts matches loosely enough to answer "cheddar cheese" with
  /// mineral water. A result the user cannot recognise as what they searched
  /// for is not a lead they have to weigh — it is work they have to do to
  /// ignore it, and enough of it reads as the search being broken.
  ///
  /// Words shorter than four characters are not used to filter: "oat" would
  /// throw away "Oatly" for want of a word boundary, and dropping a real
  /// answer is the worse mistake.
  static bool _isRelevant(NutritionMatch match, String query) {
    final List<String> terms = <String>[
      for (final String word in normaliseKey(query).split(' '))
        if (word.length >= 4) word,
    ];
    if (terms.isEmpty) return true;

    final String haystack = normaliseKey(
      '${match.food.name} ${match.food.brand ?? ''}',
    );
    return terms.any(haystack.contains);
  }
}

/// What a barcode scan turned up, and where from.
///
/// A miss is modelled as a value rather than a null so the screen can say
/// "nobody has heard of this — add it yourself" with the barcode in hand,
/// which is the path §5.5 asks for.
class BarcodeResult {
  const BarcodeResult.found(this.barcode, NutritionMatch this.match);
  const BarcodeResult.miss(this.barcode) : match = null;

  final String barcode;
  final NutritionMatch? match;

  bool get isMiss => match == null;

  /// True when something was found but is not to be trusted without a look.
  bool get needsReview => match?.isLowConfidence ?? false;

  FoodSource? get source => match?.source;
}
