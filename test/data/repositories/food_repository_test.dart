import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late FoodRepository repository;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = FoodRepository(
      database: db,
      store: FoodStore(db),
      queue: queue,
      householdId: 'household-1',
      clock: () => DateTime.utc(2026, 8, 27, 12),
    );
  });

  tearDown(() => db.close());

  Food yogurt({String id = 'food-yogurt'}) => aFood(
    'Greek yogurt',
    id: id,
    servingOptions: <ServingOption>[
      aServing(
        id: '$id-serving',
        amount: 170,
        unit: Units.gram,
        label: '1 container',
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  group('saving', () {
    test('a saved food is searchable immediately, with no network', () async {
      await repository.save(yogurt());
      expect((await repository.search('greek')).single.name, 'Greek yogurt');
    });

    test('every save is queued for sync', () async {
      await repository.save(yogurt());

      final PendingWrite write = (await queue.pending()).single;
      expect(write.entityTable, 'foods');
      expect(write.entityId, 'food-yogurt');
      expect(write.operation, WriteOperation.upsert);
    });

    test('the queued payload carries the serving options', () async {
      await repository.save(yogurt());
      final Map<String, Object?> payload =
          (await queue.pending()).single.payload;

      final List<Object?> servings =
          payload['serving_options']! as List<Object?>;
      expect(servings, hasLength(1));

      final Map<String, Object?> serving =
          servings.single as Map<String, Object?>;
      expect(serving['label'], '1 container');
      expect(serving['kcal'], 100);
      expect(serving['amount_kind'], 'mass');
    });

    test('the household is stamped, not taken from the caller', () async {
      await repository.save(
        aFood('Sneaky', id: 'food-x').withHousehold('someone-elses-household'),
      );
      final Map<String, Object?> payload =
          (await queue.pending()).single.payload;

      expect(payload['household_id'], 'household-1');
      expect(await repository.byId('food-x'), isNotNull);
    });
  });

  group('deleting', () {
    test('is soft, and the food stays resolvable by id', () async {
      await repository.save(yogurt());
      await repository.delete('food-yogurt');

      expect(await repository.all(), isEmpty);
      // A past log referencing this food must still resolve (spec §4).
      final Food? deleted = await repository.byId('food-yogurt');
      expect(deleted!.isDeleted, isTrue);
    });

    test('is queued as an update, never a row removal', () async {
      await repository.save(yogurt());
      await repository.delete('food-yogurt');

      final PendingWrite write = (await queue.pending()).single;
      expect(write.operation, WriteOperation.upsert);
      expect(write.payload['is_deleted'], isTrue);
    });
  });

  test('duplicate detection reaches the store (spec §5.5)', () async {
    await repository.save(yogurt());
    final List<Food> duplicates = await repository.likelyDuplicatesOf(
      aFood('greek yogurt', id: 'food-new'),
    );
    expect(duplicates.single.id, 'food-yogurt');
  });
}
