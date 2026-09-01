@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/usda_nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/live_config.dart';

/// The USDA Edge Function, against the deployed one (spec §9.4).
///
/// A contract test in the strict sense: it checks that what the function
/// promises to return is what this adapter knows how to read. Everything else
/// about USDA is mocked, because the point here is the seam — and the seam is
/// where the key lives, so it cannot be exercised any other way.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  final ({String url, String key})? config = liveConfig();
  final String? skip = liveSkipReason();

  late UsdaNutritionSource usda;

  setUpAll(() {
    HttpOverrides.global = null;
    if (config == null) return;
    usda = UsdaNutritionSource(SupabaseClient(config.url, config.key));
  });

  test('a real UPC comes back as a food with macros', () async {
    final NutritionMatch? match = await usda.byBarcode('048707820026');

    expect(match, isNotNull, reason: 'this UPC is in the branded dataset');
    expect(match!.food.source, FoodSource.usda);
    expect(match.food.barcode, '048707820026');

    final ServingOption per100g = match.food.servingOptions.last;
    expect(per100g.label, '100 g');
    expect(per100g.macros.kcal, greaterThan(0));
  }, skip: skip);

  test('the pack serving keeps the words on the box and the grams', () async {
    // "2 Tbsp" is what a person reads; the grams are what the maths uses.
    final NutritionMatch match = (await usda.byBarcode('048707820026'))!;

    expect(match.food.servingOptions.length, greaterThan(1));
    // Leads, because it is the number a person reads off the box.
    final ServingOption serving = match.food.servingOptions.first;
    expect(serving.label, contains('g)'));
    expect(serving.amount.canonicalAmount, greaterThan(0));
  }, skip: skip);

  test('a barcode nobody has is a miss, not an error', () async {
    expect(await usda.byBarcode('0000000000000'), isNull);
  }, skip: skip);

  test('search returns something usable', () async {
    final List<NutritionMatch> results = await usda.search('cheddar', limit: 3);

    expect(results, isNotEmpty);
    expect(results.first.food.name, isNotEmpty);
    expect(results.first.food.servingOptions, isNotEmpty);
  }, skip: skip);

  test('a curated food says which side of USDA it came from', () async {
    // The peppers were always in the answer; Hearth's own ranking is what put
    // veggie chips above them. Ordering that correctly needs to know which
    // results are ingredients and which are packets, and only the function
    // can say — FDC's `dataType` is the field, and this is the seam it
    // crosses.
    final List<NutritionMatch> results = await usda.search(
      'red bell pepper',
      limit: 20,
    );

    expect(
      results.where((NutritionMatch m) => m.isGeneric),
      isNotEmpty,
      reason: 'USDA has four Foundation entries for bell peppers alone',
    );
  }, skip: skip);

  test(
    'a curated food is not dropped for stating energy differently',
    () async {
      // USDA's Foundation set does not carry nutrient 208 at all — it states
      // energy as Atwater general and specific factors instead. Requiring 208
      // silently discarded every one of them, so the best data USDA has for a
      // raw ingredient never reached the app, and a search for a bell pepper
      // answered with veggie chips.
      final List<NutritionMatch> results = await usda.search(
        'red bell pepper',
        limit: 20,
      );

      expect(
        results.map((NutritionMatch m) => m.food.name),
        contains('Peppers, bell, red, raw'),
      );
    },
    skip: skip,
  );

  test('an empty query never reaches the function', () async {
    expect(await usda.search('   '), isEmpty);
  }, skip: skip);
}
