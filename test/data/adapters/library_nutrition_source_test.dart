import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/library_nutrition_source.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// The scan-save-rescan loop, through the real database.
///
/// This is the wiring the app actually runs, not a stub of it: a barcode that
/// has been saved once must come back from the household's own library the
/// next time it is scanned, or every scan pays for a network round trip and a
/// second copy of a food the user already corrected.
void main() {
  late HearthDatabase db;
  late FoodStore store;
  late FoodRepository repository;
  late LibraryNutritionSource source;

  const String household = 'household-1';

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = FoodStore(db);
    repository = FoodRepository(
      database: db,
      store: store,
      queue: PendingWriteStore(db),
      householdId: household,
    );
    source = LibraryNutritionSource(store: store, householdId: household);
  });

  tearDown(() => db.close());

  Food beanz({String? barcode = '5000157024671'}) => Food(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Beanz in a rich tomato sauce',
    brand: 'Heinz',
    barcode: barcode,
    source: FoodSource.openFoodFacts,
    servingOptions: <ServingOption>[
      ServingOption(
        id: '22222222-2222-4222-8222-222222222222',
        label: '100 g',
        amount: Quantity.of(100, Units.gram),
        macros: const Macros(kcal: 79, proteinG: 4.7, carbG: 12.9, fatG: 0.2),
      ),
    ],
  );

  test('a saved barcode is found again by the household library', () async {
    await repository.save(beanz());

    final NutritionMatch? match = await source.byBarcode('5000157024671');

    expect(match, isNotNull);
    expect(match!.food.name, 'Beanz in a rich tomato sauce');
    // Certain, because this household attached this barcode itself.
    expect(match.confidence, 1);
  });

  test('says the answer came from the library, not where it began', () async {
    // A food saved from a lookup keeps Open Food Facts as its provenance for
    // life. Reading that as "the household does not have this" is what made
    // the scan screen offer to save a second copy of it.
    await repository.save(beanz());

    final NutritionMatch match = (await source.byBarcode('5000157024671'))!;

    expect(match.fromLibrary, isTrue);
    expect(match.source, FoodSource.openFoodFacts);
  });

  test('a food with no barcode is not matched by an empty scan', () async {
    await repository.save(beanz(barcode: null));

    expect(await source.byBarcode('5000157024671'), isNull);
  });
}
