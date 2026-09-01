import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/foods/no_match_rule.dart';
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

  /// The row id for a wording, derived rather than random.
  ///
  /// Both phones in a household will decide "evoo means olive oil" on their
  /// own, and a random id each would make two rows for one wording — which the
  /// unique key then refuses on whichever device syncs second, permanently.
  /// Deriving the id from the pair the unique key is on means both arrive at
  /// the same row and the later write simply updates it.
  static String idFor(String householdId, String ingredientString) =>
      const Uuid().v5(
        Namespace.url.value,
        'hearth:ingredient-match:$householdId:'
        '${normaliseKey(ingredientString)}',
      );

  /// Records a confirmed match, replacing any earlier one for the same string.
  Future<void> remember({
    required String householdId,
    required String ingredientString,
    required String foodId,
    required DateTime updatedAt,
  }) async {
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return;

    await _db
        .into(_db.ingredientMatches)
        .insert(
          IngredientMatchesCompanion.insert(
            id: idFor(householdId, key),
            householdId: householdId,
            ingredientString: key,
            foodId: Value<String?>(foodId),
            updatedAt: updatedAt,
          ),
          onConflict: DoUpdate(
            (_) => IngredientMatchesCompanion(
              id: Value<String>(idFor(householdId, key)),
              foodId: Value<String?>(foodId),
              needsNoMatch: const Value<bool>(false),
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
  ///
  /// Rows answering "nothing to match" are not matches and are left out; they
  /// come back from [noMatchRules] instead.
  Future<Map<String, String>> allFor(String householdId) async {
    final List<IngredientMatchRow> rows = await _rowsFor(householdId);
    return <String, String>{
      for (final IngredientMatchRow row in rows)
        if (row.foodId case final String foodId) row.ingredientString: foodId,
    };
  }

  /// Records that a wording needs no food at all — salt, pepper, a spice
  /// (spec §5.3).
  ///
  /// The same row a food match would occupy, because it is the same question
  /// with the other answer, and the unique key keeps a wording to one of them.
  Future<void> rememberNoMatch({
    required String householdId,
    required String ingredientString,
    required DateTime updatedAt,
  }) async {
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return;

    await _db
        .into(_db.ingredientMatches)
        .insert(
          IngredientMatchesCompanion.insert(
            id: idFor(householdId, key),
            householdId: householdId,
            ingredientString: key,
            needsNoMatch: const Value<bool>(true),
            updatedAt: updatedAt,
          ),
          onConflict: DoUpdate(
            (_) => IngredientMatchesCompanion(
              id: Value<String>(idFor(householdId, key)),
              foodId: const Value<String?>(null),
              needsNoMatch: const Value<bool>(true),
              updatedAt: Value<DateTime>(updatedAt),
            ),
            target: <Column<Object>>[
              _db.ingredientMatches.householdId,
              _db.ingredientMatches.ingredientString,
            ],
          ),
        );
  }

  /// What this household has said about which wordings need no food.
  ///
  /// Marked wordings are its own [rememberNoMatch] rows. Unmarked ones are
  /// rows that answer neither a food nor no-match, which is how disagreeing
  /// with a built-in is recorded — the seed list is shipped rather than
  /// written into anybody's data, so an opinion about it has to be a row of
  /// its own.
  Future<NoMatchRules> noMatchRules(String householdId) async {
    final List<IngredientMatchRow> rows = await _rowsFor(householdId);
    return NoMatchRules(
      marked: <String>{
        for (final IngredientMatchRow row in rows)
          if (row.needsNoMatch) row.ingredientString,
      },
      unmarked: <String>{
        for (final IngredientMatchRow row in rows)
          if (!row.needsNoMatch && row.foodId == null) row.ingredientString,
      },
    );
  }

  /// Records that a wording needs an ordinary match after all — turning a
  /// built-in seasoning back off.
  Future<void> rememberNeedsMatch({
    required String householdId,
    required String ingredientString,
    required DateTime updatedAt,
  }) async {
    final String key = normaliseKey(ingredientString);
    if (key.isEmpty) return;

    await _db
        .into(_db.ingredientMatches)
        .insert(
          IngredientMatchesCompanion.insert(
            id: idFor(householdId, key),
            householdId: householdId,
            ingredientString: key,
            updatedAt: updatedAt,
          ),
          onConflict: DoUpdate(
            (_) => IngredientMatchesCompanion(
              id: Value<String>(idFor(householdId, key)),
              foodId: const Value<String?>(null),
              needsNoMatch: const Value<bool>(false),
              updatedAt: Value<DateTime>(updatedAt),
            ),
            target: <Column<Object>>[
              _db.ingredientMatches.householdId,
              _db.ingredientMatches.ingredientString,
            ],
          ),
        );
  }

  Future<List<IngredientMatchRow>> _rowsFor(String householdId) =>
      (_db.select(_db.ingredientMatches)..where(
            ($IngredientMatchesTable t) => t.householdId.equals(householdId),
          ))
          .get();
}
