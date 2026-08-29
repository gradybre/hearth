@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/usda_nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The USDA Edge Function, against the deployed one (spec §9.4).
///
/// A contract test in the strict sense: it checks that what the function
/// promises to return is what this adapter knows how to read. Everything else
/// about USDA is mocked, because the point here is the seam — and the seam is
/// where the key lives, so it cannot be exercised any other way.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  final ({String url, String key})? config = _hostedConfig();
  final String? skip = config == null
      ? 'needs config/hosted.json with a publishable key'
      : null;

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

    final ServingOption per100g = match.food.servingOptions.first;
    expect(per100g.label, '100 g');
    expect(per100g.macros.kcal, greaterThan(0));
  }, skip: skip);

  test('the pack serving keeps the words on the box and the grams', () async {
    // "2 Tbsp" is what a person reads; the grams are what the maths uses.
    final NutritionMatch match = (await usda.byBarcode('048707820026'))!;

    expect(match.food.servingOptions.length, greaterThan(1));
    final ServingOption serving = match.food.servingOptions.last;
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

  test('an empty query never reaches the function', () async {
    expect(await usda.search('   '), isEmpty);
  }, skip: skip);
}

/// The hosted project's URL and publishable key, or null when not set up.
///
/// Read from the gitignored config, never from the repo. The USDA key itself
/// is not here and never passes through the client — that is the whole reason
/// the function exists.
({String url, String key})? _hostedConfig() {
  if (Platform.environment['HEARTH_LIVE'] != '1') return null;

  final File file = File('config/hosted.json');
  if (!file.existsSync()) return null;

  final String text = file.readAsStringSync();
  final String? url = RegExp('"SUPABASE_URL"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);
  final String? key = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);

  if (url == null || key == null || key.isEmpty) return null;
  return (url: url, key: key);
}
