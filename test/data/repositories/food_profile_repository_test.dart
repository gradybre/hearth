import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_profile_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/food_profile_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/models/food_profile.dart';

/// The food profile, through the real database (spec §4, §5.4).
void main() {
  late HearthDatabase db;
  late FoodProfileRepository repository;
  late PendingWriteStore queue;
  late RemoteRows rows;

  const String user = 'user-1';

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    rows = RemoteRows(db);
    repository = FoodProfileRepository(
      database: db,
      store: FoodProfileStore(db),
      queue: queue,
      userId: user,
      clock: () => DateTime.utc(2026, 8, 29),
    );
  });

  tearDown(() => db.close());

  test('no profile yet is an empty one, not a null', () async {
    // §5.8 makes the questionnaire skippable, so "nothing said" is an
    // ordinary state rather than something every caller must branch on.
    final FoodProfile profile = await repository.mine();

    expect(profile.userId, user);
    expect(profile.isEmpty, isTrue);
    expect(profile.allergies, isEmpty);
  });

  test('a saved profile comes back whole', () async {
    await repository.save(
      const FoodProfile(
        userId: user,
        allergies: <String>['peanuts'],
        dislikes: <String>['mushrooms', 'blue cheese'],
        dietaryPreferences: <String>['high protein'],
        preferredMealTypes: <String>['bowls'],
        caloriesPerMeal: 650,
        proteinPerMealG: 40,
      ),
    );

    final FoodProfile saved = await repository.mine();
    expect(saved.allergies, <String>['peanuts']);
    expect(saved.dislikes, <String>['mushrooms', 'blue cheese']);
    expect(saved.caloriesPerMeal, 650);
    expect(saved.proteinPerMealG, 40);
  });

  test('the user is stamped, not trusted', () async {
    // A profile written against another user would vanish behind RLS the
    // moment it reached the server.
    await repository.save(
      const FoodProfile(userId: 'someone-else', allergies: <String>['fish']),
    );

    final FoodProfile saved = await repository.mine();
    expect(saved.userId, user);
    expect(saved.allergies, <String>['fish']);
  });

  test('a save is queued for sync keyed by the user', () async {
    await repository.save(
      const FoodProfile(userId: user, allergies: <String>['peanuts']),
    );

    final List<PendingWrite> pending = await queue.pending();
    expect(pending, hasLength(1));
    expect(pending.single.entityTable, 'food_profiles');
    // The user *is* the row — the server's primary key is user_id, so there
    // is no separate identity for two devices to disagree about.
    expect(pending.single.entityId, user);
    expect(pending.single.payload['allergies'], <String>['peanuts']);
  });

  test('a profile arriving from the server lands intact', () async {
    // Postgres hands back text[] as a list; the store keeps them joined.
    await rows.applyFoodProfile(<String, Object?>{
      'user_id': user,
      'allergies': <String>['shellfish'],
      'dislikes': <String>['olives'],
      'dietary_preferences': <String>[],
      'preferred_meal_types': <String>['soups'],
      'calories_per_meal_target': 700,
      'protein_target_g': 45,
      'updated_at': DateTime.utc(2026, 8, 29).toIso8601String(),
    });

    final FoodProfile pulled = await repository.mine();
    expect(pulled.allergies, <String>['shellfish']);
    expect(pulled.dislikes, <String>['olives']);
    expect(pulled.dietaryPreferences, isEmpty);
    expect(pulled.preferredMealTypes, <String>['soups']);
    expect(pulled.caloriesPerMeal, 700);
  });

  test('last-write-wins can find the row by its own key', () async {
    // The other tables are keyed by id; this one is keyed by user. Asking for
    // `id` here would query a column that does not exist, and every pull
    // would look like a first-ever write.
    await repository.save(
      const FoodProfile(userId: user, allergies: <String>['peanuts']),
    );

    expect(await rows.updatedAtFor('food_profiles', user), isNotNull);
  });

  test('watching emits the change', () async {
    final Future<FoodProfile> next = repository.watchMine().firstWhere(
      (FoodProfile p) => p.allergies.isNotEmpty,
    );

    await repository.save(
      const FoodProfile(userId: user, allergies: <String>['peanuts']),
    );

    expect((await next).allergies, <String>['peanuts']);
  });
}
