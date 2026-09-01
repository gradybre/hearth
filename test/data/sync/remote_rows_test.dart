import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late RemoteRows rows;
  late PendingWriteStore queue;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 12);
  Future<bool> nothingPending(String _) async => false;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    rows = RemoteRows(db);
    queue = PendingWriteStore(db);
  });

  tearDown(() => db.close());

  ingredientMatchTests(() => db);

  group('a logged meal arrives from another device', () {
    Map<String, Object?> entry({
      String id = 'entry-1',
      Map<String, Object?>? snapshot,
    }) => <String, Object?>{
      'id': id,
      'meal_plan_day_id': 'day-1',
      'meal_slot': 'dinner',
      'ref_type': 'recipe',
      'ref_id': 'recipe-1',
      'servings': 1.5,
      'is_planned': false,
      'is_logged': true,
      'logged_at': t0.toIso8601String(),
      'macro_snapshot': snapshot,
      'updated_at': t0.toIso8601String(),
    };

    setUp(() async {
      await rows.applyDay(<String, Object?>{
        'id': 'day-1',
        'user_id': 'user-1',
        'day': '2026-08-28',
        'notes': null,
        'updated_at': t0.toIso8601String(),
      });
    });

    test('its frozen snapshot is copied, not recomputed', () async {
      // The snapshot is what the meal was when it was logged, and editing the
      // recipe later must never change it (spec §4). Rebuilding it from the
      // current library on the way in would do exactly that.
      await rows.applyEntry(
        entry(
          snapshot: <String, Object?>{
            'kcal': 812.5,
            'protein_g': 41.25,
            'carb_g': 30,
            'fat_g': 55.5,
            'servings': 1.5,
          },
        ),
      );

      final List<MealPlanEntryRow> stored = await db
          .select(db.mealPlanEntries)
          .get();
      final Map<String, Object?> snapshot =
          jsonDecode(stored.single.macroSnapshot!) as Map<String, Object?>;

      expect(snapshot['kcal'], 812.5);
      expect(snapshot['protein_g'], 41.25);
      expect(stored.single.isLogged, isTrue);
      expect(stored.single.servings, 1.5);
    });

    test('a planned entry arrives with no snapshot at all', () async {
      // Planned is not eaten; inventing a snapshot would be inventing history.
      await rows.applyEntry(entry(id: 'entry-2'));

      final MealPlanEntryRow stored =
          (await db.select(db.mealPlanEntries).get()).single;
      expect(stored.macroSnapshot, isNull);
    });

    test('applying the same entry twice does not duplicate it', () async {
      await rows.applyEntry(entry());
      await rows.applyEntry(entry());

      expect(await db.select(db.mealPlanEntries).get(), hasLength(1));
    });
  });

  group('targets and days', () {
    test('a week of targets round-trips', () async {
      await rows.applyTargets(<String, Object?>{
        'id': 'targets-1',
        'user_id': 'user-1',
        'week_start_date': '2026-08-24',
        'kcal': 2200,
        'protein_g': 165,
        'carb_g': 200,
        'fat_g': 73,
        'updated_at': t0.toIso8601String(),
      });

      final MacroTargetRow stored =
          (await db.select(db.macroTargets).get()).single;
      expect(stored.kcal, 2200);
      expect(stored.proteinG, 165);
    });

    test('updatedAtFor reads back what was written', () async {
      await rows.applyDay(<String, Object?>{
        'id': 'day-9',
        'user_id': 'user-1',
        'day': '2026-08-28',
        'updated_at': t0.toIso8601String(),
      });

      final DateTime? at = await rows.updatedAtFor('meal_plan_days', 'day-9');
      expect(at, isNotNull);
      expect(at!.isAtSameMomentAs(t0), isTrue);
    });

    test('a record this device has never seen has no timestamp', () async {
      expect(await rows.updatedAtFor('meal_plan_days', 'nope'), isNull);
    });
  });

  group('favourites, which have no timestamps to compare', () {
    setUp(() async {
      for (final String id in <String>['recipe-1', 'recipe-2']) {
        await RecipeStore(db).upsert(
          aRecipe(
            id: id,
            title: id,
            sections: <RecipeSection>[aSection(id: 'section-$id')],
          ),
          updatedAt: t0,
        );
      }
    });

    Future<Set<String>> localFavorites() async => <String>{
      for (final RecipeFavoriteRow row
          in await db.select(db.recipeFavorites).get())
        row.recipeId,
    };

    test('the server\'s set becomes the local set', () async {
      await rows.replaceFavorites(
        userId: 'user-1',
        remoteRecipeIds: <String>{'recipe-1'},
        hasPendingWrite: nothingPending,
        now: t0,
      );

      expect(await localFavorites(), <String>{'recipe-1'});
    });

    test('one the server no longer has is removed', () async {
      await rows.replaceFavorites(
        userId: 'user-1',
        remoteRecipeIds: <String>{'recipe-1', 'recipe-2'},
        hasPendingWrite: nothingPending,
        now: t0,
      );

      await rows.replaceFavorites(
        userId: 'user-1',
        remoteRecipeIds: <String>{'recipe-1'},
        hasPendingWrite: nothingPending,
        now: t0,
      );

      expect(await localFavorites(), <String>{'recipe-1'});
    });

    test('but not one this device has not sent yet', () async {
      // A heart tapped on a train, still queued. The server has never heard
      // of it, and its silence must not be read as a removal.
      await db
          .into(db.recipeFavorites)
          .insert(
            RecipeFavoriteRow(
              userId: 'user-1',
              recipeId: 'recipe-2',
              createdAt: t0,
            ),
          );
      await queue.enqueue(
        entityTable: 'recipe_favorites',
        entityId: 'user-1/recipe-2',
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{},
        queuedAt: t0,
      );

      await rows.replaceFavorites(
        userId: 'user-1',
        remoteRecipeIds: <String>{'recipe-1'},
        hasPendingWrite: queue.hasPendingFor,
        now: t0,
      );

      expect(await localFavorites(), <String>{'recipe-1', 'recipe-2'});
    });

    test('another user\'s favourites are left alone', () async {
      await db
          .into(db.recipeFavorites)
          .insert(
            RecipeFavoriteRow(
              userId: 'user-2',
              recipeId: 'recipe-2',
              createdAt: t0,
            ),
          );

      await rows.replaceFavorites(
        userId: 'user-1',
        remoteRecipeIds: <String>{},
        hasPendingWrite: nothingPending,
        now: t0,
      );

      expect(await db.select(db.recipeFavorites).get(), hasLength(1));
    });
  });
}

/// Ingredient answers arriving from the other phone (spec §5.3, §7.1).
void ingredientMatchTests(HearthDatabase Function() database) {
  Map<String, Object?> row({
    String id = 'match-1',
    String wording = 'evoo',
    String? foodId = 'food-oil',
    bool needsNoMatch = false,
  }) => <String, Object?>{
    'id': id,
    'household_id': 'household-1',
    'ingredient_string': wording,
    'food_id': foodId,
    'needs_no_match': needsNoMatch,
    'updated_at': '2026-08-31T12:00:00Z',
  };

  Future<void> seedOil() => database()
      .into(database().foods)
      .insert(
        FoodsCompanion.insert(
          id: 'food-oil',
          name: 'Olive oil',
          updatedAt: DateTime.utc(2026, 8, 31),
        ),
      );

  group('an ingredient match from the server', () {
    test('lands as a match', () async {
      await seedOil();
      await RemoteRows(database()).applyIngredientMatch(row());

      final IngredientMatchRow saved = await database()
          .select(database().ingredientMatches)
          .getSingle();
      expect(saved.ingredientString, 'evoo');
      expect(saved.foodId, 'food-oil');
      expect(saved.needsNoMatch, isFalse);
    });

    test('or as a seasoning, with no food', () async {
      await RemoteRows(database()).applyIngredientMatch(
        row(wording: 'salt', foodId: null, needsNoMatch: true),
      );

      final IngredientMatchRow saved = await database()
          .select(database().ingredientMatches)
          .getSingle();
      expect(saved.needsNoMatch, isTrue);
      expect(saved.foodId, isNull);
    });

    test(
      'naming a food this device has not got is skipped, not thrown',
      () async {
        // Foods are pulled before records so this is rare, but the row has a
        // foreign key onto them and a failure would abort the whole table's
        // pull over one row. A match to a food that is not here is useless
        // anyway — the matcher only ever suggests foods the library holds.
        await RemoteRows(database()).applyIngredientMatch(row());
        expect(
          await database().select(database().ingredientMatches).get(),
          isEmpty,
        );
      },
    );

    test('replaces the local answer for the same wording', () async {
      await seedOil();
      // Upserted on the wording rather than the id: a row written before ids
      // were derived could still carry a random one, and inserting beside it
      // would break the unique index on a device that did nothing wrong.
      await RemoteRows(database()).applyIngredientMatch(row(id: 'old-random'));
      await RemoteRows(database()).applyIngredientMatch(
        row(id: 'derived', foodId: null, needsNoMatch: true),
      );

      final IngredientMatchRow saved = await database()
          .select(database().ingredientMatches)
          .getSingle();
      expect(saved.id, 'derived');
      expect(saved.needsNoMatch, isTrue);
    });

    test('a wording that normalises to nothing is ignored', () async {
      await RemoteRows(database()).applyIngredientMatch(row(wording: '  '));
      expect(
        await database().select(database().ingredientMatches).get(),
        isEmpty,
      );
    });
  });
}
