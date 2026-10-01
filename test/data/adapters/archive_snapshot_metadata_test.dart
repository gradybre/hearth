import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';

import '../../support/fixtures.dart';

void main() {
  test(
    'metadata captures scoped deletion/photo evidence without changing v2 JSON',
    () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final DateTime now = DateTime.utc(2026, 10, 1, 12);
      final RecipeStore recipes = RecipeStore(db);
      for (final String home in <String>['home', 'other']) {
        await recipes.upsert(
          aRecipe(id: 'recipe-$home', householdId: home),
          updatedAt: now,
        );
        await db
            .into(db.recipePhotos)
            .insert(
              RecipePhotoRow(
                recipeId: 'recipe-$home',
                fileName: 'recipe-$home-1.jpg',
                syncAttempts: 0,
                updatedAt: now,
              ),
            );
      }
      for (final String user in <String>['me', 'partner']) {
        await db
            .into(db.mealPlanDays)
            .insert(
              MealPlanDayRow(
                id: 'day-$user',
                userId: user,
                day: DateTime.utc(2026, 9, 30),
                updatedAt: now,
              ),
            );
        await db
            .into(db.mealPlanEntries)
            .insert(
              MealPlanEntryRow(
                id: 'entry-$user',
                dayId: 'day-$user',
                mealSlot: 'dinner',
                refType: 'recipe',
                refId: 'recipe-home',
                servings: 1,
                isPlanned: true,
                isLogged: true,
                macroSnapshot: '{"label":"Frozen", "kcal":10, "future":[1,2]}',
                updatedAt: now,
              ),
            );
      }
      final DataExport export = DataExport(
        database: db,
        recipes: recipes,
        foods: FoodStore(db),
        clock: () => now,
      );
      final ExportSnapshot before = await export.prepare(
        householdId: 'home',
        userId: 'me',
      );
      await (db.update(db.recipePhotos)
            ..where(($RecipePhotosTable p) => p.recipeId.equals('recipe-home')))
          .write(
            const RecipePhotosCompanion(
              fileName: Value<String?>('recipe-home-2.jpg'),
            ),
          );
      final ExportSnapshot after = await export.prepare(
        householdId: 'home',
        userId: 'me',
      );
      expect(
        after.file.contents,
        before.file.contents,
        reason: 'Alongside metadata must not rewrite standalone JSON.',
      );
      expect(before.entryDeletionStates, <String, bool>{'entry-me': false});
      expect(before.entryServingOptionIds, <String, String?>{'entry-me': null});
      expect(
        () => before.entryServingOptionIds['entry-partner'] = 'foreign',
        throwsUnsupportedError,
      );
      expect(after.entryDeletionStates, <String, bool>{'entry-me': false});
      expect(before.photoReferences.single.recipeId, 'recipe-home');
      expect(before.photoReferences.single.localFileName, 'recipe-home-1.jpg');
      expect(after.photoReferences.single.localFileName, 'recipe-home-2.jpg');
      final Map<String, Object?> original =
          jsonDecode(before.file.contents) as Map<String, Object?>;
      expect(original['version'], 2);
      final Map<String, Object?> entry =
          (original['meal_plan_entries']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(entry.containsKey('is_deleted'), isFalse);
      expect(entry['macro_snapshot'], <String, Object?>{
        'label': 'Frozen',
        'kcal': 10,
        'future': <int>[1, 2],
      });
      expect(
        () => after.entryDeletionStates['entry-me'] = false,
        throwsUnsupportedError,
      );
      expect(after.photoReferences.clear, throwsUnsupportedError);
      await (db.delete(
        db.mealPlanEntries,
      )..where(($MealPlanEntriesTable e) => e.id.equals('entry-me'))).go();
      final ExportSnapshot removed = await export.prepare(
        householdId: 'home',
        userId: 'me',
      );
      expect(removed.entryDeletionStates, isEmpty);
      expect(removed.entryServingOptionIds, isEmpty);
      expect(
        (jsonDecode(removed.file.contents)
            as Map<String, Object?>)['meal_plan_entries'],
        isEmpty,
      );
      expect(
        (jsonDecode(after.file.contents)
            as Map<String, Object?>)['meal_plan_entries'],
        hasLength(1),
      );
    },
  );
}
