import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';

void main() {
  test(
    'a stale planned save cannot rewrite a meal that was logged meanwhile',
    () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final PlanRepository repo = PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: PendingWriteStore(db),
        userId: 'user',
      );
      final DateTime date = DateTime(2026, 9, 30);
      final MealPlanEntry planned = await repo.add(
        date: date,
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'food',
        servings: 1,
        servingOptionId: 'original',
      );
      final MealPlanEntry? logged = await repo.logEntry(
        planned.id,
        liveMacros: const Macros(kcal: 100),
        label: 'Food',
        liveCoverage: const NutrientCoverage.notRecorded(),
      );
      final MealPlanEntry? result = await repo.updateEntry(
        planned.id,
        servings: 3,
        servingOptionId: 'another',
        requirePlanned: true,
      );
      expect(
        result,
        isNull,
        reason: 'the planned editor must be told its save did not happen',
      );
      final MealPlanEntry saved = (await repo.entriesFor(date)).single;
      expect(saved.servings, 1);
      expect(saved.servingOptionId, 'original');
      expect(saved.macroSnapshot, logged!.macroSnapshot);
    },
  );
  test(
    'a removed planned meal is not recreated by an open portion editor',
    () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final PlanRepository repo = PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: PendingWriteStore(db),
        userId: 'user',
      );
      final DateTime date = DateTime(2026, 9, 30);
      final MealPlanEntry planned = await repo.add(
        date: date,
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'food',
        servings: 1,
      );
      await repo.removeEntry(planned.id);
      expect(
        await repo.updateEntry(planned.id, servings: 3, requirePlanned: true),
        isNull,
      );
      expect(await repo.entriesFor(date), isEmpty);
    },
  );
}
