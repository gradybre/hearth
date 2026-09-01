import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/usda_nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockFunctions extends Mock implements FunctionsClient {}

/// USDA reached through its Edge Function (spec §5.5).
///
/// The function's response shape is the contract; this is where a change to it
/// should be felt, rather than in whatever screen happens to show the food.
UsdaNutritionSource sourceReturning(Map<String, Object?> payload) {
  final _MockClient client = _MockClient();
  final _MockFunctions functions = _MockFunctions();

  when(() => client.functions).thenReturn(functions);
  when(() => functions.invoke(any(), body: any(named: 'body')))
      .thenAnswer((_) async => FunctionResponse(data: payload, status: 200));

  return UsdaNutritionSource(client);
}

Map<String, Object?> aHit({
  String? servingLabel,
  double servingGrams = 28,
  String? dataType,
}) => <String, Object?>{
  'matches': <Object?>[
    <String, Object?>{
      'fdc_id': '123',
      'name': 'Cheddar cheese',
      'data_type': ?dataType,
      'per_100g': <String, Object?>{
        'kcal': 400,
        'protein_g': 25,
        'carb_g': 1.3,
        'fat_g': 33,
      },
      'serving_grams': servingGrams,
      'serving_label': ?servingLabel,
    },
  ],
};

void main() {
  group('which side of USDA an answer came from', () {
    // Two datasets in one API: a couple of thousand curated whole foods and
    // about two million branded labels. Which one answered decides whether
    // this is an ingredient or a packet, and only the function can say.
    test('a curated food is a plain ingredient', () async {
      final List<NutritionMatch> matches = await sourceReturning(
        aHit(dataType: 'SR Legacy'),
      ).search('cheddar');

      expect(matches.single.isGeneric, isTrue);
    });

    test('a branded label is not', () async {
      final List<NutritionMatch> matches = await sourceReturning(
        aHit(dataType: 'Branded'),
      ).search('cheddar');

      expect(matches.single.isGeneric, isFalse);
    });

    test('a function that has not said yet is treated as a packet', () async {
      // Fail towards the status quo: an older deployment says nothing, and
      // nothing must not read as "this is the ingredient you wanted".
      final List<NutritionMatch> matches = await sourceReturning(aHit())
          .search('cheddar');

      expect(matches.single.isGeneric, isFalse);
    });
  });

  test('the measure the box states leads, not the metric weight', () async {
    // The function reports the weight and states the household measure
    // separately. Keeping only the weight meant a food saved from here could
    // never be used against a recipe line written in cups, and every screen
    // showed a number nobody measures out.
    final List<NutritionMatch> matches = await sourceReturning(
      aHit(servingLabel: '1/4 cup'),
    ).search('cheddar');

    final ServingOption serving = matches.single.food.defaultServing!;
    expect(serving.amount.kind, UnitKind.volume);
    expect(serving.amount.amountIn(Units.cup), closeTo(0.25, 1e-12));
    expect(serving.label, '¼ cup');
    // Scaled from the per-100 g figures by the weight, not by the volume.
    expect(serving.macros.kcal, closeTo(112, 1e-9));
  });

  test('the metric weight is still offered underneath it', () async {
    final List<NutritionMatch> matches = await sourceReturning(
      aHit(servingLabel: '1/4 cup'),
    ).search('cheddar');

    final List<ServingOption> options = matches.single.food.servingOptions;
    expect(options.map((ServingOption o) => o.label), <String>[
      '¼ cup',
      '1/4 cup (28 g)',
      '100 g',
    ]);
  });

  test('a label naming nothing measurable leaves the grams alone', () async {
    final List<NutritionMatch> matches = await sourceReturning(
      aHit(servingLabel: '1 slice'),
    ).search('cheddar');

    final ServingOption serving = matches.single.food.defaultServing!;
    expect(serving.label, '1 slice (28 g)');
    expect(serving.amount.amountIn(Units.gram), closeTo(28, 1e-9));
  });

  test('no stated label at all is still a usable serving', () async {
    final List<NutritionMatch> matches = await sourceReturning(aHit())
        .search('cheddar');

    expect(matches.single.food.defaultServing!.label, '28 g');
  });
}
