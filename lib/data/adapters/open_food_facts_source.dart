import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../../domain/units/unit_converter.dart';
import 'nutrition_source.dart';

/// Open Food Facts, the second link in the chain (spec §5.5).
///
/// Needs no API key, which is why it can be called straight from the client
/// while USDA cannot: a keyed source has to sit behind an Edge Function so the
/// key never reaches a bundle (CLAUDE.md, §8.1).
///
/// It is a crowd-sourced database, so the data is uneven: fields are missing,
/// numbers are occasionally nonsense, and store brands are patchy. Every read
/// here is defensive, and anything doubtful is returned with low confidence
/// for a human to look at rather than quietly trusted.
class OpenFoodFactsSource implements NutritionSource {
  OpenFoodFactsSource({http.Client? client, String? userAgent})
    : _client = client ?? http.Client(),
      _userAgent = userAgent ?? defaultUserAgent;

  static const String host = 'world.openfoodfacts.org';

  /// Text search lives on a different service to barcode lookup.
  ///
  /// `world.openfoodfacts.org/api/v2/search` is not usable: it returns 503s
  /// intermittently, and when it does answer it ignores `search_terms`
  /// altogether — "chicken broth" and "cheddar cheese" came back with the same
  /// six products, none of them either. Search-a-licious is the service Open
  /// Food Facts now points text search at, and it actually reads the query.
  static const String searchHost = 'search.openfoodfacts.org';

  /// Open Food Facts asks apps to identify themselves; anonymous traffic gets
  /// rate-limited.
  static const String defaultUserAgent = 'Hearth/1.0 (household meal planner)';

  /// Fields worth asking for. Requesting everything makes the response many
  /// times larger for data this never reads.
  static const String fields =
      'code,product_name,brands,quantity,serving_size,nutriments';

  final http.Client _client;
  final String _userAgent;

  @override
  String get displayName => 'Open Food Facts';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    final String code = barcode.trim();
    if (code.isEmpty) return null;

    final Uri uri = Uri.https(
      host,
      '/api/v2/product/$code.json',
      <String, String>{'fields': fields},
    );

    final Map<String, Object?>? body = await _get(uri);
    if (body == null) return null;
    // status 0 means "no such product", which is an ordinary outcome that
    // hands off to the next source rather than an error.
    if (body['status'] != 1) return null;

    final Object? product = body['product'];
    if (product is! Map<String, Object?>) return null;
    return _toMatch(product, barcode: code);
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    final String needle = query.trim();
    if (needle.isEmpty) return const <NutritionMatch>[];

    final Uri uri = Uri.https(searchHost, '/search', <String, String>{
      'q': needle,
      // Deliberately no `sort_by`: Search-a-licious only sorts by relevance
      // when nothing overrides it, and `sort_by` is not a tiebreaker on top
      // of that — it replaces relevance entirely. `sort_by=-popularity_key`
      // was tried here for exactly the "results feel random" complaint this
      // fixes, and it does return well-known brands first for a query with
      // many popular near-matches ("chicken broth" → Swanson). But it also
      // sorts the *entire* multi-thousand-result match set by popularity
      // before relevance ever gets a vote, so a query with an exact but less
      // globally popular answer never appears within the page at all — a
      // search for "96/4 Ground Beef" returned peanut butter and coffee, with
      // real matches for the query buried past position 10,000. Relevance
      // alone already surfaces the right answer first for both cases.
      'fields': fields,
      'page_size': '$limit',
    });

    final Map<String, Object?>? body = await _get(uri);
    if (body == null) return const <NutritionMatch>[];

    // Search-a-licious calls them hits, not products.
    final Object? hits = body['hits'];
    if (hits is! List<Object?>) return const <NutritionMatch>[];

    return <NutritionMatch>[
      for (final Object? hit in hits)
        if (hit is Map<String, Object?>)
          if (_toMatch(hit) case final NutritionMatch match) match,
    ];
  }

  Future<Map<String, Object?>?> _get(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: <String, String>{'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(response.body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      // A source being unreachable is not a failure of the lookup — the chain
      // moves on. Standing in a supermarket aisle is the worst possible place
      // to be shown a network error.
      return null;
    }
  }

  /// Builds a food from one product, or null when there is not enough to be
  /// worth offering.
  NutritionMatch? _toMatch(Map<String, Object?> product, {String? barcode}) {
    final String name = '${product['product_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;

    final Object? nutriments = product['nutriments'];
    if (nutriments is! Map<String, Object?>) return null;

    final double? kcal = _number(nutriments['energy-kcal_100g']);
    if (kcal == null) return null;

    final Macros per100g = Macros(
      kcal: kcal,
      proteinG: _number(nutriments['proteins_100g']) ?? 0,
      carbG: _number(nutriments['carbohydrates_100g']) ?? 0,
      fatG: _number(nutriments['fat_100g']) ?? 0,
    );

    final String? brand = _firstBrand(product['brands']);
    final String code = barcode ?? '${product['code'] ?? ''}'.trim();

    return NutritionMatch(
      food: Food(
        // The barcode is the id: scanning the same product twice must land on
        // the same food rather than making a second one.
        id: 'off:$code',
        name: name,
        brand: brand,
        barcode: code.isEmpty ? null : code,
        source: FoodSource.openFoodFacts,
        // The pack's own serving leads. `Food.defaultServing` is whatever comes
        // first, and it is what every screen shows and what a log defaults to
        // — so it has to be the number written on the tin, not a laboratory
        // hundred grams.
        servingOptions: <ServingOption>[
          ...?_servingOption(
            product['serving_size'],
            product['serving_quantity'],
            per100g,
            code,
          ),
          ServingOption(
            id: 'off:$code:100g',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: per100g,
          ),
        ],
      ),
      source: FoodSource.openFoodFacts,
      confidence: _confidence(per100g, brand: brand),
    );
  }

  /// The pack's own serving, when it states one in a unit that can be measured.
  ///
  /// Grams *or* millilitres. Only grams were read at first, so every liquid on
  /// the shelf came back offering nothing but "100 g" — scanning a tin of
  /// chicken broth that says "1 cup, 4 servings per container" produced a
  /// serving size nobody has ever measured out.
  ///
  /// A serving given as "1 biscuit" is still refused: that cannot be converted
  /// without knowing what a biscuit weighs, and guessing would put a wrong
  /// number into someone's day.
  List<ServingOption>? _servingOption(
    Object? servingSize,
    Object? servingQuantity,
    Macros per100g,
    String code,
  ) {
    final String text = '${servingSize ?? ''}'.trim();
    if (text.isEmpty) return null;

    final RegExpMatch? match = RegExp(
      r'([\d.,]+)\s*(g|ml)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final bool isVolume = match.group(2)!.toLowerCase() == 'ml';

    // Open Food Facts states the amount separately as well, and that field is
    // cleaner than anything pulled back out of the label text.
    final double? amount =
        _number(servingQuantity) ??
        double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return null;

    // Open Food Facts' per-100 figures apply against 100 g or 100 ml
    // interchangeably, so the same ratio holds either way — computed from the
    // metric amount actually on record, before the unit is re-expressed below.
    final Macros macros = per100g.scaledBy(amount / 100);

    if (!isVolume) {
      // What the packet itself says, when Open Food Facts kept it.
      //
      // Its numeric fields are always metric — `serving_quantity` is grams
      // for every US product checked — so reading only those made every
      // scanned food come back in grams however the label was written. The
      // household measure often survives in the text beside them
      // ("3/4 cup (28 g)", "1 oz (28 g)"), and it is the one printed on the
      // box, so it leads when it is there.
      final Quantity? stated = _statedHouseholdMeasure(text);
      return <ServingOption>[
        if (stated != null)
          ServingOption(
            id: 'off:$code:stated',
            label: QuantityFormat.format(stated),
            // A volume measure against a weight of grams is not a rounding
            // of it — it is the density of this food, stated by its own
            // maker, and the only place that fact exists.
            amount: stated.kind == UnitKind.mass
                ? UnitConverter.normalise(
                    Quantity.of(amount, Units.gram),
                    system: UnitSystem.imperial,
                  )
                : stated,
            macros: macros,
          ),
        ServingOption(
          id: 'off:$code:serving',
          label: text,
          amount: Quantity.of(amount, Units.gram),
          macros: macros,
        ),
      ];
    }

    // Open Food Facts states volume in millilitres regardless of how the pack
    // itself is labelled — a Swanson tin that says "1 cup, 4 servings per
    // container" still reports "1 serving (240 ml)". Re-expressed in cups,
    // tablespoons or teaspoons, whichever reads as a whole-ish number, so the
    // scan review screen — and every later view of the saved food — shows
    // what is printed on the box rather than OFF's metric bookkeeping.
    final Quantity imperial = UnitConverter.normalise(
      Quantity.of(amount, Units.millilitre),
      system: UnitSystem.imperial,
    );
    return <ServingOption>[
      ServingOption(
        id: 'off:$code:serving',
        label: QuantityFormat.format(imperial),
        amount: imperial,
        macros: macros,
      ),
    ];
  }

  /// The household measure a label leads with, when it names one.
  ///
  /// "3/4 cup (28 g)" and "1 oz (28 g)" both carry a measure a cook can
  /// actually use in front of the metric figure. "1 serving (28 g)",
  /// "1 bar (43 g)" and "0.5 Can (207 g)" do not — a serving, a bar and a can
  /// cannot be measured out — so those come back null and the grams stand.
  static Quantity? _statedHouseholdMeasure(String text) {
    final RegExpMatch? match = RegExp(
      r'^\s*([\d]+(?:[./\s]\d+)*)\s*([a-zA-Z]+)',
    ).firstMatch(text);
    if (match == null) return null;

    final double? amount = parseAmount(match.group(1)!);
    if (amount == null || amount <= 0) return null;

    final Unit? unit = Units.parse(match.group(2)!);
    if (unit == null) return null;
    // Already the metric figure, so there is nothing to restore.
    if (unit == Units.gram || unit == Units.millilitre) return null;
    if (unit.kind == UnitKind.count) return null;

    return Quantity.of(amount, unit);
  }

  /// How much to trust the row.
  ///
  /// Crowd-sourced data is uneven, and the honest signal is how complete and
  /// how plausible it looks. A wrong macro corrupts a day's numbers invisibly,
  /// so anything doubtful is flagged for a human rather than assumed (§5.3).
  static double _confidence(Macros per100g, {String? brand}) {
    // Nothing edible is over 900 kcal per 100 g — pure fat is about 900.
    if (per100g.kcal <= 0 || per100g.kcal > 900) return 0.3;

    double score = 0.75;
    if (brand != null && brand.isNotEmpty) score += 0.1;
    if (per100g.proteinG > 0 || per100g.carbG > 0 || per100g.fatG > 0) {
      score += 0.1;
    } else {
      // Energy with no macronutrients at all is a half-filled entry.
      score -= 0.25;
    }
    return score.clamp(0, 1);
  }

  /// The first brand, from either shape the two services use.
  ///
  /// The barcode endpoint sends a comma-separated string; search sends a list.
  /// Stringifying a list would have produced "[Heinz]", brackets and all, on
  /// every search result.
  static String? _firstBrand(Object? brands) {
    if (brands is List<Object?>) {
      for (final Object? brand in brands) {
        final String text = '${brand ?? ''}'.trim();
        if (text.isNotEmpty) return text;
      }
      return null;
    }

    final String text = '${brands ?? ''}'.trim();
    if (text.isEmpty) return null;
    return text.split(',').first.trim();
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s.replaceAll(',', '.')),
    _ => null,
  };
}
