import '../../domain/models/food_profile.dart';
import 'hearth_database.dart';

/// The cached food profile (spec §4, §5.4).
///
/// Cached rather than fetched: the generator reads it on every turn, and a
/// round trip for a handful of words the user typed themselves would be a
/// wait for nothing — and would stop working the moment they were offline.
class FoodProfileStore {
  FoodProfileStore(this._db);

  final HearthDatabase _db;

  Future<FoodProfile?> forUser(String userId) async {
    final FoodProfileRow? row =
        await (_db.select(_db.foodProfiles)
              ..where(($FoodProfilesTable p) => p.userId.equals(userId)))
            .getSingleOrNull();
    return row == null ? null : _toProfile(row);
  }

  Stream<FoodProfile?> watch(String userId) =>
      (_db.select(_db.foodProfiles)
            ..where(($FoodProfilesTable p) => p.userId.equals(userId)))
          .watchSingleOrNull()
          .map((FoodProfileRow? row) => row == null ? null : _toProfile(row));

  Future<void> upsert(FoodProfile profile, {required DateTime updatedAt}) => _db
      .into(_db.foodProfiles)
      .insertOnConflictUpdate(_toRow(profile, updatedAt: updatedAt));

  /// Writes a row straight from the server, without a domain round trip.
  Future<void> upsertRow(FoodProfileRow row) =>
      _db.into(_db.foodProfiles).insertOnConflictUpdate(row);

  static FoodProfile _toProfile(FoodProfileRow row) => FoodProfile(
    userId: row.userId,
    allergies: _split(row.allergies),
    dislikes: _split(row.dislikes),
    dietaryPreferences: _split(row.dietaryPreferences),
    preferredMealTypes: _split(row.preferredMealTypes),
    caloriesPerMeal: row.caloriesPerMealTarget,
    proteinPerMealG: row.proteinTargetG,
  );

  static FoodProfileRow _toRow(
    FoodProfile profile, {
    required DateTime updatedAt,
  }) => FoodProfileRow(
    userId: profile.userId,
    caloriesPerMealTarget: profile.caloriesPerMeal,
    proteinTargetG: profile.proteinPerMealG,
    allergies: _join(profile.allergies),
    dislikes: _join(profile.dislikes),
    dietaryPreferences: _join(profile.dietaryPreferences),
    preferredMealTypes: _join(profile.preferredMealTypes),
    updatedAt: updatedAt,
  );

  /// Newlines rather than commas, so the storage format does not depend on the
  /// editor's. Today the editor splits what you type on commas; if that ever
  /// becomes chips or a picker, nothing stored has to be migrated.
  static String _join(List<String> values) => values.join('\n');

  static List<String> _split(String value) => <String>[
    for (final String part in value.split('\n'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}
