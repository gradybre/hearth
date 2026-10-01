import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

final DateTime _captured = DateTime.utc(2026, 10, 1, 12);

void main() {
  late HearthDatabase db;
  late RecipeStore recipes;
  late FoodStore foods;
  late DataExport exporter;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeStore(db);
    foods = FoodStore(db);
    exporter = DataExport(
      database: db,
      recipes: recipes,
      foods: foods,
      clock: () => _captured,
    );
  });
  tearDown(() => db.close());

  Future<ExportSnapshot> prepare() =>
      exporter.prepare(householdId: 'household-1', userId: 'user-1');

  test(
    'scope, counts and logged dates describe the exact captured file',
    () async {
      await recipes.upsert(aRecipe(id: 'recipe-1'), updatedAt: _captured);
      await _day(db, 'earlier', DateTime.utc(2026, 9, 2));
      await _day(db, 'later', DateTime.utc(2026, 9, 8));
      await _day(db, 'future-plan', DateTime.utc(2026, 12, 15));
      await _entry(db, 'one', 'earlier', logged: true, planned: false);
      await _entry(db, 'two', 'later', logged: true);
      await _entry(db, 'three', 'future-plan');
      await _day(db, 'partner-day', DateTime.utc(2020), userId: 'user-2');
      await _entry(db, 'partner-log', 'partner-day', logged: true);

      final ExportSnapshot snapshot = await prepare();
      final Map<String, Object?> data = _data(snapshot);
      final Map<String, Object?> manifest = _manifest(snapshot);

      expect(snapshot.householdId, 'household-1');
      expect(snapshot.userId, 'user-1');
      expect(snapshot.capturedAt, _captured);
      expect(snapshot.file.name, 'hearth-2026-10-01.json');
      expect(data['version'], 2);
      expect(data['exported_at'], _captured.toIso8601String());
      expect(manifest['exported_at'], data['exported_at']);
      expect(manifest['scope'], <String, Object?>{
        'household_id': snapshot.householdId,
        'user_id': snapshot.userId,
      });
      expect(manifest['counts'], snapshot.counts);
      for (final String section in <String>[
        'recipes',
        'foods',
        'meal_plan_days',
        'meal_plan_entries',
        'macro_targets',
        'plan_templates',
        'collections',
        'ingredient_matches',
        'shopping_lists',
      ]) {
        expect(
          snapshot.counts[section],
          (data[section]! as List<Object?>).length,
        );
      }
      expect(snapshot.counts['logged_entries'], 2);
      expect(snapshot.counts['planned_entries'], 2);
      expect(snapshot.counts['meal_plan_days'], 3);
      expect(snapshot.loggedDayStart, DateTime.utc(2026, 9, 2));
      expect(snapshot.loggedDayEnd, DateTime.utc(2026, 9, 8));
      expect(manifest['logged_day_start'], '2026-09-02');
      expect(manifest['logged_day_end'], '2026-09-08');
      expect(snapshot.exclusions, manifest['excluded']);
      expect(snapshot.exclusions.join(' '), contains('Recipe photos'));
      expect(snapshot.pendingChanges, 0);
      expect(snapshot.localReferencesComplete, isTrue);
    },
  );

  test('a plan without any logged entries has no logged date range', () async {
    await _day(db, 'planned', DateTime.utc(2026, 10, 2));
    await _entry(db, 'plan', 'planned');

    final ExportSnapshot snapshot = await prepare();

    expect(snapshot.counts['logged_entries'], 0);
    expect(snapshot.counts['planned_entries'], 1);
    expect(snapshot.loggedDayStart, isNull);
    expect(snapshot.loggedDayEnd, isNull);
    expect(_manifest(snapshot)['logged_day_start'], isNull);
    expect(_manifest(snapshot)['logged_day_end'], isNull);
  });

  test('reviewed bytes and facts survive later database edits', () async {
    await recipes.upsert(
      aRecipe(id: 'recipe-1', title: 'Before'),
      updatedAt: _captured,
    );
    await _day(db, 'logged', DateTime.utc(2026, 9, 30));
    const String frozen =
        '{"kcal":432,"servings":1.5,"future_field":{"portion":"original"}}';
    await _entry(db, 'log', 'logged', logged: true, snapshot: frozen);
    final ExportSnapshot reviewed = await prepare();
    final String reviewedBytes = reviewed.file.contents;

    await recipes.upsert(
      aRecipe(id: 'recipe-1', title: 'After'),
      updatedAt: _captured,
    );
    await recipes.upsert(aRecipe(id: 'recipe-2'), updatedAt: _captured);
    await PendingWriteStore(db).enqueue(
      entityTable: 'recipes',
      entityId: 'recipe-2',
      operation: WriteOperation.upsert,
      payload: const <String, Object?>{'id': 'recipe-2'},
      queuedAt: _captured,
    );
    final ExportSnapshot later = await prepare();

    expect(reviewed.file.contents, reviewedBytes);
    expect(reviewed.file.contents, contains('Before'));
    expect(reviewed.file.contents, isNot(contains('After')));
    expect(reviewed.counts['recipes'], 1);
    expect(reviewed.pendingChanges, 0);
    expect(later.counts['recipes'], 2);
    expect(later.pendingChanges, 1);
    expect(later.file.contents, contains('After'));
    for (final ExportSnapshot snapshot in <ExportSnapshot>[reviewed, later]) {
      final Map<String, Object?> log =
          (_data(snapshot)['meal_plan_entries']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(log['macro_snapshot'], jsonDecode(frozen));
    }
  });

  test('snapshot collections cannot be mutated through any caller alias', () {
    final Map<String, int> counts = <String, int>{'recipes': 1};
    final List<String> exclusions = <String>['Photos'];
    final List<String> missing = <String>['food missing'];
    final ExportSnapshot snapshot = ExportSnapshot(
      file: const ExportedFile(name: 'reviewed.json', contents: '{}'),
      householdId: 'household-1',
      userId: 'user-1',
      capturedAt: _captured,
      counts: counts,
      loggedDayStart: null,
      loggedDayEnd: null,
      pendingChanges: 0,
      exclusions: exclusions,
      missingReferences: missing,
    );

    counts['recipes'] = 99;
    exclusions.clear();
    missing.clear();

    expect(snapshot.counts, <String, int>{'recipes': 1});
    expect(snapshot.exclusions, <String>['Photos']);
    expect(snapshot.missingReferences, <String>['food missing']);
    expect(snapshot.localReferencesComplete, isFalse);
    expect(() => snapshot.counts['recipes'] = 2, throwsUnsupportedError);
    expect(() => snapshot.exclusions.add('Logs'), throwsUnsupportedError);
    expect(snapshot.missingReferences.clear, throwsUnsupportedError);
  });

  test(
    'deleted owned definitions and referenced global rows remain included',
    () async {
      await recipes.upsert(
        aRecipe(
          id: 'recipe-1',
          isDeleted: true,
          ingredients: <RecipeIngredient>[
            anIngredient('global ingredient', foodId: 'global-used'),
          ],
        ),
        updatedAt: _captured,
      );
      await foods.upsert(
        aFood(
          'Deleted owned',
          id: 'owned',
        ).withHousehold('household-1').withDeleted(),
        updatedAt: _captured,
      );
      await foods.upsert(
        aFood('Deleted global', id: 'global-used').withDeleted(),
        updatedAt: _captured,
      );
      await foods.upsert(
        aFood('Unused catalogue', id: 'unused-global'),
        updatedAt: _captured,
      );
      await _day(db, 'logged', DateTime.utc(2026, 9, 30));
      await _entry(db, 'log', 'logged', logged: true);

      final ExportSnapshot snapshot = await prepare();
      final Map<String, Object?> data = _data(snapshot);
      final List<Map<String, Object?>> exported =
          (data['foods']! as List<Object?>).cast<Map<String, Object?>>();

      expect(
        exported.map((Map<String, Object?> row) => row['id']),
        unorderedEquals(<String>['owned', 'global-used']),
      );
      expect(
        exported.every((Map<String, Object?> row) => row['is_deleted'] == true),
        isTrue,
      );
      expect(
        exported.singleWhere(
          (Map<String, Object?> row) => row['id'] == 'global-used',
        )['is_global'],
        isTrue,
      );
      expect(snapshot.counts['recipes'], 1);
      expect(snapshot.counts['foods'], 2);
      expect(snapshot.counts['global_foods_referenced'], 1);
      expect(snapshot.localReferencesComplete, isTrue);
    },
  );

  test(
    'partner private rows and another household stay outside the scope',
    () async {
      for (final String suffix in <String>['1', '2']) {
        await recipes.upsert(
          aRecipe(
            id: 'recipe-$suffix',
            householdId: 'household-$suffix',
            title: 'recipe-scope-$suffix',
          ),
          updatedAt: _captured,
        );
        await foods.upsert(
          aFood(
            'food-scope-$suffix',
            id: 'food-$suffix',
          ).withHousehold('household-$suffix'),
          updatedAt: _captured,
        );
        await _day(
          db,
          'day-$suffix',
          DateTime.utc(2026, 9, 30),
          userId: 'user-$suffix',
        );
        await _entry(
          db,
          'entry-$suffix',
          'day-$suffix',
          refId: 'recipe-$suffix',
          logged: true,
        );
        await db
            .into(db.planTemplates)
            .insert(
              PlanTemplatesCompanion.insert(
                id: 'template-$suffix',
                userId: 'user-$suffix',
                name: 'template-scope-$suffix',
                updatedAt: _captured,
              ),
            );
        await db
            .into(db.macroTargets)
            .insert(
              MacroTargetsCompanion.insert(
                id: 'target-$suffix',
                userId: 'user-$suffix',
                weekStartDate: DateTime.utc(2026, 9, 28),
                kcal: 2000,
                proteinG: 100,
                carbG: 200,
                fatG: 80,
                updatedAt: _captured,
              ),
            );
        await db
            .into(db.recipeFavorites)
            .insert(
              RecipeFavoritesCompanion.insert(
                userId: 'user-$suffix',
                recipeId: 'recipe-$suffix',
                createdAt: _captured,
              ),
            );
        await db
            .into(db.foodProfiles)
            .insert(
              FoodProfilesCompanion.insert(
                userId: 'user-$suffix',
                dislikes: Value<String>('private-dislike-$suffix'),
                updatedAt: _captured,
              ),
            );
        await db
            .into(db.collections)
            .insert(
              CollectionsCompanion.insert(
                id: 'collection-$suffix',
                householdId: 'household-$suffix',
                name: 'collection-scope-$suffix',
                updatedAt: _captured,
              ),
            );
        await db
            .into(db.recipeCollections)
            .insert(
              RecipeCollectionsCompanion.insert(
                collectionId: 'collection-$suffix',
                recipeId: 'recipe-$suffix',
                createdAt: _captured,
              ),
            );
        await db
            .into(db.ingredientMatches)
            .insert(
              IngredientMatchesCompanion.insert(
                id: 'match-$suffix',
                householdId: 'household-$suffix',
                ingredientString: 'match-scope-$suffix',
                foodId: Value<String>('food-$suffix'),
                updatedAt: _captured,
              ),
            );
        await _shoppingList(
          db,
          'list-$suffix',
          householdId: 'household-$suffix',
        );
        await _shoppingItem(db, 'item-$suffix', 'list-$suffix');
      }

      final ExportSnapshot snapshot = await prepare();
      final Map<String, Object?> data = _data(snapshot);

      expect(snapshot.counts.values.where((int value) => value > 1), isEmpty);
      expect(snapshot.counts['food_profiles'], 1);
      expect(data['favorite_recipe_ids'], <String>['recipe-1']);
      expect(
        (data['food_profile']! as Map<String, Object?>)['dislikes'],
        'private-dislike-1',
      );
      expect(snapshot.file.contents, isNot(contains('scope-2')));
      expect(snapshot.file.contents, isNot(contains('private-dislike-2')));
      expect(snapshot.file.contents, isNot(contains('user-2')));
      expect(snapshot.file.contents, isNot(contains('household-2')));
      expect(snapshot.localReferencesComplete, isTrue);
    },
  );

  test(
    'pending count is device-wide and separate from reference completeness',
    () async {
      await PendingWriteStore(db).enqueue(
        entityTable: 'meal_plan_days',
        entityId: 'other-user-day',
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'user_id': 'user-2'},
        queuedAt: _captured,
      );
      await PendingWriteStore(db).enqueue(
        entityTable: 'recipes',
        entityId: 'other-household-recipe',
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'household_id': 'household-2'},
        queuedAt: _captured,
      );

      final ExportSnapshot snapshot = await prepare();
      final Map<String, Object?> manifest = _manifest(snapshot);

      expect(snapshot.pendingChanges, 2);
      expect(snapshot.localReferencesComplete, isTrue);
      expect(manifest['pending_changes'], 2);
      expect(manifest['pending_changes_scope'], 'device');
      expect(manifest['local_references_complete'], isTrue);
      expect(manifest['complete'], isFalse);
      expect(
        manifest['note'],
        startsWith('2 changes were pending on this device'),
      );
      expect(manifest['note'], contains('outside this export'));
      expect(snapshot.file.contents, isNot(contains('user-2')));
      expect(snapshot.file.contents, isNot(contains('household-2')));
    },
  );

  test('an empty outbox makes no promise about cloud completeness', () async {
    final Map<String, Object?> manifest = _manifest(await prepare());

    expect(manifest['pending_changes'], 0);
    expect(manifest['complete'], isTrue);
    expect(
      manifest['completeness_scope'],
      'local_references_and_device_pending_changes',
    );
    expect(manifest['note'], contains('does not verify whether the cloud'));
    expect(manifest['note'], isNot(contains('sent everything')));
  });

  test(
    'shopping references include the global definitions they name',
    () async {
      for (final String id in <String>['linked', 'contributed', 'unused']) {
        await foods.upsert(aFood(id, id: id), updatedAt: _captured);
      }
      await _shoppingList(db, 'list');
      await _shoppingItem(
        db,
        'item',
        'list',
        foodId: 'linked',
        contributions:
            '[{"kind":"food","ref_id":"contributed","quantities":[]}]',
      );

      final ExportSnapshot snapshot = await prepare();
      final List<Map<String, Object?>> exported =
          (_data(snapshot)['foods']! as List<Object?>)
              .cast<Map<String, Object?>>();

      expect(
        exported.map((Map<String, Object?> row) => row['id']),
        unorderedEquals(<String>['linked', 'contributed']),
      );
      expect(snapshot.counts['global_foods_referenced'], 2);
      expect(snapshot.localReferencesComplete, isTrue);
    },
  );

  test(
    'shopping missing references are named without exporting private targets',
    () async {
      await foods.upsert(
        aFood(
          'Private target',
          id: 'private-food',
        ).withHousehold('household-2'),
        updatedAt: _captured,
      );
      await recipes.upsert(
        aRecipe(
          id: 'private-recipe',
          householdId: 'household-2',
          title: 'Private recipe title',
        ),
        updatedAt: _captured,
      );
      await _shoppingList(db, 'list');
      await _shoppingItem(
        db,
        'item',
        'list',
        foodId: 'private-food',
        sourceRecipes: 'missing-source',
        contributions: '[{"kind":"recipe","ref_id":"private-recipe","quantities":[]},{"kind":"food","ref_id":"missing-food","quantities":[]}]',
      );
      await _shoppingList(db, 'other-list', householdId: 'household-2');
      await _shoppingItem(
        db,
        'other-item',
        'other-list',
        foodId: 'hidden-reference',
        sourceRecipes: 'hidden-recipe',
      );

      final ExportSnapshot snapshot = await prepare();

      expect(snapshot.missingReferences, <String>[
        'food missing-food',
        'food private-food',
        'recipe missing-source',
        'recipe private-recipe',
      ]);
      expect(snapshot.localReferencesComplete, isFalse);
      expect(_manifest(snapshot)['local_references_complete'], isFalse);
      expect(_manifest(snapshot)['complete'], isFalse);
      expect(snapshot.counts['foods'], 0);
      expect(snapshot.counts['recipes'], 0);
      expect(snapshot.counts['shopping_lists'], 1);
      expect(snapshot.counts['shopping_items'], 1);
      expect(snapshot.file.contents, isNot(contains('Private target')));
      expect(snapshot.file.contents, isNot(contains('Private recipe title')));
      expect(snapshot.file.contents, isNot(contains('hidden-reference')));
      expect(snapshot.file.contents, isNot(contains('hidden-recipe')));
    },
  );

  test(
    'a competing write cannot land between the snapshot section reads',
    () async {
      final _PausedRecipeStore paused = _PausedRecipeStore(db);
      final DataExport capturing = DataExport(
        database: db,
        recipes: paused,
        foods: foods,
        clock: () => _captured,
      );
      final Future<ExportSnapshot> inProgress = capturing.prepare(
        householdId: 'household-1',
        userId: 'user-1',
      );
      await paused.readStarted.future;
      final Future<void> write = foods.upsert(
        aFood('Arriving food', id: 'arriving').withHousehold('household-1'),
        updatedAt: _captured,
      );
      // Let the competing operation reach the executor while capture is paused.
      await Future<void>.delayed(Duration.zero);
      paused.resume.complete();

      final ExportSnapshot snapshot = await inProgress;
      await write;

      expect(snapshot.counts['foods'], 0);
      expect((await prepare()).counts['foods'], 1);
    },
  );
}

Map<String, Object?> _data(ExportSnapshot snapshot) =>
    jsonDecode(snapshot.file.contents) as Map<String, Object?>;

Map<String, Object?> _manifest(ExportSnapshot snapshot) =>
    _data(snapshot)['manifest']! as Map<String, Object?>;

Future<void> _day(
  HearthDatabase db,
  String id,
  DateTime date, {
  String userId = 'user-1',
}) async {
  await PlanStore(db).ensureDay(
    userId: userId,
    date: date,
    idFactory: () => id,
    updatedAt: _captured,
  );
}

Future<void> _entry(
  HearthDatabase db,
  String id,
  String dayId, {
  String refId = 'recipe-1',
  bool logged = false,
  bool planned = true,
  String? snapshot,
}) async {
  await db
      .into(db.mealPlanEntries)
      .insert(
        MealPlanEntriesCompanion.insert(
          id: id,
          dayId: dayId,
          mealSlot: 'dinner',
          refType: 'recipe',
          refId: refId,
          servings: 1,
          isLogged: Value<bool>(logged),
          isPlanned: Value<bool>(planned),
          loggedAt: Value<DateTime?>(logged ? _captured : null),
          macroSnapshot: Value<String?>(snapshot),
          updatedAt: _captured,
        ),
      );
}

Future<void> _shoppingList(
  HearthDatabase db,
  String id, {
  String householdId = 'household-1',
}) async {
  await db
      .into(db.shoppingLists)
      .insert(
        ShoppingListsCompanion.insert(
          id: id,
          householdId: householdId,
          fromDate: _captured,
          toDate: _captured,
          updatedAt: _captured,
        ),
      );
}

Future<void> _shoppingItem(
  HearthDatabase db,
  String id,
  String listId, {
  String? foodId,
  String sourceRecipes = '',
  String contributions = '[]',
}) async {
  await db
      .into(db.shoppingListItems)
      .insert(
        ShoppingListItemsCompanion.insert(
          id: id,
          listId: listId,
          itemKey: id,
          name: id,
          foodId: Value<String?>(foodId),
          sourceRecipeIds: Value<String>(sourceRecipes),
          contributions: Value<String>(contributions),
          updatedAt: _captured,
        ),
      );
}

class _PausedRecipeStore extends RecipeStore {
  _PausedRecipeStore(super.database);

  final Completer<void> readStarted = Completer<void>();
  final Completer<void> resume = Completer<void>();

  @override
  Future<List<Recipe>> all({
    required String householdId,
    bool includeDeleted = false,
  }) async {
    final List<Recipe> result = await super.all(
      householdId: householdId,
      includeDeleted: includeDeleted,
    );
    readStarted.complete();
    await resume.future;
    return result;
  }
}
