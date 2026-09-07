import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';

/// Forgetting a wording has to reach the row that holds it (spec §5.3).
///
/// `ingredient_matches` is unique on (household_id, ingredient_string), and
/// its upsert deliberately resolves on that pair rather than on the id —
/// because a row written by an older build carries a random id rather than
/// the derived one. The delete did not: it filtered on the id, so forgetting
/// a wording whose server row predates the derived id matched no rows at all.
/// The write succeeded, the queue cleared, and the answer stayed on the
/// partner's phone, still answering.
void main() {
  test('a forgotten wording is found by the pair, not by the id', () {
    expect(
      SupabaseRemoteGateway.deleteKeys['ingredient_matches'],
      <String>['household_id', 'ingredient_string'],
      reason:
          'filtering on the id misses a row written before the id was '
          'derived, and the deletion is lost without a word',
    );
  });

  test('and it is the same pair the upsert resolves on', () {
    // Two different answers to "which row is this?" is how the row a write
    // updates stops being the row a delete removes.
    expect(
      SupabaseRemoteGateway.upsertConflictTargets['ingredient_matches'],
      SupabaseRemoteGateway.deleteKeys['ingredient_matches']!.join(','),
    );
  });

  group('and paging does not move because of it', () {
    // `pageOrderFor` used to read `deleteKeys`, so adding an entry there
    // would silently re-sort a table's pull. Keyset paging needs a
    // deterministic order ending in something unique, and `(updated_at, id)`
    // is the one where a row written mid-pull sorts to the end rather than
    // shifting a boundary under rows already read (#18).
    test('ingredient matches still page by when they changed', () {
      expect(SupabaseRemoteGateway.pageOrderFor('ingredient_matches'), <String>[
        'updated_at',
        'id',
      ]);
    });

    test('and the join tables still page by their pair', () {
      // They carry no timestamp at all, so the pair is all they have.
      expect(SupabaseRemoteGateway.pageOrderFor('recipe_favorites'), <String>[
        'user_id',
        'recipe_id',
      ]);
      expect(SupabaseRemoteGateway.pageOrderFor('recipe_collections'), <String>[
        'collection_id',
        'recipe_id',
      ]);
    });
  });

  test('and the queued delete carries what that filter needs', () async {
    // The half that matters, and the half a map on its own cannot show: the
    // gateway refuses a delete whose key is missing rather than guessing,
    // so a filter naming columns the payload does not carry turns a silent
    // no-op into a loud failure — which is better, and still broken.
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);
    final PendingWriteStore queue = PendingWriteStore(db);

    await IngredientMatchRepository(
      database: db,
      store: IngredientMatchStore(db),
      queue: queue,
      householdId: 'house-1',
    ).forget('Extra-Virgin Olive Oil');

    final PendingWrite write = (await queue.pending()).single;
    expect(write.operation, WriteOperation.delete);

    for (final String column
        in SupabaseRemoteGateway.deleteKeys['ingredient_matches']!) {
      expect(
        write.payload[column],
        isNotNull,
        reason: 'the delete is filtered on $column and does not carry it',
      );
    }

    // Normalised, because that is what the column holds and what the unique
    // index is on — the wording as typed would match nothing.
    expect(write.payload['ingredient_string'], 'extra virgin olive oil');
  });
}
