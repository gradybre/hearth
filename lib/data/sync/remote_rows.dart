import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/hearth_database.dart';

/// Writes records that arrived from the server straight into the local cache.
///
/// Deliberately row-level rather than domain-level. These tables carry values
/// this device must not reinterpret — above all `macro_snapshot`, which is
/// frozen history: what the meal was when it was logged, never what the recipe
/// says today (spec §4). Round-tripping it through the domain would invite
/// exactly the recomputation that rule forbids, so the stored text is copied
/// across verbatim.
class RemoteRows {
  RemoteRows(this._db);

  final HearthDatabase _db;

  // ── Timestamped records, resolved by last-write-wins ──────────────────────

  Future<DateTime?> updatedAtFor(String table, String id) async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'select updated_at from $table where id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.read<DateTime?>('updated_at');
  }

  Future<void> applyDay(Map<String, Object?> json) => _db
      .into(_db.mealPlanDays)
      .insertOnConflictUpdate(
        MealPlanDayRow(
          id: '${json['id']}',
          userId: '${json['user_id']}',
          day: _date(json['day']),
          notes: json['notes'] as String?,
          updatedAt: _time(json['updated_at']),
        ),
      );

  Future<void> applyEntry(Map<String, Object?> json) => _db
      .into(_db.mealPlanEntries)
      .insertOnConflictUpdate(
        MealPlanEntryRow(
          id: '${json['id']}',
          dayId: '${json['meal_plan_day_id']}',
          mealSlot: '${json['meal_slot']}',
          refType: '${json['ref_type']}',
          refId: '${json['ref_id']}',
          servings: _double(json['servings']) ?? 0,
          isPlanned: json['is_planned'] == true,
          isLogged: json['is_logged'] == true,
          loggedAt: json['logged_at'] == null ? null : _time(json['logged_at']),
          // Copied as text, never rebuilt: this is the frozen record of what
          // was eaten (spec §4).
          macroSnapshot: json['macro_snapshot'] == null
              ? null
              : jsonEncode(json['macro_snapshot']),
          updatedAt: _time(json['updated_at']),
        ),
      );

  Future<void> applyTargets(Map<String, Object?> json) => _db
      .into(_db.macroTargets)
      .insertOnConflictUpdate(
        MacroTargetRow(
          id: '${json['id']}',
          userId: '${json['user_id']}',
          weekStartDate: _date(json['week_start_date']),
          kcal: _double(json['kcal']) ?? 0,
          proteinG: _double(json['protein_g']) ?? 0,
          carbG: _double(json['carb_g']) ?? 0,
          fatG: _double(json['fat_g']) ?? 0,
          updatedAt: _time(json['updated_at']),
        ),
      );

  Future<void> applyCollection(Map<String, Object?> json) => _db
      .into(_db.collections)
      .insertOnConflictUpdate(
        CollectionRow(
          id: '${json['id']}',
          householdId: '${json['household_id']}',
          name: '${json['name'] ?? ''}',
          sortOrder: _int(json['sort_order']) ?? 0,
          updatedAt: _time(json['updated_at']),
        ),
      );

  // ── Membership, which has no timestamps to compare ────────────────────────

  /// Replaces the local favourites with the server's, keeping any the queue
  /// has not sent yet.
  ///
  /// These tables record only that a pair exists — there is no `updated_at` to
  /// resolve, so the server's set is authoritative except where this device
  /// has an unsent opinion. Dropping that exception would undo a heart tapped
  /// on a train before it reached the server.
  Future<void> replaceFavorites({
    required String userId,
    required Set<String> remoteRecipeIds,
    required Future<bool> Function(String entityId) hasPendingWrite,
    required DateTime now,
  }) async {
    final List<RecipeFavoriteRow> local = await (_db.select(
      _db.recipeFavorites,
    )..where(($RecipeFavoritesTable f) => f.userId.equals(userId))).get();

    for (final RecipeFavoriteRow row in local) {
      if (remoteRecipeIds.contains(row.recipeId)) continue;
      if (await hasPendingWrite('$userId/${row.recipeId}')) continue;
      await (_db.delete(_db.recipeFavorites)..where(
            ($RecipeFavoritesTable f) =>
                f.userId.equals(userId) & f.recipeId.equals(row.recipeId),
          ))
          .go();
    }

    for (final String recipeId in remoteRecipeIds) {
      await _db
          .into(_db.recipeFavorites)
          .insertOnConflictUpdate(
            RecipeFavoriteRow(
              userId: userId,
              recipeId: recipeId,
              createdAt: now,
            ),
          );
    }
  }

  /// The same reconcile for which recipes are in which cookbook.
  Future<void> replaceMemberships({
    required Set<(String collectionId, String recipeId)> remote,
    required Future<bool> Function(String entityId) hasPendingWrite,
    required DateTime now,
  }) async {
    final List<RecipeCollectionRow> local = await _db
        .select(_db.recipeCollections)
        .get();

    for (final RecipeCollectionRow row in local) {
      final (String, String) pair = (row.collectionId, row.recipeId);
      if (remote.contains(pair)) continue;
      if (await hasPendingWrite('${row.collectionId}/${row.recipeId}')) {
        continue;
      }
      await (_db.delete(_db.recipeCollections)..where(
            ($RecipeCollectionsTable rc) =>
                rc.collectionId.equals(row.collectionId) &
                rc.recipeId.equals(row.recipeId),
          ))
          .go();
    }

    for (final (String collectionId, String recipeId) pair in remote) {
      await _db
          .into(_db.recipeCollections)
          .insertOnConflictUpdate(
            RecipeCollectionRow(
              collectionId: pair.$1,
              recipeId: pair.$2,
              createdAt: now,
            ),
          );
    }
  }

  /// Server timestamps arrive as ISO text; a date column carries no time.
  static DateTime _date(Object? value) =>
      DateTime.tryParse('$value')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime _time(Object? value) =>
      DateTime.tryParse('$value')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static double? _double(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}
