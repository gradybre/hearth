import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/readable_archive_rows.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

void main() {
  for (final String? selected in <String?>['pot', null, 'removed']) {
    test('readable planned serving keeps selected basis $selected', () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final DateTime now = DateTime.utc(2026, 10, 1);
      final FoodStore foods = FoodStore(db);
      await foods.upsert(
        Food(
          id: 'yogurt',
          householdId: 'home',
          name: 'Yogurt',
          source: FoodSource.manual,
          servingOptions: <ServingOption>[
            ServingOption(
              id: 'spoon',
              label: 'Small spoon',
              amount: Quantity.of(10, Units.gram),
              macros: const Macros(kcal: 10, proteinG: 1, carbG: 1, fatG: 0),
            ),
            ServingOption(
              id: 'pot',
              label: 'One pot',
              amount: Quantity.of(170, Units.gram),
              macros: const Macros(kcal: 170, proteinG: 17, carbG: 17, fatG: 0),
            ),
          ],
        ),
        updatedAt: now,
      );
      for (final String user in <String>['me', 'partner']) {
        await db
            .into(db.mealPlanDays)
            .insert(
              MealPlanDayRow(
                id: 'day-$user',
                userId: user,
                day: now,
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
                refType: 'food',
                refId: 'yogurt',
                servings: 1.5,
                servingOptionId: selected,
                isPlanned: true,
                isLogged: false,
                updatedAt: now,
              ),
            );
      }
      final DataExport exporter = DataExport(
        database: db,
        recipes: RecipeStore(db),
        foods: foods,
        clock: () => now,
      );
      final ExportSnapshot snapshot = await exporter.prepare(
        householdId: 'home',
        userId: 'me',
      );
      final List<String> lines = ReadableArchiveRows(snapshot)
          .meals(logged: false)
          .skip(1)
          .toList();
      // This fixture has no commas, quotes or newlines in its data. CSV's
      // general escaping is tested separately by the archive suite.
      List<String> cells(String line) =>
          line.trim().substring(1, line.trim().length - 1).split('","');
      final List<String> headers = cells(lines.first);
      final List<String> values = cells(lines[1]);
      final Map<String, String> row = Map<String, String>.fromIterables(
        headers,
        values,
      );
      expect(
        lines,
        hasLength(2),
        reason: 'The partner’s private plan is excluded.',
      );
      expect(row['entry_servings'], '1.5');
      expect(row['entry_serving_option_id'], selected ?? '');
      expect(
        row['planned_serving_label'],
        selected == 'removed'
            ? ''
            : selected == null
            ? 'Small spoon'
            : 'One pot',
      );
      expect(
        row['planned_serving_amount'],
        selected == 'removed'
            ? ''
            : selected == null
            ? '10.0'
            : '170.0',
      );
      expect(row['planned_serving_unit'], selected == 'removed' ? '' : 'g');
      expect(
        row['planned_serving_basis'],
        selected == 'removed'
            ? 'selected serving unavailable at export'
            : selected == null
            ? 'first serving at export'
            : 'selected serving at export',
      );
      expect(
        row['entered_amount'],
        isEmpty,
        reason: 'No raw input amount was stored for this plan.',
      );
      expect(
        row['kcal'],
        isEmpty,
        reason: 'Planned nutrition is not frozen history.',
      );
      final Map<String, Object?> original =
          jsonDecode(snapshot.file.contents) as Map<String, Object?>;
      final Map<String, Object?> originalEntry =
          (original['meal_plan_entries']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(
        originalEntry.containsKey('serving_option_id'),
        isFalse,
        reason: 'Original versioned JSON remains unchanged in this group.',
      );
    });
  }
}
