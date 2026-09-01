import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';
import 'package:hearth/domain/foods/no_match_rule.dart';

import '../../support/fixtures.dart';

/// Remembered ingredient answers, shared across the household (spec §7.1).
///
/// "Evoo means olive oil" is a decision about a kitchen, not about a handset,
/// and until this existed it never left the phone it was made on.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late IngredientMatchRepository repository;
  final DateTime now = DateTime.utc(2026, 8, 31, 12);

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = IngredientMatchRepository(
      database: db,
      store: IngredientMatchStore(db),
      queue: queue,
      householdId: 'household-1',
      now: () => now,
    );
    await FoodStore(db)
        .upsert(aFood('Olive oil', id: 'food-oil'), updatedAt: now);
  });

  tearDown(() => db.close());

  Future<PendingWriteRow> onlyQueued() async {
    final List<PendingWriteRow> writes = await db
        .select(db.pendingWrites)
        .get();
    expect(writes, hasLength(1));
    return writes.single;
  }

  group('every answer is queued for the household', () {
    test('a food match', () async {
      await repository.remember(ingredientString: 'EVOO', foodId: 'food-oil');

      final PendingWriteRow write = await onlyQueued();
      expect(write.entityTable, 'ingredient_matches');
      expect(write.payload, contains('"food_id":"food-oil"'));
      expect(write.payload, contains('"household_id":"household-1"'));
      // The normalised key, because that is what the unique index is on and
      // what every reader looks a wording up by.
      expect(write.payload, contains('"ingredient_string":"evoo"'));
    });

    test('a seasoning', () async {
      await repository.rememberNoMatch('fish sauce');

      final PendingWriteRow write = await onlyQueued();
      expect(write.payload, contains('"needs_no_match":true'));
      expect(write.payload, contains('"food_id":null'));
    });

    test('and turning a built-in seasoning back off', () async {
      await repository.rememberNeedsMatch('water');

      final PendingWriteRow write = await onlyQueued();
      expect(write.payload, contains('"needs_no_match":false'));
      expect(write.payload, contains('"food_id":null'));
    });

    test('forgetting one is queued as a delete', () async {
      await repository.remember(ingredientString: 'evoo', foodId: 'food-oil');
      await repository.forget('evoo');

      final PendingWriteRow write = await onlyQueued();
      expect(write.operation, 'delete');
    });

    test('nothing is queued for a wording that is not one', () async {
      await repository.rememberNoMatch('   ');
      expect(await db.select(db.pendingWrites).get(), isEmpty);
    });
  });

  group('two phones deciding the same thing', () {
    test('land on the same row rather than two the index refuses', () async {
      // The id is derived from the household and the wording, so the other
      // phone's row *is* this row. A random id each would make two, and the
      // unique index would refuse whichever synced second — for ever.
      expect(
        IngredientMatchStore.idFor('household-1', 'EVOO'),
        IngredientMatchStore.idFor('household-1', 'evoo.'),
      );
      expect(
        IngredientMatchStore.idFor('household-1', 'evoo'),
        isNot(IngredientMatchStore.idFor('household-2', 'evoo')),
      );
    });

    test('and the queued id is that one', () async {
      await repository.remember(ingredientString: 'evoo', foodId: 'food-oil');
      expect(
        (await onlyQueued()).entityId,
        IngredientMatchStore.idFor('household-1', 'evoo'),
      );
    });
  });

  test('reads come back through the repository too', () async {
    await repository.remember(ingredientString: 'evoo', foodId: 'food-oil');
    await repository.rememberNoMatch('fish sauce');

    expect(await repository.allFor(), <String, String>{'evoo': 'food-oil'});
    final NoMatchRules rules = await repository.noMatchRules();
    expect(rules.covers('fish sauce'), isTrue);
  });
}
