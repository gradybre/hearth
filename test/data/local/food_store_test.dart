import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/food_mapper.dart';
import 'package:hearth/data/mappers/sync_payload.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late FoodStore store;
  final DateTime now = DateTime.utc(2026, 8, 27, 12);
  const String household = 'household-1';

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = FoodStore(db);
  });

  tearDown(() => db.close());

  Food chicken({String id = 'food-chicken', String name = 'Chicken breast'}) =>
      aFood(
        name,
        id: id,
        servingOptions: <ServingOption>[
          aServing(
            id: '$id-100g',
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 165, proteinG: 31, fatG: 3.6),
          ),
          aServing(
            id: '$id-breast',
            amount: 1,
            unit: Units.item,
            label: '1 breast',
            macros: const Macros(kcal: 284, proteinG: 53, fatG: 6.2),
          ),
        ],
      ).withHousehold(household);

  group('round trip', () {
    test('a food and its serving options survive a save and reload', () async {
      await store.upsert(chicken(), updatedAt: now);
      final Food? loaded = await store.byId('food-chicken');

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Chicken breast');
      expect(loaded.servingOptions, hasLength(2));
      expect(loaded.servingOptions.first.macros.kcal, 165);
      expect(
        loaded.servingOptions.first.amount.amountIn(Units.gram),
        closeTo(100, 1e-9),
      );
    });

    test('a reloaded food carries the timestamp it was written with', () async {
      // The sort on the Foods tab is only as good as this: `updatedAt` lives
      // on the row and is easy to write without ever reading back, which is
      // exactly how it behaved before the library gained a recency sort.
      //
      // Compared as an instant, not with ==: Drift stores the epoch and hands
      // it back in local time, and DateTime equality also demands a matching
      // UTC flag. Sorting compares instants, so the difference is real here
      // and irrelevant there.
      await store.upsert(chicken(), updatedAt: now);

      expect(
        (await store.byId('food-chicken'))!.updatedAt!.isAtSameMomentAs(now),
        isTrue,
      );
    });

    test('a food marked default comes back marked', () async {
      // The mark travels through the domain model, the row, and three
      // mappers, every one of which restates every field. `updatedAt` was
      // silently dropped by exactly that shape of code, and nothing noticed
      // until a sort came to depend on it.
      await store.upsert(chicken().asDefault(), updatedAt: now);
      expect((await store.byId('food-chicken'))!.isDefault, isTrue);
    });

    test('and a food that is not marked stays unmarked', () async {
      await store.upsert(chicken(), updatedAt: now);
      expect((await store.byId('food-chicken'))!.isDefault, isFalse);
    });

    test('unmarking one sticks', () async {
      await store.upsert(chicken().asDefault(), updatedAt: now);
      await store.upsert(chicken(), updatedAt: now);
      expect((await store.byId('food-chicken'))!.isDefault, isFalse);
    });

    test('a food confirmed as genuinely zero comes back confirmed', () async {
      // Same trail as isDefault: the domain model, the row, and three mappers
      // that each restate every field. `updatedAt` was silently dropped by
      // exactly that shape of code.
      await store.upsert(chicken().asZeroCalorie(), updatedAt: now);
      expect((await store.byId('food-chicken'))!.isZeroCalorie, isTrue);
    });

    test('and one that is not stays unconfirmed', () async {
      await store.upsert(chicken(), updatedAt: now);
      expect((await store.byId('food-chicken'))!.isZeroCalorie, isFalse);
    });

    test('serving option order is preserved', () async {
      await store.upsert(chicken(), updatedAt: now);
      final Food loaded = (await store.byId('food-chicken'))!;
      expect(loaded.servingOptions.map((ServingOption s) => s.label), <String>[
        '100 g',
        '1 breast',
      ]);
      expect(loaded.defaultServing!.label, '100 g');
    });

    test('replacing a food drops serving options the edit removed', () async {
      await store.upsert(chicken(), updatedAt: now);
      await store.upsert(
        aFood(
          'Chicken breast',
          id: 'food-chicken',
          servingOptions: <ServingOption>[
            aServing(
              id: 'food-chicken-100g',
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 165),
            ),
          ],
        ).withHousehold(household),
        updatedAt: now,
      );

      final Food loaded = (await store.byId('food-chicken'))!;
      expect(loaded.servingOptions, hasLength(1));
    });
  });

  group('scoping', () {
    test('household foods and the global catalogue are both visible', () async {
      await store.upsert(chicken(), updatedAt: now);
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'global-rice',
              name: 'White rice',
              updatedAt: now,
            ),
          );

      final List<Food> all = await store.all(householdId: household);
      expect(
        all.map((Food f) => f.id),
        containsAll(<String>['food-chicken', 'global-rice']),
      );
      expect(
        all.firstWhere((Food f) => f.id == 'global-rice').isGlobal,
        isTrue,
      );
    });

    test('another household is never visible', () async {
      await store.upsert(
        chicken().withHousehold('someone-else'),
        updatedAt: now,
      );
      expect(await store.all(householdId: household), isEmpty);
    });

    test('soft-deleted foods are hidden but still resolvable', () async {
      await store.upsert(chicken(), updatedAt: now);
      await store.softDelete('food-chicken', updatedAt: now);

      expect(await store.all(householdId: household), isEmpty);
      // A past log referencing this food must still resolve (spec §4).
      expect((await store.byId('food-chicken'))!.isDeleted, isTrue);
    });
  });

  group('search', () {
    setUp(() async {
      await store.upsert(chicken(), updatedAt: now);
      await store.upsert(
        aFood(
          'Greek yogurt',
          id: 'food-yogurt',
        ).withHousehold(household).withBrand('Fage'),
        updatedAt: now,
      );
    });

    test('matches on name, case and punctuation insensitively', () async {
      final List<Food> results = await store.search(
        'CHICKEN',
        householdId: household,
      );
      expect(results.single.id, 'food-chicken');
    });

    test('matches on brand', () async {
      final List<Food> results = await store.search(
        'fage',
        householdId: household,
      );
      expect(results.single.id, 'food-yogurt');
    });

    test('an empty query returns the library', () async {
      expect(await store.search('', householdId: household), hasLength(2));
    });

    test('no match returns nothing rather than everything', () async {
      expect(await store.search('rutabaga', householdId: household), isEmpty);
    });
  });

  group('duplicate detection (spec §5.5)', () {
    test('flags an identical name', () async {
      await store.upsert(chicken(), updatedAt: now);
      final List<Food> duplicates = await store.likelyDuplicatesOf(
        aFood('chicken breast', id: 'new-food').withHousehold(household),
        householdId: household,
      );
      expect(duplicates.single.id, 'food-chicken');
    });

    test('flags a shared barcode even when names differ', () async {
      await store.upsert(chicken().withBarcode('0123456789'), updatedAt: now);
      final List<Food> duplicates = await store.likelyDuplicatesOf(
        aFood(
          'Something else entirely',
          id: 'new-food',
        ).withHousehold(household).withBarcode('0123456789'),
        householdId: household,
      );
      expect(duplicates, hasLength(1));
    });

    test('never flags the food against itself', () async {
      await store.upsert(chicken(), updatedAt: now);
      expect(
        await store.likelyDuplicatesOf(chicken(), householdId: household),
        isEmpty,
      );
    });

    test('a distinct food is not flagged', () async {
      await store.upsert(chicken(), updatedAt: now);
      expect(
        await store.likelyDuplicatesOf(
          aFood('Greek yogurt', id: 'new-food').withHousehold(household),
          householdId: household,
        ),
        isEmpty,
      );
    });
  });

  group('the Walmart product a food is bought as (spec §5.7)', () {
    Food withProduct() => Food(
      id: 'food-walmart',
      householdId: 'household-1',
      name: 'Ground beef',
      source: FoodSource.manual,
      servingOptions: const <ServingOption>[],
      walmartItemId: '10450479',
      packSize: Quantity.of(1, Units.pound),
    );

    test('survives a save and a read back', () async {
      await store.upsert(withProduct(), updatedAt: DateTime.utc(2026));

      final Food back = (await store.byId('food-walmart'))!;
      expect(back.walmartItemId, '10450479');
      expect(back.packSize, Quantity.of(1, Units.pound));
    });

    test('and through the wire in both directions', () async {
      // The two halves of the mapper drifting apart is how a column goes
      // quietly missing, so the payload is read straight back.
      final Map<String, Object?> json = FoodMapper.toJson(
        withProduct(),
        updatedAt: DateTime.utc(2026),
      );
      expect(json['walmart_item_id'], '10450479');
      expect(json['pack_unit'], 'lb');

      final Food back = SyncPayload.food(json);
      expect(back.walmartItemId, '10450479');
      expect(back.packSize, Quantity.of(1, Units.pound));
    });

    test('a food without one keeps null rather than an empty string', () async {
      await store.upsert(
        aFood('Plain').withHousehold('household-1'),
        updatedAt: DateTime.utc(2026),
      );

      final Food back = (await store.byId(
        (await store.all(householdId: 'household-1'))
            .firstWhere((Food f) => f.name == 'Plain')
            .id,
      ))!;
      expect(back.walmartItemId, isNull);
      expect(back.packSize, isNull);
    });
  });

  group('the three minor nutrients (spec §5.6)', () {
    Food withNutrients() => Food(
      id: 'food-oats',
      householdId: household,
      name: 'Oats',
      source: FoodSource.manual,
      servingOptions: <ServingOption>[
        aServing(
          id: 'serving-oats',
          amount: 100,
          unit: Units.gram,
          macros: const Macros(
            kcal: 380,
            proteinG: 13,
            carbG: 67,
            fatG: 7,
            fiberG: 10,
            sodiumMg: 2,
            cholesterolMg: 0,
          ),
        ),
      ],
    );

    test('survive a save and a read back, zero included', () async {
      await store.upsert(withNutrients(), updatedAt: DateTime.utc(2026));

      final Macros back = (await store.byId('food-oats'))!
          .servingOptions
          .single
          .macros;
      expect(back.fiberG, 10);
      expect(back.sodiumMg, 2);
      // A stated zero is a fact, and must not come back as "unknown".
      expect(back.cholesterolMg, 0);
    });

    test('and through the wire in both directions', () async {
      final Map<String, Object?> json = FoodMapper.toJson(
        withNutrients(),
        updatedAt: DateTime.utc(2026),
      );
      final List<Object?> servings = json['serving_options']! as List<Object?>;
      final Map<String, Object?> serving =
          servings.single! as Map<String, Object?>;
      expect(serving['fiber_g'], 10);
      expect(serving['sodium_mg'], 2);
      expect(serving['cholesterol_mg'], 0);

      final Macros back = SyncPayload.food(json).servingOptions.single.macros;
      expect(back.fiberG, 10);
      expect(back.cholesterolMg, 0);
    });

    test(
      'a payload from before these existed decodes as unknown, not zero',
      () {
        // The guard that matters most. Every food already in the hosted
        // database was written by a client that had never heard of fibre, and
        // reading those back as "0 g fibre" would put a wrong number on every
        // one of them (spec §5.6, and §4's frozen history by extension).
        final Map<String, Object?> json = FoodMapper.toJson(
          withNutrients(),
          updatedAt: DateTime.utc(2026),
        );
        final Map<String, Object?> serving =
            (json['serving_options']! as List<Object?>).single!
                as Map<String, Object?>;
        serving
          ..remove('fiber_g')
          ..remove('sodium_mg')
          ..remove('cholesterol_mg');

        final Macros back = SyncPayload.food(json).servingOptions.single.macros;
        expect(back.kcal, 380);
        expect(back.fiberG, isNull);
        expect(back.sodiumMg, isNull);
        expect(back.cholesterolMg, isNull);
      },
    );

    test('a food nobody asked about keeps all three null', () async {
      await store.upsert(
        aFood(
          'Plainer',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 100),
            ),
          ],
        ).withHousehold(household),
        updatedAt: DateTime.utc(2026),
      );

      final Food back = (await store.all(householdId: household))
          .firstWhere((Food f) => f.name == 'Plainer');
      expect(back.servingOptions.single.macros.fiberG, isNull);
      expect(back.servingOptions.single.macros.sodiumMg, isNull);
      expect(back.servingOptions.single.macros.cholesterolMg, isNull);
    });
  });

  group('where an item sits on a menu (spec §5.2)', () {
    Food menuItem() => const Food(
      id: 'food-chicken',
      householdId: household,
      name: 'Chicken',
      brand: 'Chipotle',
      source: FoodSource.restaurant,
      menuGroup: 'Proteins',
      menuOrder: 9,
      servingOptions: <ServingOption>[],
    );

    test('survives a save and a read back', () async {
      await store.upsert(menuItem(), updatedAt: DateTime.utc(2026));

      final Food back = (await store.byId('food-chicken'))!;
      expect(back.menuGroup, 'Proteins');
      expect(back.menuOrder, 9);
    });

    test('and through the wire in both directions', () async {
      final Map<String, Object?> json = FoodMapper.toJson(
        menuItem(),
        updatedAt: DateTime.utc(2026),
      );
      expect(json['menu_group'], 'Proteins');
      expect(json['menu_order'], 9);

      final Food back = SyncPayload.food(json);
      expect(back.menuGroup, 'Proteins');
      expect(back.menuOrder, 9);
    });

    test('a food off nobody\'s menu keeps both null', () async {
      await store.upsert(
        aFood('Ground beef').withHousehold(household),
        updatedAt: DateTime.utc(2026),
      );

      final Food back = (await store.all(householdId: household))
          .firstWhere((Food f) => f.name == 'Ground beef');
      expect(back.menuGroup, isNull);
      expect(back.menuOrder, isNull);
    });
  });
}
