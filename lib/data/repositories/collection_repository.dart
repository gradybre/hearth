import 'package:uuid/uuid.dart';

import '../local/collection_store.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';

/// Favourites and collections — the library's organisation (spec §5.2).
///
/// Both live here rather than on [RecipeRepository] because neither belongs to
/// a recipe: a favourite belongs to a *user* and a collection to a
/// *household*, and a recipe knows about neither. Keeping them apart is what
/// stops a recipe sync from carrying one user's hearts to the other's device.
class CollectionRepository {
  CollectionRepository({
    required HearthDatabase database,
    required CollectionStore store,
    required PendingWriteStore queue,
    required String householdId,
    required String userId,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _householdId = householdId,
       _userId = userId,
       _now = clock ?? DateTime.now,
       _newId = idFactory ?? const Uuid().v4;

  static const String favoritesTable = 'recipe_favorites';
  static const String collectionsTable = 'collections';
  static const String membershipTable = 'recipe_collections';

  final HearthDatabase _db;
  final CollectionStore _store;
  final PendingWriteStore _queue;
  final String _householdId;
  final String _userId;
  final DateTime Function() _now;
  final String Function() _newId;

  // ── Favourites ────────────────────────────────────────────────────────────

  Future<Set<String>> favoriteIds() => _store.favoriteIds(userId: _userId);

  Stream<Set<String>> watchFavoriteIds() =>
      _store.watchFavoriteIds(userId: _userId);

  /// Turns the heart on or off and returns the state it landed in.
  ///
  /// Returning the result rather than nothing lets the caller show the
  /// outcome without re-reading — a favourite tap should feel instant.
  Future<bool> toggleFavorite(String recipeId) async {
    final DateTime now = _now();
    final Set<String> current = await favoriteIds();
    final bool wanted = !current.contains(recipeId);

    await _db.transaction(() async {
      if (wanted) {
        await _store.addFavorite(userId: _userId, recipeId: recipeId, at: now);
      } else {
        await _store.removeFavorite(userId: _userId, recipeId: recipeId);
      }
      await _queue.enqueue(
        entityTable: favoritesTable,
        // These rows are keyed by the pair, not by an id column. The queue
        // needs one string, so the pair is joined — the payload still carries
        // the real columns for the remote write.
        entityId: '$_userId/$recipeId',
        operation: wanted ? WriteOperation.upsert : WriteOperation.delete,
        payload: <String, Object?>{
          'user_id': _userId,
          'recipe_id': recipeId,
          if (wanted) 'created_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });

    return wanted;
  }

  // ── Collections ───────────────────────────────────────────────────────────

  Future<List<CollectionSummary>> collections() =>
      _store.collections(householdId: _householdId);

  Stream<List<CollectionSummary>> watchCollections() =>
      _store.watchCollections(householdId: _householdId);

  Stream<Map<String, Set<String>>> watchMembership() =>
      _store.watchMembership();

  Future<Set<String>> collectionsOf(String recipeId) =>
      _store.collectionsOf(recipeId);

  /// Creates a cookbook and returns its id.
  Future<String> createCollection(String name, {int sortOrder = 0}) async {
    final String id = _newId();
    await renameCollection(id, name, sortOrder: sortOrder);
    return id;
  }

  /// Creates or renames — the same upsert either way, since a collection is
  /// only a name and a position.
  Future<void> renameCollection(
    String id,
    String name, {
    int sortOrder = 0,
  }) async {
    final DateTime now = _now();
    final String trimmed = name.trim();
    await _db.transaction(() async {
      await _store.upsertCollection(
        id: id,
        householdId: _householdId,
        name: trimmed,
        sortOrder: sortOrder,
        updatedAt: now,
      );
      await _queue.enqueue(
        entityTable: collectionsTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: <String, Object?>{
          'id': id,
          'household_id': _householdId,
          'name': trimmed,
          'sort_order': sortOrder,
          // A row that was deleted and is being written again — an undo,
          // a restore, the same name re-added — has to come back rather than
          // stay a tombstone (spec §7.1).
          'is_deleted': false,
          'updated_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });
  }

  /// Deletes the cookbook. The recipes in it are not touched.
  Future<void> deleteCollection(String id) async {
    final DateTime now = _now();
    await _db.transaction(() async {
      await _store.deleteCollection(id);
      await _queue.enqueue(
        entityTable: collectionsTable,
        entityId: id,
        operation: WriteOperation.delete,
        payload: <String, Object?>{
          'id': id,
          // Stated, not left to the server: the tombstone records the deleting
          // writer's own clock, so an Undo from this same device is always
          // newer than the deletion it undoes (spec §7.1).
          'updated_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });
  }

  /// Puts a recipe in a cookbook, or takes it out; returns whether it is in.
  Future<bool> toggleMembership({
    required String collectionId,
    required String recipeId,
  }) async {
    final DateTime now = _now();
    final Set<String> current = await collectionsOf(recipeId);
    final bool wanted = !current.contains(collectionId);

    await _db.transaction(() async {
      if (wanted) {
        await _store.addToCollection(
          collectionId: collectionId,
          recipeId: recipeId,
          at: now,
        );
      } else {
        await _store.removeFromCollection(
          collectionId: collectionId,
          recipeId: recipeId,
        );
      }
      await _queue.enqueue(
        entityTable: membershipTable,
        entityId: '$collectionId/$recipeId',
        operation: wanted ? WriteOperation.upsert : WriteOperation.delete,
        payload: <String, Object?>{
          'collection_id': collectionId,
          'recipe_id': recipeId,
          if (wanted) 'created_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });

    return wanted;
  }
}
