import 'package:drift/drift.dart';

import 'hearth_database.dart';

/// A cookbook as the app reads it — the row plus its recipe ids.
class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.recipeIds,
  });

  final String id;
  final String name;
  final int sortOrder;
  final Set<String> recipeIds;

  int get size => recipeIds.length;
}

/// Local reads and writes for favourites and collections (spec §5.2).
///
/// Favourites are keyed by user and collections by household, matching the
/// scoping split in §8.2 — the tables are shaped so a query written against
/// the wrong scope does not compile rather than quietly leaking a partner's
/// hearts into your library.
class CollectionStore {
  CollectionStore(this._db);

  final HearthDatabase _db;

  // ── Favourites (user-scoped) ──────────────────────────────────────────────

  Future<Set<String>> favoriteIds({required String userId}) async {
    final List<RecipeFavoriteRow> rows = await (_db.select(
      _db.recipeFavorites,
    )..where(($RecipeFavoritesTable f) => f.userId.equals(userId))).get();
    return <String>{for (final RecipeFavoriteRow row in rows) row.recipeId};
  }

  Stream<Set<String>> watchFavoriteIds({required String userId}) =>
      (_db.select(_db.recipeFavorites)
            ..where(($RecipeFavoritesTable f) => f.userId.equals(userId)))
          .watch()
          .map(
            (List<RecipeFavoriteRow> rows) => <String>{
              for (final RecipeFavoriteRow row in rows) row.recipeId,
            },
          );

  /// Adds the favourite. Idempotent — the pair is the primary key, so a double
  /// tap replaces rather than duplicates.
  Future<void> addFavorite({
    required String userId,
    required String recipeId,
    required DateTime at,
  }) => _db
      .into(_db.recipeFavorites)
      .insertOnConflictUpdate(
        RecipeFavoriteRow(userId: userId, recipeId: recipeId, createdAt: at),
      );

  Future<void> removeFavorite({
    required String userId,
    required String recipeId,
  }) =>
      (_db.delete(_db.recipeFavorites)..where(
            ($RecipeFavoritesTable f) =>
                f.userId.equals(userId) & f.recipeId.equals(recipeId),
          ))
          .go();

  // ── Collections (household-scoped) ────────────────────────────────────────

  Future<List<CollectionSummary>> collections({
    required String householdId,
  }) async {
    final List<CollectionRow> rows =
        await (_db.select(_db.collections)
              ..where(
                ($CollectionsTable c) => c.householdId.equals(householdId),
              )
              ..orderBy(<OrderClauseGenerator<$CollectionsTable>>[
                ($CollectionsTable c) => OrderingTerm.asc(c.sortOrder),
                ($CollectionsTable c) => OrderingTerm.asc(c.name),
              ]))
            .get();
    return _withMembers(rows);
  }

  Stream<List<CollectionSummary>> watchCollections({
    required String householdId,
  }) =>
      // Membership changes have to move the list too — adding a recipe to a
      // cookbook changes what the cookbook chip means even though no
      // collection row was touched.
      _db
          .select(_db.collections)
          .watch()
          .asyncMap((_) => collections(householdId: householdId));

  Future<List<CollectionSummary>> _withMembers(List<CollectionRow> rows) async {
    if (rows.isEmpty) return const <CollectionSummary>[];
    final List<RecipeCollectionRow> links =
        await (_db.select(_db.recipeCollections)..where(
              ($RecipeCollectionsTable rc) => rc.collectionId.isIn(<String>[
                for (final CollectionRow row in rows) row.id,
              ]),
            ))
            .get();

    final Map<String, Set<String>> byCollection = <String, Set<String>>{};
    for (final RecipeCollectionRow link in links) {
      byCollection
          .putIfAbsent(link.collectionId, () => <String>{})
          .add(link.recipeId);
    }

    return <CollectionSummary>[
      for (final CollectionRow row in rows)
        CollectionSummary(
          id: row.id,
          name: row.name,
          sortOrder: row.sortOrder,
          recipeIds: byCollection[row.id] ?? const <String>{},
        ),
    ];
  }

  Future<void> upsertCollection({
    required String id,
    required String householdId,
    required String name,
    required int sortOrder,
    required DateTime updatedAt,
  }) => _db
      .into(_db.collections)
      .insertOnConflictUpdate(
        CollectionRow(
          id: id,
          householdId: householdId,
          name: name,
          sortOrder: sortOrder,
          updatedAt: updatedAt,
        ),
      );

  /// Removes the cookbook outright.
  ///
  /// Unlike recipes and foods this is a real delete: a collection holds no
  /// history, so nothing logged can be left dangling by its removal. The
  /// recipes inside it are untouched.
  Future<void> deleteCollection(String id) => (_db.delete(
    _db.collections,
  )..where(($CollectionsTable c) => c.id.equals(id))).go();

  /// Every collection id a recipe belongs to.
  Future<Set<String>> collectionsOf(String recipeId) async {
    final List<RecipeCollectionRow> rows =
        await (_db.select(_db.recipeCollections)..where(
              ($RecipeCollectionsTable rc) => rc.recipeId.equals(recipeId),
            ))
            .get();
    return <String>{
      for (final RecipeCollectionRow row in rows) row.collectionId,
    };
  }

  /// The whole membership map, for filtering the library in one pass.
  Future<Map<String, Set<String>>> membership() async {
    final List<RecipeCollectionRow> rows = await _db
        .select(_db.recipeCollections)
        .get();
    final Map<String, Set<String>> byRecipe = <String, Set<String>>{};
    for (final RecipeCollectionRow row in rows) {
      byRecipe
          .putIfAbsent(row.recipeId, () => <String>{})
          .add(row.collectionId);
    }
    return byRecipe;
  }

  Stream<Map<String, Set<String>>> watchMembership() =>
      _db.select(_db.recipeCollections).watch().asyncMap((_) => membership());

  Future<void> addToCollection({
    required String collectionId,
    required String recipeId,
    required DateTime at,
  }) => _db
      .into(_db.recipeCollections)
      .insertOnConflictUpdate(
        RecipeCollectionRow(
          collectionId: collectionId,
          recipeId: recipeId,
          createdAt: at,
        ),
      );

  Future<void> removeFromCollection({
    required String collectionId,
    required String recipeId,
  }) =>
      (_db.delete(_db.recipeCollections)..where(
            ($RecipeCollectionsTable rc) =>
                rc.collectionId.equals(collectionId) &
                rc.recipeId.equals(recipeId),
          ))
          .go();
}
