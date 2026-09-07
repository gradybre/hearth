import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
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
      }, hasPendingWrite: nothingPending);

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

  group("a partner's shopping list", () {
    Map<String, Object?> aList() => <String, Object?>{
      'id': 'list-1',
      'household_id': 'household-1',
      'from_date': '2026-09-02',
      'to_date': '2026-09-08',
      'status': 'draft',
      'updated_at': '2026-09-02T09:00:00Z',
    };

    Map<String, Object?> anItem() => <String, Object?>{
      'id': 'item-1',
      'shopping_list_id': 'list-1',
      'item_key': 'ground-beef',
      'raw_name': 'ground beef',
      'planned_canonical': 907.185,
      'planned_kind': 'mass',
      'planned_unit': 'lb',
      'checked': true,
      'is_manual': false,
      'has_unquantified': false,
      'sort_order': 0,
      'source_recipe_ids': <String>['recipe-1', 'recipe-2'],
      'updated_at': '2026-09-02T09:00:00Z',
    };

    test('arrives whole, tick and all', () async {
      await rows.applyShoppingList(aList());
      await rows.applyShoppingItem(anItem());

      final ShoppingListSnapshot? saved = await ShoppingStore(db)
          .current(householdId: 'household-1');
      expect(saved, isNotNull);
      expect(saved!.from, DateTime(2026, 9, 2));
      expect(saved.lines.single.name, 'ground beef');
      expect(saved.lines.single.checked, isTrue);
    });

    test(
      'a uuid[] of sources becomes the joined string the store holds',
      () async {
        // Postgres sends an array; the local column is one joined string.
        await rows.applyShoppingList(aList());
        await rows.applyShoppingItem(anItem());

        final List<ShoppingItemRow> stored = await ShoppingStore(db)
            .rowsFor('list-1');
        expect(stored.single.sourceRecipeIds, 'recipe-1,recipe-2');
      },
    );

    test('a line whose list has not arrived is skipped, not fatal', () async {
      // The foreign key would refuse it and take the rest of the table's pull
      // down with it. The list is one step ahead in the same pass.
      await rows.applyShoppingItem(anItem());

      expect(await ShoppingStore(db).rowsFor('list-1'), isEmpty);
    });

    test('re-applying the same line changes nothing', () async {
      await rows.applyShoppingList(aList());
      await rows.applyShoppingItem(anItem());
      await rows.applyShoppingItem(anItem());

      expect(await ShoppingStore(db).rowsFor('list-1'), hasLength(1));
    });
  });
}

Future<bool> _nothingPending(String _) async => false;

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
      await RemoteRows(database())
          .applyIngredientMatch(row(), hasPendingWrite: _nothingPending);

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
        hasPendingWrite: _nothingPending,
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
        await RemoteRows(database())
            .applyIngredientMatch(row(), hasPendingWrite: _nothingPending);
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
      await RemoteRows(database()).applyIngredientMatch(
        row(id: 'old-random'),
        hasPendingWrite: _nothingPending,
      );
      await RemoteRows(database()).applyIngredientMatch(
        row(id: 'derived', foodId: null, needsNoMatch: true),
        hasPendingWrite: _nothingPending,
      );

      final IngredientMatchRow saved = await database()
          .select(database().ingredientMatches)
          .getSingle();
      expect(saved.id, 'derived');
      expect(saved.needsNoMatch, isTrue);
    });

    test('but not over an answer this device has not sent yet', () async {
      // The same shape as macro_targets (#37), and the same loss. The pull's
      // own guard asks whether the *incoming* id has an unsent write — and on
      // this table the incoming id is whatever the server row happens to
      // carry, which for a row written before ids were derived is not the id
      // this phone queued under. So the guard sees nothing, the upsert
      // resolves on the wording, and an answer the household gave on this
      // phone is replaced by the one it is still waiting to correct.
      await seedOil();
      final HearthDatabase db = database();
      final PendingWriteStore queue = PendingWriteStore(db);

      // This phone said "evoo is a seasoning", offline. The local row takes
      // the derived id; the queued write is keyed on it.
      const String derived = 'derived-id';
      await db
          .into(db.ingredientMatches)
          .insert(
            IngredientMatchesCompanion.insert(
              id: derived,
              householdId: 'household-1',
              ingredientString: 'evoo',
              needsNoMatch: const Value<bool>(true),
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
      await queue.enqueue(
        entityTable: 'ingredient_matches',
        entityId: derived,
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'id': derived},
        queuedAt: DateTime.utc(2026, 9, 1),
      );

      // The server still holds the old row, under an id of its own.
      await RemoteRows(db).applyIngredientMatch(
        row(id: 'old-random'),
        hasPendingWrite: queue.hasPendingFor,
      );

      final IngredientMatchRow saved = await db
          .select(db.ingredientMatches)
          .getSingle();
      expect(
        saved.needsNoMatch,
        isTrue,
        reason: 'the unsent answer was overwritten by the one it corrects',
      );
      expect(saved.foodId, isNull);
    });

    test('and a tombstone does not take one either', () async {
      await seedOil();
      final HearthDatabase db = database();
      final PendingWriteStore queue = PendingWriteStore(db);

      const String derived = 'derived-id';
      await db
          .into(db.ingredientMatches)
          .insert(
            IngredientMatchesCompanion.insert(
              id: derived,
              householdId: 'household-1',
              ingredientString: 'evoo',
              foodId: const Value<String?>('food-oil'),
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
      await queue.enqueue(
        entityTable: 'ingredient_matches',
        entityId: derived,
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'id': derived},
        queuedAt: DateTime.utc(2026, 9, 1),
      );

      await RemoteRows(db).applyIngredientMatch(<String, Object?>{
        ...row(id: 'old-random'),
        'is_deleted': true,
      }, hasPendingWrite: queue.hasPendingFor);

      expect(
        await db.select(db.ingredientMatches).get(),
        hasLength(1),
        reason: 'a forget from before this answer must not erase it unsent',
      );
    });

    test('a wording that normalises to nothing is ignored', () async {
      await RemoteRows(database()).applyIngredientMatch(
        row(wording: '  '),
        hasPendingWrite: _nothingPending,
      );
      expect(
        await database().select(database().ingredientMatches).get(),
        isEmpty,
      );
    });
  });
}
