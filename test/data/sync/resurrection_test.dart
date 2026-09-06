import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/collection_repository.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';

/// A deletion is not undone by a write that predates it (spec §7.1, R03).
///
/// The server holds that rule, in one trigger across all seven soft-deleting
/// tables. What the client owes it is a *stated time*: the tombstone records
/// the deleting writer's own clock, so that an Undo from the same device is
/// always newer than the deletion it undoes. A delete payload that says
/// nothing leaves the server comparing clocks that are not comparable.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>?> deletePayloadFor(String table) async {
    for (final PendingWrite write in await queue.pending()) {
      if (write.entityTable == table &&
          write.operation == WriteOperation.delete) {
        return write.payload;
      }
    }
    return null;
  }

  test('a queued deletion says when it was made', () async {
    final CollectionRepository collections = CollectionRepository(
      database: db,
      store: CollectionStore(db),
      queue: queue,
      householdId: 'house-1',
      userId: 'user-1',
    );
    final String id = await collections.createCollection('Weeknights');
    await collections.deleteCollection(id);

    final IngredientMatchRepository matches = IngredientMatchRepository(
      database: db,
      store: IngredientMatchStore(db),
      queue: queue,
      householdId: 'house-1',
    );
    await matches.rememberNoMatch('olive oil');
    await matches.forget('olive oil');

    for (final String table in <String>['collections', 'ingredient_matches']) {
      final Map<String, Object?>? payload = await deletePayloadFor(table);
      expect(payload, isNotNull, reason: '$table queued no deletion');
      expect(
        payload!['updated_at'],
        isNotNull,
        reason:
            "$table's deletion states no time, so the tombstone cannot "
            'record one and Undo has nothing to be newer than',
      );
      // And in UTC, like every other timestamp this app sends (N02).
      expect(payload['updated_at'], endsWith('Z'));
    }
  });
}
