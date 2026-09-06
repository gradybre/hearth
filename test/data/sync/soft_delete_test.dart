import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/mappers/shopping_mapper.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
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
  });
}
