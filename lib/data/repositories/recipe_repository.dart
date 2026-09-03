import '../../domain/models/recipe.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
import '../local/recipe_store.dart';
import '../mappers/recipe_mapper.dart';

/// The only thing features talk to for recipes.
///
/// Reads come from the local cache so the library works with no network;
/// writes land locally *and* in the sync queue inside one transaction, so a
/// recipe can never appear on the device without also being scheduled to sync
/// (spec §7.1). Features never see Drift or Supabase.
class RecipeRepository {
  RecipeRepository({
    required HearthDatabase database,
    required RecipeStore store,
    required PendingWriteStore queue,
    required String householdId,
    DateTime Function()? clock,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _householdId = householdId,
       _now = clock ?? DateTime.now;

  /// The Supabase table these writes target.
  static const String entityTable = 'recipes';

  final HearthDatabase _db;
  final RecipeStore _store;
  final PendingWriteStore _queue;
  final String _householdId;
  final DateTime Function() _now;

  Future<List<Recipe>> all({bool includeDeleted = false}) =>
      _store.all(householdId: _householdId, includeDeleted: includeDeleted);

  Stream<List<Recipe>> watchAll({bool includeDeleted = false}) => _store
      .watchAll(householdId: _householdId, includeDeleted: includeDeleted);

  /// Reads one recipe by id, soft-deleted or not — a past log needs to resolve
  /// a recipe that has since been removed from the library (spec §4).
  Future<Recipe?> byId(String id) => _store.byId(id);

  /// Saves a recipe locally and queues it for sync.
  ///
  /// The household is always stamped, never taken from the caller: saving
  /// through this repository means "save into my household", and trusting an
  /// incoming value would let a bug write a row this user could not then read
  /// back through RLS. Records arriving from sync bypass this and go straight
  /// to the store.
  Future<void> save(Recipe recipe) {
    final DateTime now = _now();
    final Recipe owned = _withHousehold(recipe);

    return _db.transaction(() async {
      await _store.upsert(owned, updatedAt: now);
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: owned.id,
        operation: WriteOperation.upsert,
        payload: RecipeMapper.toJson(owned, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  /// Points a recipe at its photo in the household's bucket (spec §5.2).
  ///
  /// A separate method rather than part of [save] because the photo's object
  /// path is decided by the sync pass, not by anything the editor knows, and
  /// routing it through the editor would mean the screen holding a value it
  /// has no opinion about.
  ///
  /// Null clears it — the photo was removed.
  Future<void> setPhotoUrl(String id, String? path) {
    final DateTime now = _now();
    return _db.transaction(() async {
      final Recipe? recipe = await _store.byId(id);
      if (recipe == null) return;
      final Recipe owned = _withHousehold(
        recipe.copyWith(photoUrl: path, clearPhotoUrl: path == null),
      );
      await _store.upsert(owned, updatedAt: now);
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: RecipeMapper.toJson(owned, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  /// Hides a recipe and queues the change.
  ///
  /// This is a soft delete pushed as an ordinary update, never a row removal:
  /// physically deleting a recipe would strand every log that references it
  /// (spec §4).
  Future<void> delete(String id) {
    final DateTime now = _now();
    return _db.transaction(() async {
      await _store.softDelete(id, updatedAt: now);
      final Recipe? deleted = await _store.byId(id);
      if (deleted == null) return;
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: RecipeMapper.toJson(deleted, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  /// Undoes a [delete].
  ///
  /// A real restore, not a re-creation: the recipe was only ever hidden, so it
  /// comes back with the same id and every meal logged against it still
  /// resolves.
  Future<void> restore(String id) {
    final DateTime now = _now();
    return _db.transaction(() async {
      await _store.restore(id, updatedAt: now);
      final Recipe? restored = await _store.byId(id);
      if (restored == null) return;
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: RecipeMapper.toJson(restored, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  Recipe _withHousehold(Recipe recipe) => Recipe(
    id: recipe.id,
    title: recipe.title,
    servings: recipe.servings,
    sections: recipe.sections,
    householdId: _householdId,
    prepTime: recipe.prepTime,
    cookTime: recipe.cookTime,
    cuisine: recipe.cuisine,
    tags: recipe.tags,
    kind: recipe.kind,
    source: recipe.source,
    photoUrl: recipe.photoUrl,
    notes: recipe.notes,
    createdBy: recipe.createdBy,
    isDeleted: recipe.isDeleted,
    updatedAt: recipe.updatedAt,
  );
}
