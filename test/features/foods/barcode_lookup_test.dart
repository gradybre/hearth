import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/barcode_lookup_controller.dart';

/// A source that answers for exactly the barcodes it was given.
class StubSource implements NutritionSource {
  StubSource(this.known, {this.name = 'Stub'});

  final Map<String, NutritionMatch> known;
  final String name;
  final List<String> asked = <String>[];

  @override
  String get displayName => name;

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    asked.add(barcode);
    return known[barcode];
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      const <NutritionMatch>[];
}

NutritionMatch aMatch(String name, {double confidence = 1}) => NutritionMatch(
  food: Food(
    id: 'f',
    name: name,
    source: FoodSource.openFoodFacts,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 's',
        label: '100 g',
        amount: Quantity.of(100, Units.gram),
        macros: const Macros(kcal: 100),
      ),
    ],
  ),
  source: FoodSource.openFoodFacts,
  confidence: confidence,
);

ProviderContainer containerWith(NutritionLookup lookup) {
  final ProviderContainer container = ProviderContainer(
    overrides: [nutritionLookupProvider.overrideWithValue(lookup)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('a barcode that is found', () {
    test('ends as a match the review screen can show', () async {
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[
          StubSource(<String, NutritionMatch>{
            '5000157024671': aMatch('Baked beans'),
          }),
        ]),
      );

      await container
          .read(barcodeLookupProvider.notifier)
          .lookUp('5000157024671');

      final BarcodeLookupState state = container.read(barcodeLookupProvider);
      expect(state, isA<BarcodeFound>());
      expect((state as BarcodeFound).match.food.name, 'Baked beans');
    });
  });

  group('a barcode that is not', () {
    test('is a miss carrying the number, not an error', () async {
      // The manual-entry path: the new food gets attached to this barcode and
      // is found first next time (§5.5).
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[
          StubSource(const <String, NutritionMatch>{}),
        ]),
      );

      await container
          .read(barcodeLookupProvider.notifier)
          .lookUp('5000157024671');

      final BarcodeLookupState state = container.read(barcodeLookupProvider);
      expect(state, isA<BarcodeMissing>());
      expect((state as BarcodeMissing).barcode, '5000157024671');
    });

    test(
      'something that is not a product code is said so, not looked up',
      () async {
        // A QR code off a menu, or a mistyped number. Three fruitless round
        // trips to discover that is three too many.
        final StubSource source = StubSource(const <String, NutritionMatch>{});
        final ProviderContainer container = containerWith(
          NutritionLookup(<NutritionSource>[source]),
        );

        await container
            .read(barcodeLookupProvider.notifier)
            .lookUp('https://example.com/menu');

        expect(
          container.read(barcodeLookupProvider),
          isA<BarcodeNotAProduct>(),
        );
        expect(source.asked, isEmpty);
      },
    );

    test('an empty scan does nothing at all', () async {
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[
          StubSource(const <String, NutritionMatch>{}),
        ]),
      );

      await container.read(barcodeLookupProvider.notifier).lookUp('   ');
      expect(container.read(barcodeLookupProvider), isA<BarcodeIdle>());
    });
  });

  group('a UPC and its EAN-13 are the same product', () {
    test('a 12-digit code is also tried with the leading zero', () async {
      // Open Food Facts stores EAN-13; USDA GTINs are usually 12-digit UPC.
      // Trying only what the camera read misses half the shelf.
      final StubSource source = StubSource(<String, NutritionMatch>{
        '0048707820026': aMatch('Cheddar'),
      });
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[source]),
      );

      await container
          .read(barcodeLookupProvider.notifier)
          .lookUp('048707820026');

      expect(container.read(barcodeLookupProvider), isA<BarcodeFound>());
      expect(source.asked, <String>['048707820026', '0048707820026']);
    });

    test('and a padded 13-digit code without it', () async {
      final StubSource source = StubSource(<String, NutritionMatch>{
        '048707820026': aMatch('Cheddar'),
      });
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[source]),
      );

      await container
          .read(barcodeLookupProvider.notifier)
          .lookUp('0048707820026');

      expect(container.read(barcodeLookupProvider), isA<BarcodeFound>());
    });

    test(
      'every source is asked before the next variant is given up on',
      () async {
        // Order matters: the household's own library must answer for a variant
        // before the internet is asked for any of them.
        final StubSource library = StubSource(<String, NutritionMatch>{
          '0048707820026': aMatch('Mine'),
        }, name: 'Your library');
        final StubSource off = StubSource(<String, NutritionMatch>{
          '048707820026': aMatch('Theirs'),
        }, name: 'Open Food Facts');
        final ProviderContainer container = containerWith(
          NutritionLookup(<NutritionSource>[library, off]),
        );

        await container
            .read(barcodeLookupProvider.notifier)
            .lookUp('048707820026');

        final BarcodeLookupState state = container.read(barcodeLookupProvider);
        expect((state as BarcodeFound).match.food.name, 'Mine');
        expect(off.asked, isEmpty);
      },
    );
  });

  group('scanning again while a lookup is in flight', () {
    test('the older answer never overwrites the newer scan', () async {
      // Pointing a camera at a shelf fires repeatedly; a slow first lookup
      // landing last would show the wrong food for the barcode on screen.
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[
          StubSource(<String, NutritionMatch>{
            '5000157024671': aMatch('First'),
            '0048707820026': aMatch('Second'),
          }),
        ]),
      );

      final BarcodeLookupController controller = container.read(
        barcodeLookupProvider.notifier,
      );

      final Future<void> first = controller.lookUp('5000157024671');
      final Future<void> second = controller.lookUp('0048707820026');
      await Future.wait(<Future<void>>[first, second]);

      final BarcodeLookupState state = container.read(barcodeLookupProvider);
      expect((state as BarcodeFound).match.food.name, 'Second');
    });
  });

  group('starting over', () {
    test('reset clears the result', () async {
      final ProviderContainer container = containerWith(
        NutritionLookup(<NutritionSource>[
          StubSource(<String, NutritionMatch>{
            '5000157024671': aMatch('Baked beans'),
          }),
        ]),
      );

      final BarcodeLookupController controller = container.read(
        barcodeLookupProvider.notifier,
      );
      await controller.lookUp('5000157024671');
      controller.reset();

      expect(container.read(barcodeLookupProvider), isA<BarcodeIdle>());
    });
  });
}
