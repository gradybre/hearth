import '../../domain/models/food_profile.dart';
import '../local/food_profile_store.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';

/// The only thing features talk to for the food profile (spec §4, §5.4).
///
/// Local first, queued for sync, like every other write in the app: the
/// profile is small and personal, and typing an allergy into it on a train
/// should not depend on having signal.
class FoodProfileRepository {
  FoodProfileRepository({
    required HearthDatabase database,
    required FoodProfileStore store,
    required PendingWriteStore queue,
    required String userId,
    DateTime Function()? clock,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _userId = userId,
       _now = clock ?? DateTime.now;

  static const String entityTable = 'food_profiles';

  final HearthDatabase _db;
  final FoodProfileStore _store;
  final PendingWriteStore _queue;
  final String _userId;
  final DateTime Function() _now;

  /// The profile, or an empty one — never null.
  ///
  /// §5.8 makes the questionnaire skippable, so "no profile yet" is an
  /// ordinary state rather than something callers should have to branch on.
  Future<FoodProfile> mine() async =>
      await _store.forUser(_userId) ?? FoodProfile.empty(_userId);

  Stream<FoodProfile> watchMine() => _store
      .watch(_userId)
      .map((FoodProfile? profile) => profile ?? FoodProfile.empty(_userId));

  /// Saves the profile locally and queues it for sync.
  ///
  /// The user is stamped rather than trusted, for the same reason as recipes
  /// and foods: a profile written against another user would vanish behind
  /// RLS the moment it reached the server.
  Future<void> save(FoodProfile profile) {
    final DateTime now = _now();
    final FoodProfile owned = profile.userId == _userId
        ? profile
        : FoodProfile(
            userId: _userId,
            allergies: profile.allergies,
            dislikes: profile.dislikes,
            dietaryPreferences: profile.dietaryPreferences,
            preferredMealTypes: profile.preferredMealTypes,
            caloriesPerMeal: profile.caloriesPerMeal,
            proteinPerMealG: profile.proteinPerMealG,
          );

    return _db.transaction(() async {
      await _store.upsert(owned, updatedAt: now);
      await _queue.enqueue(
        entityTable: entityTable,
        // The user *is* the row: the server's primary key is user_id, so
        // there is no separate identity to invent or to disagree about
        // between two devices.
        entityId: _userId,
        operation: WriteOperation.upsert,
        payload: toJson(owned, updatedAt: now),
        queuedAt: now,
      );
    });
  }

  static Map<String, Object?> toJson(
    FoodProfile profile, {
    required DateTime updatedAt,
  }) => <String, Object?>{
    'user_id': profile.userId,
    'allergies': profile.allergies,
    'dislikes': profile.dislikes,
    'dietary_preferences': profile.dietaryPreferences,
    'preferred_meal_types': profile.preferredMealTypes,
    'calories_per_meal_target': profile.caloriesPerMeal,
    'protein_target_g': profile.proteinPerMealG,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
