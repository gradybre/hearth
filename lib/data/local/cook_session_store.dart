import 'dart:convert';

import 'hearth_database.dart';

/// Local progress for one cook: direction position and the separate direction
/// and ingredient checks. It is never shared with a household partner.
class StoredCookProgress {
  const StoredCookProgress({
    required this.currentStep,
    required this.checkedStepIds,
    this.checkedIngredientIds = const <String>{},
  });

  final int currentStep;
  final Set<String> checkedStepIds;
  final Set<String> checkedIngredientIds;
}

/// Keeps a cook's place across launches (spec §5.2).
///
/// Backing out to check the planner and coming back should not lose an hour of
/// ticked steps — the list is a record of what you have already done at the
/// stove, and it cannot be reconstructed from anywhere else.
class CookSessionStore {
  CookSessionStore(this._db);

  /// A session older than this is a new cook, not a resumed one.
  ///
  /// Opening the same recipe next week should start clean rather than showing
  /// every step still ticked from last time. Long enough to cover a braise
  /// left overnight, short enough that "I am cooking this again" wins.
  static const Duration staleAfter = Duration(hours: 24);

  final HearthDatabase _db;

  Future<StoredCookProgress?> read(
    String recipeId, {
    required DateTime now,
  }) async {
    final CookSessionRow? row =
        await (_db.select(_db.cookSessions)
              ..where(($CookSessionsTable c) => c.recipeId.equals(recipeId)))
            .getSingleOrNull();
    if (row == null) return null;

    if (now.difference(row.updatedAt) > staleAfter) {
      await clear(recipeId);
      return null;
    }

    return StoredCookProgress(
      currentStep: row.currentStep,
      checkedStepIds: <String>{
        for (final Object? id
            in jsonDecode(row.checkedStepIds) as List<Object?>)
          id as String,
      },
      checkedIngredientIds: <String>{
        for (final Object? id
            in jsonDecode(row.checkedIngredientIds) as List<Object?>)
          id as String,
      },
    );
  }

  Future<void> save({
    required String recipeId,
    required int currentStep,
    required Set<String> checkedStepIds,
    required DateTime now,
    Set<String> checkedIngredientIds = const <String>{},
  }) => _db
      .into(_db.cookSessions)
      .insertOnConflictUpdate(
        CookSessionRow(
          recipeId: recipeId,
          currentStep: currentStep,
          checkedStepIds: jsonEncode(checkedStepIds.toList()),
          checkedIngredientIds: jsonEncode(checkedIngredientIds.toList()),
          updatedAt: now,
        ),
      );

  Future<void> clear(String recipeId) => (_db.delete(
    _db.cookSessions,
  )..where(($CookSessionsTable c) => c.recipeId.equals(recipeId))).go();
}
