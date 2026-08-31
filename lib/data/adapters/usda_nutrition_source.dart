import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/serving_label.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import 'nutrition_source.dart';

/// USDA FoodData Central, reached through an Edge Function (spec §5.5).
///
/// The third link in the chain, and the only one that cannot be called
/// directly: FDC requires an API key, and a key in the client is a key anyone
/// can pull out of the app bundle (CLAUDE.md §8.1). The function holds the key
/// and this asks the function.
///
/// It also means USDA's response shape is parsed server-side, so a change
/// there is a redeploy rather than an App Store release. What arrives here is
/// already the small stable shape the function promises.
class UsdaNutritionSource implements NutritionSource {
  UsdaNutritionSource(this._client);

  static const String functionName = 'usda-lookup';

  final SupabaseClient _client;

  @override
  String get displayName => 'USDA';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    final String code = barcode.trim();
    if (code.isEmpty) return null;

    final List<NutritionMatch> matches = await _invoke(<String, Object?>{
      'barcode': code,
    });
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    final String needle = query.trim();
    if (needle.isEmpty) return const <NutritionMatch>[];

    return _invoke(<String, Object?>{'query': needle, 'limit': limit});
  }

  Future<List<NutritionMatch>> _invoke(Map<String, Object?> body) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: body,
      );

      final Object? data = response.data;
      if (data is! Map) return const <NutritionMatch>[];

      final Object? matches = data['matches'];
      if (matches is! List) return const <NutritionMatch>[];

      return <NutritionMatch>[
        for (final Object? raw in matches)
          if (raw is Map)
            if (_toMatch(raw) case final NutritionMatch m) m,
      ];
    } on Object {
      // A source being unreachable is a miss, not a failure: the chain moves
      // on, and standing in a supermarket aisle is the worst possible place
      // to be shown a network error.
      return const <NutritionMatch>[];
    }
  }

  NutritionMatch? _toMatch(Map<Object?, Object?> json) {
    final String name = '${json['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;

    final Object? per100 = json['per_100g'];
    if (per100 is! Map) return null;

    final double? kcal = _number(per100['kcal']);
    if (kcal == null) return null;

    final Macros per100g = Macros(
      kcal: kcal,
      proteinG: _number(per100['protein_g']) ?? 0,
      carbG: _number(per100['carb_g']) ?? 0,
      fatG: _number(per100['fat_g']) ?? 0,
    );

    final String id = '${json['fdc_id'] ?? ''}'.trim();
    final String? barcode = _text(json['barcode']);

    return NutritionMatch(
      food: Food(
        // Keyed by FDC id: the same food found twice is one food, and USDA's
        // id is the only thing here guaranteed stable.
        id: 'usda:$id',
        name: name,
        brand: _text(json['brand']),
        barcode: barcode,
        source: FoodSource.usda,
        // The pack's own serving leads, for the same reason it does in Open
        // Food Facts: `Food.defaultServing` is whatever comes first, and what
        // a log defaults to should be the number written on the box.
        servingOptions: <ServingOption>[
          ...?_packServing(json, per100g, id),
          ServingOption(
            id: 'usda:$id:100g',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: per100g,
          ),
        ],
      ),
      source: FoodSource.usda,
      confidence: _number(json['confidence']) ?? 0.5,
    );
  }

  /// The pack's own serving, when the function found one in grams.
  ///
  /// The label's own measure is recovered as a real quantity rather than left
  /// as prose. USDA reports the weight — `serving_grams` — and states the
  /// household measure separately as "2 Tbsp"; keeping only the grams meant a
  /// food saved from here could never be used against a recipe line written in
  /// tablespoons, and every screen showed a weight nobody measures out. Both
  /// options are offered, the measurable one first, so `defaultServing` is the
  /// number written on the box (see [servingAmountFor]).
  List<ServingOption>? _packServing(
    Map<Object?, Object?> json,
    Macros per100g,
    String id,
  ) {
    final double? grams = _number(json['serving_grams']);
    if (grams == null || grams <= 0) return null;

    final String? stated = _text(json['serving_label']);
    final Macros macros = per100g.scaledBy(grams / 100);
    final Quantity? measure = stated == null
        ? null
        : statedHouseholdMeasure(stated);

    return <ServingOption>[
      if (measure != null)
        ServingOption(
          id: 'usda:$id:stated',
          label: QuantityFormat.format(servingAmountFor(stated!, grams: grams)),
          amount: servingAmountFor(stated, grams: grams),
          macros: macros,
        ),
      ServingOption(
        id: 'usda:$id:serving',
        label: stated == null
            ? '${_trim(grams)} g'
            : '$stated (${_trim(grams)} g)',
        amount: Quantity.of(grams, Units.gram),
        macros: macros,
      ),
    ];
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  static String? _text(Object? value) {
    final String text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}
