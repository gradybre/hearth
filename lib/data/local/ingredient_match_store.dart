import 'package:drift/drift.dart';

import '../../domain/text/text_normaliser.dart';
import 'hearth_database.dart';

/// Remembered ingredient-string to food mappings (spec §5.3).
///
/// The point is that correcting a match is a one-time cost: once "evoo" has
/// been pointed at olive oil, every future line saying "evoo" resolves on its
/// own. Matching is keyed on the shared normalised string, so "EVOO", "evoo",
/// and "evoo." are the same key everywhere in the app.
class IngredientMatchStore {
  IngredientMatchStore(this._db);

  final HearthDatabase _db;

  /// Records a confirmed match, replacing any earlier one for the same string.
  Future<void> remember({
    required String householdId,
    required String ingredientString,
    required String foodId,
    required String id,
    required DateTime updatedAt,
  }) async {
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return;

    await _db
        .into(_db.ingredientMatches)
        .insert(
          IngredientMatchesCompanion.insert(
            id: id,
            householdId: householdId,
            ingredientString: key,
            foodId: foodId,
            updatedAt: updatedAt,
          ),
          onConflict: DoUpdate(
            (_) => IngredientMatchesCompanion(
              foodId: Value<String>(foodId),
              updatedAt: Value<DateTime>(updatedAt),
            ),
            target: <Column<Object>>[
              _db.ingredientMatches.householdId,
              _db.ingredientMatches.ingredientString,
            ],
          ),
        );
  }

  /// Forgets a remembered match, so the next save can record a new one.
  Future<void> forget({
    required String householdId,
    required String ingredientString,
  }) async {
    await (_db.delete(_db.ingredientMatches)..where(
          ($IngredientMatchesTable t) =>
              t.householdId.equals(householdId) &
              t.ingredientString.equals(normaliseKey(ingredientString)),
        ))
        .go();
  }

  /// The remembered food for [ingredientString], if there is one.
  Future<String?> rememberedFoodId({
    required String householdId,
    required String ingredientString,
  }) async {
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return null;

    final IngredientMatchRow? row =
        await (_db.select(_db.ingredientMatches)..where(
              ($IngredientMatchesTable t) =>
                  t.householdId.equals(householdId) &
                  t.ingredientString.equals(key),
            ))
            .getSingleOrNull();
    return row?.foodId;
  }

  /// Every remembered match for the household, keyed by normalised string.
  Future<Map<String, String>> allFor(String householdId) async {
    final List<IngredientMatchRow> rows =
        await (_db.select(_db.ingredientMatches)..where(
              ($IngredientMatchesTable t) => t.householdId.equals(householdId),
            ))
            .get();
    return <String, String>{
      for (final IngredientMatchRow row in rows)
        row.ingredientString: row.foodId,
    };
  }
}
