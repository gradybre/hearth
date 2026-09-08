import '../../domain/foods/no_match_rule.dart';
import '../../domain/text/text_normaliser.dart';
import '../local/hearth_database.dart';
import '../local/ingredient_match_store.dart';
import '../local/pending_write_store.dart';

/// Remembered answers for an ingredient wording, shared across the household
/// (spec §5.3, §7.1).
///
/// The store writes locally; this is what makes the answer travel. Both phones
/// meet the same recipes, and "evoo means olive oil" is a decision about the
/// household's kitchen rather than about one device — so a correction made on
/// one is a correction made for both, exactly as recipes and foods already are.
///
/// The household id is stamped rather than trusted, for the same reason as
/// recipes and foods: a row written into another household would vanish behind
/// RLS the moment it reached the server, with nothing on screen to say why.
class IngredientMatchRepository {
  IngredientMatchRepository({
    required HearthDatabase database,
    required IngredientMatchStore store,
    required PendingWriteStore queue,
    required String householdId,
    DateTime Function()? now,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _householdId = householdId,
       _now = now ?? DateTime.now;

  static const String entityTable = 'ingredient_matches';

  final HearthDatabase _db;
  final IngredientMatchStore _store;
  final PendingWriteStore _queue;
  final String _householdId;
  final DateTime Function() _now;

  /// Points a wording at a food.
  Future<void> remember({
    required String ingredientString,
    required String foodId,
  }) => _write(
    ingredientString,
    (DateTime at) => _store.remember(
      householdId: _householdId,
      ingredientString: ingredientString,
      foodId: foodId,
      updatedAt: at,
    ),
    foodId: foodId,
    needsNoMatch: false,
  );

  /// Records that a wording needs no food at all — salt, a spice.
  Future<void> rememberNoMatch(String ingredientString) => _write(
    ingredientString,
    (DateTime at) => _store.rememberNoMatch(
      householdId: _householdId,
      ingredientString: ingredientString,
      updatedAt: at,
    ),
    needsNoMatch: true,
  );

  /// Records that a wording needs an ordinary match after all — how one of the
  /// seasonings Hearth ships knowing about is turned back off.
  Future<void> rememberNeedsMatch(String ingredientString) => _write(
    ingredientString,
    (DateTime at) => _store.rememberNeedsMatch(
      householdId: _householdId,
      ingredientString: ingredientString,
      updatedAt: at,
    ),
    needsNoMatch: false,
  );

  /// Drops the household's opinion about a wording entirely.
  Future<void> forget(String ingredientString) {
    final DateTime at = _now();
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return Future<void>.value();

    return _db.transaction(() async {
      await _store.forget(
        householdId: _householdId,
        ingredientString: ingredientString,
      );
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: IngredientMatchStore.idFor(_householdId, key),
        operation: WriteOperation.delete,
        payload: <String, Object?>{
          'id': IngredientMatchStore.idFor(_householdId, key),
          // The pair the delete is filtered on, because the id alone misses a
          // row written before the id was derived — and the gateway refuses a
          // delete whose key is missing rather than matching every row it is
          // allowed to see.
          'household_id': _householdId,
          'ingredient_string': key,
          // Stated, not left to the server: the tombstone records the deleting
          // writer's own clock, so an Undo from this same device is always
          // newer than the deletion it undoes (spec §7.1).
          'updated_at': at.toUtc().toIso8601String(),
        },
        queuedAt: at,
      );
    });
  }

  Future<Map<String, String>> allFor() => _store.allFor(_householdId);

  Future<NoMatchRules> noMatchRules() => _store.noMatchRules(_householdId);

  Future<void> _write(
    String ingredientString,
    Future<void> Function(DateTime at) local, {
    String? foodId,
    required bool needsNoMatch,
  }) {
    final DateTime at = _now();
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return Future<void>.value();

    return _db.transaction(() async {
      await local(at);
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: IngredientMatchStore.idFor(_householdId, key),
        operation: WriteOperation.upsert,
        payload: <String, Object?>{
          'id': IngredientMatchStore.idFor(_householdId, key),
          'household_id': _householdId,
          // The normalised key, not what was typed: it is what the unique
          // index is on, and what every reader looks a wording up by.
          'ingredient_string': key,
          'food_id': foodId,
          'needs_no_match': needsNoMatch,
          // Explicit, because this table's upsert resolves on the unique
          // index rather than the id: answering the same wording again has
          // to revive the row already sitting on that name, not be refused
          // by it (spec §7.1).
          'is_deleted': false,
          'updated_at': at.toUtc().toIso8601String(),
        },
        queuedAt: at,
      );
    });
  }
}
