import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/open_food_facts_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A product as Open Food Facts actually returns one.
Map<String, Object?> product({
  String name = 'Baked beans',
  String? brands = 'Heinz',
  String code = '5000157024671',
  Object? kcal = 78,
  Object? protein = 4.7,
  Object? carbs = 12.9,
  Object? fat = 0.2,
  String? servingSize,
}) => <String, Object?>{
  'code': code,
  'product_name': name,
  'brands': ?brands,
  'serving_size': ?servingSize,
  'nutriments': <String, Object?>{
    'energy-kcal_100g': kcal,
    'proteins_100g': protein,
    'carbohydrates_100g': carbs,
    'fat_100g': fat,
  },
};

OpenFoodFactsSource sourceReturning(
  Object? body, {
  int status = 200,
  List<Uri>? recordInto,
}) => OpenFoodFactsSource(
  client: MockClient((http.Request request) async {
    recordInto?.add(request.url);
    return http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }),
);

void main() {
  group('a barcode that exists', () {
    test('becomes a food with macros per 100 g', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;

      expect(match.food.name, 'Baked beans');
      expect(match.food.brand, 'Heinz');
      expect(match.food.source, FoodSource.openFoodFacts);
      final ServingOption per100g = match.food.servingOptions.first;
      expect(per100g.label, '100 g');
      expect(per100g.macros.kcal, 78);
      expect(per100g.macros.proteinG, 4.7);
    });

    test('the barcode is the id, so scanning twice is one food', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;
      expect(match.food.id, 'off:5000157024671');
      expect(match.food.barcode, '5000157024671');
    });

    test('a pack serving in grams leads, with the 100 g behind it', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(servingSize: '200 g'),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;

      expect(match.food.servingOptions, hasLength(2));
      final ServingOption serving = match.food.servingOptions.first;
      expect(serving.label, '200 g');
      expect(serving.macros.kcal, closeTo(156, 0.001));
    });

    test('a serving given in pieces is not guessed at', () async {
      // "1 biscuit" cannot be converted without knowing what a biscuit
      // weighs, and a guess there puts a wrong number in someone's day.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(servingSize: '1 biscuit'),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;
      expect(match.food.servingOptions, hasLength(1));
    });
  });

  group('a barcode that does not', () {
    test('status 0 is a miss, not an error', () async {
      // A miss hands off to the next source; it is the ordinary case.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 0,
      });

      expect(await off.byBarcode('0000000000000'), isNull);
    });

    test('an unreachable source is a miss too', () async {
      // Standing in a supermarket aisle is the worst place to meet a network
      // error, so the chain simply moves on.
      final OpenFoodFactsSource off = OpenFoodFactsSource(
        client: MockClient(
          (http.Request request) async => throw const SocketExceptionStub(),
        ),
      );

      expect(await off.byBarcode('5000157024671'), isNull);
    });

    test('so is a server error', () async {
      final OpenFoodFactsSource off = sourceReturning(
        <String, Object?>{},
        status: 503,
      );
      expect(await off.byBarcode('5000157024671'), isNull);
    });

    test('an empty barcode is never sent anywhere', () async {
      final List<Uri> calls = <Uri>[];
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 0,
      }, recordInto: calls);

      expect(await off.byBarcode('  '), isNull);
      expect(calls, isEmpty);
    });
  });

  group('data worth doubting is flagged, not trusted', () {
    Future<double> confidenceFor(Map<String, Object?> p) async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': p,
      });
      return (await off.byBarcode('5000157024671'))!.confidence;
    }

    test('a complete branded row is trusted', () async {
      expect(await confidenceFor(product()), greaterThan(0.7));
    });

    test('energy with no macros at all is not', () async {
      // A half-filled entry. Believing it silently corrupts a day's numbers.
      expect(
        await confidenceFor(product(protein: 0, carbs: 0, fat: 0)),
        lessThan(0.7),
      );
    });

    test('an impossible calorie count is not', () async {
      // Nothing edible is over 900 kcal per 100 g; pure fat is about 900.
      expect(await confidenceFor(product(kcal: 3200)), lessThan(0.7));
    });

    test('a product with no name at all is not offered', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(name: '   '),
      });
      expect(await off.byBarcode('5000157024671'), isNull);
    });

    test('a product with no energy is not offered', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(kcal: null),
      });
      expect(await off.byBarcode('5000157024671'), isNull);
    });
  });

  group('numbers as they actually arrive', () {
    test('a decimal comma is read, not dropped', () async {
      // Much of the database is written by people using a comma decimal.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(kcal: '78,5'),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;
      expect(match.food.servingOptions.first.macros.kcal, 78.5);
    });

    test('only the first of several brands is kept', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(brands: 'Heinz,Heinz Beanz,H. J. Heinz'),
      });

      final NutritionMatch match = (await off.byBarcode('5000157024671'))!;
      expect(match.food.brand, 'Heinz');
    });
  });

  group('the serving people actually read', () {
    test('the pack serving leads, not per 100 g', () async {
      // Scanning Swanson chicken broth offered "100 g". The tin says one cup,
      // four servings per container — 100 g of broth is a number nobody has
      // ever measured out.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': <String, Object?>{
          ...product(name: 'Chicken broth', kcal: 6.25),
          'serving_size': '1 serving (240 ml)',
          'serving_quantity': 240,
        },
      });

      final NutritionMatch match = (await off.byBarcode('051000132796'))!;
      final ServingOption first = match.food.servingOptions.first;

      // Not OFF's raw "1 serving (240 ml)" — see "a metric volume serving
      // reads the way a US kitchen reads it" below for that.
      expect(first.label, '1 cup');
      expect(first.amount.amountIn(Units.millilitre), 240);
      expect(first.macros.kcal, closeTo(15, 0.01));
    });

    test('per 100 g is still offered, just not first', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': <String, Object?>{
          ...product(name: 'Chicken broth', kcal: 6.25),
          'serving_size': '1 serving (240 ml)',
          'serving_quantity': 240,
        },
      });

      final NutritionMatch match = (await off.byBarcode('051000132796'))!;
      expect(match.food.servingOptions, hasLength(2));
      expect(match.food.servingOptions.last.label, '100 g');
    });

    test('millilitres count as a serving, not just grams', () async {
      // Only grams were parsed before, so every liquid on the shelf came back
      // with 100 g as its only option. A volume is a real unit Hearth already
      // converts; a count like "1 biscuit" is the thing that genuinely cannot
      // be weighed, and that is still refused.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': <String, Object?>{
          ...product(name: 'Oat drink', kcal: 45),
          'serving_size': '250 ml',
        },
      });

      final ServingOption first = (await off.byBarcode('1'))!
          .food
          .servingOptions
          .first;
      expect(first.amount.amountIn(Units.millilitre), 250);
    });

    test(
      'a metric volume serving reads the way a US kitchen reads it',
      () async {
        // Real Swanson chicken broth data: Open Food Facts states the serving
        // as "1 serving (240 ml)" regardless of what the tin itself says — and
        // the tin says "1 cup". 100 g led before this, then the raw "240 ml"
        // after that was fixed; a US household still had to do the arithmetic
        // in their head either way.
        final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
          'status': 1,
          'product': <String, Object?>{
            ...product(name: 'Chicken broth', kcal: 6.25),
            'serving_size': '1 serving (240 ml)',
            'serving_quantity': 240,
          },
        });

        final ServingOption first = (await off.byBarcode('051000132796'))!
            .food
            .servingOptions
            .first;

        expect(first.label, '1 cup');
        expect(first.amount.preferredUnit, Units.cup);
        // The maths must not move with the display: still 240 ml underneath,
        // and still the same 15 kcal Swanson's own label states.
        expect(first.amount.amountIn(Units.millilitre), 240);
        expect(first.macros.kcal, closeTo(15, 0.01));
      },
    );

    test('a serving nobody can weigh is still refused', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': <String, Object?>{
          ...product(name: 'Digestives', kcal: 478),
          'serving_size': '1 biscuit',
        },
      });

      final Food food = (await off.byBarcode('1'))!.food;
      expect(food.servingOptions, hasLength(1));
      expect(food.servingOptions.single.label, '100 g');
    });

    test('a pack with no stated serving is unchanged', () async {
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'status': 1,
        'product': product(name: 'Chicken broth'),
      });

      final Food food = (await off.byBarcode('1'))!.food;
      expect(food.servingOptions.single.label, '100 g');
    });
  });

  group('search', () {
    test('returns only products it can make sense of', () async {
      // Search-a-licious calls them hits; the barcode endpoint says products.
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'hits': <Object?>[
          product(name: 'Baked beans'),
          product(name: '', code: '2'),
          product(name: 'No energy', kcal: null, code: '3'),
          'not even a map',
        ],
      });

      final List<NutritionMatch> results = await off.search('beans');
      expect(results, hasLength(1));
      expect(results.single.food.name, 'Baked beans');
    });

    test('search goes to the service that reads the query', () async {
      // `world.openfoodfacts.org/api/v2/search` returns 503s intermittently
      // and otherwise ignores search_terms entirely — "chicken broth" and
      // "cheddar cheese" came back with the same six unrelated products.
      final List<Uri> calls = <Uri>[];
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'hits': <Object?>[product(name: 'Chicken broth')],
      }, recordInto: calls);

      await off.search('chicken broth');

      expect(calls.single.host, OpenFoodFactsSource.searchHost);
      expect(calls.single.queryParameters['q'], 'chicken broth');
      // No sort_by: Search-a-licious only ranks by relevance when nothing
      // overrides it, and sort_by replaces relevance rather than tie-breaking
      // it — forcing popularity order buried an exact match for a less
      // globally popular query ("96/4 Ground Beef") past the first page.
      expect(calls.single.queryParameters.containsKey('sort_by'), isFalse);
    });

    test('a brand list is read as well as a brand string', () async {
      // Search sends brands as a list; stringifying it produced "[Heinz]".
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'hits': <Object?>[
          <String, Object?>{
            ...product(name: 'Chicken broth'),
            'brands': <String>['Swanson', 'Campbell'],
          },
        ],
      });

      expect((await off.search('broth')).single.food.brand, 'Swanson');
    });

    test('an empty query is never sent anywhere', () async {
      final List<Uri> calls = <Uri>[];
      final OpenFoodFactsSource off = sourceReturning(<String, Object?>{
        'hits': <Object?>[],
      }, recordInto: calls);

      expect(await off.search('   '), isEmpty);
      expect(calls, isEmpty);
    });
  });
}

/// Stands in for a network failure without importing dart:io into a test that
/// otherwise has no need of it.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
