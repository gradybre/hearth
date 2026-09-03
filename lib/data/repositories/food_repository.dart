import '../../domain/models/food.dart';
import '../local/food_store.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
import '../mappers/food_mapper.dart';

/// The only thing features talk to for foods.
///
/// Same shape as [RecipeRepository]: reads come from the local cache so the
/// library works offline, and writes land locally and in the sync queue inside
/// one transaction.
class FoodRepository {
  FoodRepository({
    required HearthDatabase database,
    required FoodStore store,
    required PendingWriteStore queue,
    required String householdId,
    DateTime Function()? clock,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _householdId = householdId,
       _now = clock ?? DateTime.now;

  static const String entityTable = 'foods';

  final HearthDatabase _db;
  final FoodStore _store;
  final PendingWriteStore _queue;
  final String _householdId;
  final DateTime Function() _now;

  Future<List<Food>> all({bool includeDeleted = false}) =>
      _store.all(householdId: _householdId, includeDeleted: includeDeleted);

  Stream<List<Food>> watchAll() => _store.watchAll(householdId: _householdId);

  Future<Food?> byId(String id) => _store.byId(id);

  Future<List<Food>> search(String query, {int limit = 50}) =>
      _store.search(query, householdId: _householdId, limit: limit);

  /// Foods that look like duplicates of [food] (spec §5.5).
  ///
  /// Surfaced as a soft warning with a merge option, never a block: two
  /// genuinely different foods can share a name.
  Future<List<Food>> likelyDuplicatesOf(Food food) =>
      _store.likelyDuplicatesOf(food, householdId: _householdId);

  /// Saves a food locally and queues it for sync.
  ///
  /// The household is stamped rather than trusted, for the same reason as
  /// recipes: a food written into another household would vanish behind RLS.
  /// Global foods (null household) are server-owned and never saved here.
  Future<void> save(Food food) {
    final DateTime now = _now();
    final Food owned = _withHousehold(food);

    return _db.transaction(() async {
      await _store.upsert(owned, updatedAt: now);
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: owned.id,
        operation: WriteOperation.upsert,
        payload: FoodMapper.toJson(owned, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  /// Soft-deletes a food and queues the change as an ordinary update.
  Future<void> delete(String id) {
    final DateTime now = _now();
    return _db.transaction(() async {
      await _store.softDelete(id, updatedAt: now);
      final Food? deleted = await _store.byId(id);
      if (deleted == null) return;
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: FoodMapper.toJson(deleted, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  /// Undoes a [delete].
  ///
  /// A real restore, not a re-creation: the food was only hidden, so it comes
  /// back with the same id and every meal logged against it still resolves.
  Future<void> restore(String id) {
    final DateTime now = _now();
    return _db.transaction(() async {
      await _store.restore(id, updatedAt: now);
      final Food? restored = await _store.byId(id);
      if (restored == null) return;
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: FoodMapper.toJson(restored, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  Food _withHousehold(Food food) => Food(
    id: food.id,
    name: food.name,
    servingOptions: food.servingOptions,
    source: food.source,
    householdId: _householdId,
    brand: food.brand,
    storeTag: food.storeTag,
    walmartItemId: food.walmartItemId,
    packSize: food.packSize,
    barcode: food.barcode,
    gramsPerMillilitre: food.gramsPerMillilitre,
    macrosOverridden: food.macrosOverridden,
    isDefault: food.isDefault,
    isZeroCalorie: food.isZeroCalorie,
    isDeleted: food.isDeleted,
    updatedAt: food.updatedAt,
  );
}
