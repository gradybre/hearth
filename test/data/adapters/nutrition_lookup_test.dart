import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

Food aFood({
  required String id,
  required String name,
  String? barcode,
  FoodSource source = FoodSource.manual,
}) => Food(
  id: id,
  name: name,
  barcode: barcode,
  source: source,
  servingOptions: <ServingOption>[
    ServingOption(
      id: '$id:100g',
      label: '100 g',
      amount: Quantity.of(100, Units.gram),
      macros: const Macros(kcal: 100),
    ),
  ],
);

class StubSource implements NutritionSource {
  StubSource(this.displayName, {this.barcodeHit, this.results = const []});

  @override
  final String displayName;

  final NutritionMatch? barcodeHit;
  final List<NutritionMatch> results;
  int barcodeCalls = 0;

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    barcodeCalls++;
    return barcodeHit;
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      results;
}

NutritionMatch match(Food food, {double confidence = 1}) =>
    NutritionMatch(food: food, source: food.source, confidence: confidence);

void main() {
  group('the chain stops at the first answer', () {
    test('the library wins, and nothing else is even asked', () async {
      // A food this household has already corrected must outrank a
      // stranger's version of it, and asking further could only produce a
      // worse answer.
      final StubSource library = StubSource(
        'Your library',
        barcodeHit: match(aFood(id: 'mine', name: 'My oats', barcode: '1')),
      );
      final StubSource off = StubSource(
        'Open Food Facts',
        barcodeHit: match(
          aFood(id: 'off:1', name: 'Their oats', barcode: '1'),
          confidence: 0.9,
        ),
      );

      final NutritionMatch? found = await NutritionLookup(<NutritionSource>[
        library,
        off,
      ]).byBarcode('1');

      expect(found!.food.name, 'My oats');
      expect(off.barcodeCalls, 0);
    });

    test('a library miss hands off to the next source', () async {
      final StubSource library = StubSource('Your library');
      final StubSource off = StubSource(
        'Open Food Facts',
        barcodeHit: match(aFood(id: 'off:1', name: 'Their oats', barcode: '1')),
      );

      final NutritionMatch? found = await NutritionLookup(<NutritionSource>[
        library,
        off,
      ]).byBarcode('1');

      expect(found!.food.name, 'Their oats');
      expect(library.barcodeCalls, 1);
    });

    test('nobody knowing it is null, not an error', () async {
      // The manual-entry path is a first-class outcome, not a failure.
      final NutritionLookup lookup = NutritionLookup(<NutritionSource>[
        StubSource('Your library'),
        StubSource('Open Food Facts'),
      ]);

      expect(await lookup.byBarcode('nope'), isNull);
    });
  });

  group('search gathers from everywhere', () {
    test('the household\'s own results come first', () async {
      final NutritionLookup lookup = NutritionLookup(<NutritionSource>[
        StubSource(
          'Your library',
          results: <NutritionMatch>[match(aFood(id: 'mine', name: 'Oats'))],
        ),
        StubSource(
          'Open Food Facts',
          results: <NutritionMatch>[match(aFood(id: 'off:9', name: 'Oats'))],
        ),
      ]);

      final List<NutritionMatch> results = await lookup.search('oats');
      expect(results.first.food.id, 'mine');
      expect(results, hasLength(2));
    });

    test('the same product from two sources is shown once', () async {
      // One thing to the person looking at it. The earlier — more trusted —
      // source is the one kept.
      final NutritionLookup lookup = NutritionLookup(<NutritionSource>[
        StubSource(
          'Your library',
          results: <NutritionMatch>[
            match(aFood(id: 'mine', name: 'My beans', barcode: '5')),
          ],
        ),
        StubSource(
          'Open Food Facts',
          results: <NutritionMatch>[
            match(aFood(id: 'off:5', name: 'Their beans', barcode: '5')),
          ],
        ),
      ]);

      final List<NutritionMatch> results = await lookup.search('beans');
      expect(results, hasLength(1));
      expect(results.single.food.name, 'My beans');
    });

    test('foods with no barcode are not collapsed together', () async {
      // Two hand-entered foods with no barcode are two different foods.
      final NutritionLookup lookup = NutritionLookup(<NutritionSource>[
        StubSource(
          'Your library',
          results: <NutritionMatch>[
            match(aFood(id: 'a', name: 'Porridge')),
            match(aFood(id: 'b', name: 'Porridge, made up')),
          ],
        ),
      ]);

      expect(await lookup.search('porridge'), hasLength(2));
    });

    test('the limit is honoured across sources, not per source', () async {
      final NutritionLookup lookup = NutritionLookup(<NutritionSource>[
        StubSource(
          'Your library',
          results: <NutritionMatch>[
            match(aFood(id: 'a', name: 'One')),
            match(aFood(id: 'b', name: 'Two')),
          ],
        ),
        StubSource(
          'Open Food Facts',
          results: <NutritionMatch>[match(aFood(id: 'c', name: 'Three'))],
        ),
      ]);

      expect(await lookup.search('x', limit: 2), hasLength(2));
    });
  });

  group('what a scan result says about itself', () {
    test('a miss carries the barcode, so it can be added by hand', () async {
      const BarcodeResult result = BarcodeResult.miss('5000157024671');

      expect(result.isMiss, isTrue);
      expect(result.barcode, '5000157024671');
      expect(result.needsReview, isFalse);
    });

    test('a doubtful hit asks to be looked at', () {
      final BarcodeResult result = BarcodeResult.found(
        '5',
        match(aFood(id: 'off:5', name: 'Mystery'), confidence: 0.4),
      );

      expect(result.isMiss, isFalse);
      expect(result.needsReview, isTrue);
    });

    test('a confident hit does not', () {
      final BarcodeResult result = BarcodeResult.found(
        '5',
        match(aFood(id: 'off:5', name: 'Baked beans')),
      );
      expect(result.needsReview, isFalse);
    });
  });
}
