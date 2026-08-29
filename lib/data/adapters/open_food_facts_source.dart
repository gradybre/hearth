import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
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

    final Uri uri = Uri.https(host, '/api/v2/search', <String, String>{
      'search_terms': needle,
      'fields': fields,
      'page_size': '$limit',
    });

    final Map<String, Object?>? body = await _get(uri);
    if (body == null) return const <NutritionMatch>[];

    final Object? products = body['products'];
    if (products is! List<Object?>) return const <NutritionMatch>[];

    return <NutritionMatch>[
      for (final Object? product in products)
        if (product is Map<String, Object?>)
          if (_toMatch(product) case final NutritionMatch match) match,
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
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'off:$code:100g',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: per100g,
          ),
          ...?_servingOption(product['serving_size'], per100g, code),
        ],
      ),
      source: FoodSource.openFoodFacts,
      confidence: _confidence(per100g, brand: brand),
    );
  }

  /// The pack's own serving, when it states one in grams.
  ///
  /// Only grams: a serving given as "1 biscuit" cannot be converted without
  /// knowing what a biscuit weighs, and guessing there would put a wrong
  /// number into someone's day.
  List<ServingOption>? _servingOption(
    Object? servingSize,
    Macros per100g,
    String code,
  ) {
    final String text = '${servingSize ?? ''}'.trim();
    if (text.isEmpty) return null;

    final RegExpMatch? match = RegExp(
      r'([\d.,]+)\s*g\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final double? grams = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (grams == null || grams <= 0) return null;

    return <ServingOption>[
      ServingOption(
        id: 'off:$code:serving',
        label: text,
        amount: Quantity.of(grams, Units.gram),
        macros: per100g.scaledBy(grams / 100),
      ),
    ];
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

  static String? _firstBrand(Object? brands) {
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
