import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/target_schedule.dart';

void main() {
  test(
    'reviewed export owns personal target history, stops, nulls and zeroes',
    () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final PlanStore store = PlanStore(db);
      final DateTime captured = DateTime.utc(2026, 10, 1, 12);
      const MacroTargets authored = MacroTargets(
        kcal: 2000,
        proteinG: 120,
        carbG: 230,
        fatG: 70,
        fiberG: null,
        sodiumMg: 0,
        cholesterolMg: 250,
      );
      for (final String user in <String>['me', 'partner']) {
        await store.setOngoingTarget(
          boundary: OngoingTargetBoundary.active(
            userId: user,
            weekStart: DateTime(2026, 9, 21),
            targets: authored,
          ),
          updatedAt: captured,
        );
      }
      await store.setTargets(
        userId: 'me',
        date: DateTime(2026, 9, 28),
        targets: authored,
        idFactory: () => 'weekly',
        updatedAt: captured,
      );
      await store.setOngoingTarget(
        boundary: OngoingTargetBoundary.stopped(
          userId: 'me',
          weekStart: DateTime(2026, 9, 28),
        ),
        updatedAt: captured,
      );
      final ExportSnapshot snapshot = await DataExport(
        database: db,
        recipes: RecipeStore(db),
        foods: FoodStore(db),
        clock: () => captured,
      ).prepare(householdId: 'home', userId: 'me');
      final Map<String, dynamic> json =
          jsonDecode(snapshot.file.contents) as Map<String, dynamic>;
      final List<dynamic> history =
          json['ongoing_macro_targets'] as List<dynamic>;
      expect(history, hasLength(2));
      expect(history.every((dynamic row) => row['user_id'] == 'me'), isTrue);
      final Map<String, dynamic> active = history.singleWhere(
        (dynamic row) => row['is_stopped'] == false,
      ) as Map<String, dynamic>;
      final Map<String, dynamic> stopped = history.singleWhere(
        (dynamic row) => row['is_stopped'] == true,
      ) as Map<String, dynamic>;
      expect(active['week_start_date'], '2026-09-21');
      expect(active['fiber_g'], isNull);
      expect(active['sodium_mg'], 0);
      expect(active['cholesterol_mg'], 250);
      expect(stopped['week_start_date'], '2026-09-28');
      for (final String key in <String>[
        'kcal',
        'protein_g',
        'carb_g',
        'fat_g',
        'fiber_g',
        'sodium_mg',
        'cholesterol_mg',
      ]) {
        expect(stopped.containsKey(key), isTrue);
        expect(stopped[key], isNull);
      }
      expect(snapshot.counts['ongoing_macro_targets'], 2);
      expect(json['macro_targets'], hasLength(1));
      final String reviewed = snapshot.file.contents;
      await store.setOngoingTarget(
        boundary: OngoingTargetBoundary.active(
          userId: 'me',
          weekStart: DateTime(2026, 9, 28),
          targets: authored,
        ),
        updatedAt: captured.add(const Duration(minutes: 1)),
      );
      expect(snapshot.file.contents, reviewed);
      expect(stopped['is_stopped'], isTrue);
    },
  );
}
