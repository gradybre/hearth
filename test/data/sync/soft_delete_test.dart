import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/mappers/shopping_mapper.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:hearth/data/repositories/collection_repository.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

/// A deletion reaches the other phone (spec §7.1, R03).
///
/// Five tables removed rows outright, and a pull only ever sees rows that
/// exist — so a meal your partner deleted stayed on your phone for ever. They
/// soft-delete now, the way recipes and foods always have.
void main() {
  late HearthDatabase db;
  late RemoteRows rows;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    rows = RemoteRows(db);
  });

  tearDown(() => db.close());

  group('which tables say a row is gone rather than removing it', () {
    test('the five that used to vanish, and not the two that reconcile', () {
      // The membership tables are fetched whole every pass and reconciled by
      // replacement, so absence there is already read correctly as removal.
      // Giving them a flag as well would be a second mechanism for the same
      // fact, and the two would eventually disagree.
      expect(
        SupabaseRemoteGateway.softDeleteTables,
        containsAll(<String>[
          'meal_plan_entries',
          'shopping_list_items',
          'collections',
          'plan_templates',
          'ingredient_matches',
        ]),
      );
      expect(
        SupabaseRemoteGateway.softDeleteTables,
        isNot(contains('recipe_favorites')),
      );
      expect(
        SupabaseRemoteGateway.softDeleteTables,
        isNot(contains('recipe_collections')),
      );
    });
  });

  group('a row deleted on the other phone', () {
    Future<void> seedDay() => db
        .into(db.mealPlanDays)
        .insertOnConflictUpdate(
          MealPlanDayRow(
            id: 'day-1',
            userId: 'user-1',
            day: DateTime.utc(2026, 8, 28),
            updatedAt: t0,
          ),
        );

    Map<String, Object?> entry({required bool deleted}) => <String, Object?>{
      'id': 'entry-1',
      'meal_plan_day_id': 'day-1',
      'meal_slot': 'dinner',
      'ref_type': 'recipe',
      'ref_id': 'recipe-1',
      'servings': 1,
      'is_planned': false,
      'is_logged': true,
      'logged_at': t0.toIso8601String(),
      'macro_snapshot': jsonEncode(<String, Object?>{'kcal': 400}),
      'is_deleted': deleted,
      'updated_at': t0.toIso8601String(),
    };

    test('is taken off this one too', () async {
      await seedDay();
      await rows.applyEntry(entry(deleted: false));
      expect(await db.select(db.mealPlanEntries).get(), hasLength(1));

      await rows.applyEntry(entry(deleted: true));

      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    });

    test(
      'and one this phone never had is not created just to delete it',
      () async {
        // The pull reaches back past the checkpoint, so a row deleted before
        // this device ever saw it arrives as an ordinary record. Inserting it
        // and then removing it would be a flicker of a meal nobody logged.
        await seedDay();

        await rows.applyEntry(entry(deleted: true));

        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      },
    );

    test('a collection deleted elsewhere goes', () async {
      Map<String, Object?> collection({required bool deleted}) =>
          <String, Object?>{
            'id': 'col-1',
            'household_id': 'house-1',
            'name': 'Weeknights',
            'sort_order': 0,
            'is_deleted': deleted,
            'updated_at': t0.toIso8601String(),
          };

      await rows.applyCollection(collection(deleted: false));
      expect(await db.select(db.collections).get(), hasLength(1));

      await rows.applyCollection(collection(deleted: true));

      expect(await db.select(db.collections).get(), isEmpty);
    });

    test('a saved week deleted elsewhere goes', () async {
      Map<String, Object?> template({required bool deleted}) =>
          <String, Object?>{
            'id': 'tpl-1',
            'user_id': 'user-1',
            'name': 'Usual week',
            'entries': const <Object?>[],
            'is_deleted': deleted,
            'updated_at': t0.toIso8601String(),
          };

      await rows.applyPlanTemplate(template(deleted: false));
      expect(await db.select(db.planTemplates).get(), hasLength(1));

      await rows.applyPlanTemplate(template(deleted: true));

      expect(await db.select(db.planTemplates).get(), isEmpty);
    });
  });

  group('a write that puts a deleted row back', () {
    // The upsert for four of these tables resolves on the id, and for
    // `ingredient_matches` on its unique index. Either way, writing a row
    // that is already tombstoned only revives it if the payload says so —
    // and Undo, Restore, and re-adding the same name all do exactly that.
    test('says so in the payload, for every table that can be tombstoned', () {
      final Map<String, Object?> entry = PlanMapper.entryToJson(
        const MealPlanEntry(
          id: 'entry-1',
          dayId: 'day-1',
          slot: MealSlot.dinner,
          refType: PlanRefType.recipe,
          refId: 'recipe-1',
          servings: 1,
        ),
        updatedAt: DateTime.utc(2026, 8, 28, 12),
      );
      expect(entry['is_deleted'], false);

      final Map<String, Object?> item = ShoppingMapper.itemToJson(
        ShoppingItemRow(
          id: 'item-1',
          listId: 'list-1',
          itemKey: 'milk',
          name: 'Milk',
          checked: false,
          isManual: false,
          sourceRecipeIds: '',
          sortOrder: 0,
          hasUnquantified: false,
          plannedRest: '',
          updatedAt: DateTime.utc(2026, 8, 28, 12),
        ),
      );
      expect(item['is_deleted'], false);
    });

    test(
      'including the three built by hand inside their repositories',
      () async {
        // These are written inline rather than by a mapper, which is exactly
        // where a key gets dropped without anything noticing.
        final PendingWriteStore queue = PendingWriteStore(db);

        await CollectionRepository(
          database: db,
          store: CollectionStore(db),
          queue: queue,
          householdId: 'house-1',
          userId: 'user-1',
        ).createCollection('Weeknights');

        await IngredientMatchRepository(
          database: db,
          store: IngredientMatchStore(db),
          queue: queue,
          householdId: 'house-1',
        ).rememberNoMatch('olive oil');

        final Map<String, Map<String, Object?>> byTable =
            <String, Map<String, Object?>>{
              for (final PendingWrite write in await queue.pending())
                if (write.operation == WriteOperation.upsert)
                  write.entityTable: write.payload,
            };

        for (final String table in <String>[
          'collections',
          'ingredient_matches',
        ]) {
          expect(
            byTable[table],
            isNotNull,
            reason: '$table queued nothing to check',
          );
          expect(
            byTable[table]!['is_deleted'],
            false,
            reason: '$table would write a row that stays a tombstone',
          );
        }
      },
    );
  });

  group('a cookbook deleted with recipes still in it', () {
    // The chain that made this worse than the bug it fixes. The delete is a
    // tombstone now, so the server-side cascade that used to take the
    // membership rows with it never fires; their own policy still returns
    // them, because it asks about the recipe rather than the parent. Locally
    // the collection row goes and the local cascade takes the memberships
    // with it — so re-inserting those pairs breaks the local foreign key, the
    // exception escapes the whole pull, and every sync on both phones fails
    // from then on, for ever, because the orphans never go away.
    test('does not take every future sync down with it', () async {
      await db
          .into(db.collections)
          .insertOnConflictUpdate(
            CollectionRow(
              id: 'col-1',
              householdId: 'house-1',
              name: 'Weeknights',
              sortOrder: 0,
              updatedAt: t0,
            ),
          );

      // The cookbook is deleted elsewhere and the tombstone arrives.
      await rows.applyCollection(<String, Object?>{
        'id': 'col-1',
        'household_id': 'house-1',
        'name': 'Weeknights',
        'sort_order': 0,
        'is_deleted': true,
        'updated_at': t0.toIso8601String(),
      });

      // The server still hands over the membership rows underneath it.
      await expectLater(
        rows.replaceMemberships(
          remote: <(String, String)>{('col-1', 'recipe-1')},
          hasPendingWrite: (String _) async => false,
          now: t0,
        ),
        completes,
      );
      expect(await db.select(db.recipeCollections).get(), isEmpty);
    });

    test(
      'and a favourite for a recipe this device has not got is skipped too',
      () async {
        await expectLater(
          rows.replaceFavorites(
            userId: 'user-1',
            remoteRecipeIds: <String>{'recipe-never-pulled'},
            hasPendingWrite: (String _) async => false,
            now: t0,
          ),
          completes,
        );
        expect(await db.select(db.recipeFavorites).get(), isEmpty);
      },
    );
  });

  group('a forgotten ingredient answer', () {
    test('goes even when this device kept a different id for it', () async {
      // The insert path resolves on (household, wording) precisely because a
      // local row may still carry a random id rather than the derived one. A
      // tombstone matching on the id the insert does not trust would leave
      // the wording in place, quietly answering ingredients the household
      // said to stop answering.
      await db
          .into(db.ingredientMatches)
          .insert(
            IngredientMatchesCompanion.insert(
              id: 'a-random-legacy-id',
              householdId: 'house-1',
              ingredientString: 'olive oil',
              updatedAt: t0,
            ),
          );

      await rows.applyIngredientMatch(<String, Object?>{
        'id': 'the-derived-id',
        'household_id': 'house-1',
        'ingredient_string': 'olive oil',
        'is_deleted': true,
        'updated_at': t0.toIso8601String(),
      });

      expect(await db.select(db.ingredientMatches).get(), isEmpty);
    });
  });

  group('a shopping line deleted elsewhere', () {
    test('comes off the list here', () async {
      await db
          .into(db.shoppingLists)
          .insertOnConflictUpdate(
            ShoppingListRow(
              id: 'list-1',
              householdId: 'house-1',
              fromDate: DateTime.utc(2026, 8, 24),
              toDate: DateTime.utc(2026, 8, 30),
              status: 'draft',
              updatedAt: t0,
            ),
          );
      Map<String, Object?> item({required bool deleted}) => <String, Object?>{
        'id': 'item-1',
        'shopping_list_id': 'list-1',
        'item_key': 'milk',
        'raw_name': 'Milk',
        'checked': false,
        'is_manual': true,
        'sort_order': 0,
        'has_unquantified': false,
        'source_recipe_ids': const <String>[],
        'is_deleted': deleted,
        'updated_at': t0.toIso8601String(),
      };

      await rows.applyShoppingItem(item(deleted: false));
      expect(await db.select(db.shoppingListItems).get(), hasLength(1));

      await rows.applyShoppingItem(item(deleted: true));

      expect(await db.select(db.shoppingListItems).get(), isEmpty);
    });
  });
}
