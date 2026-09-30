import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

void main() {
  test(
    'multi-day assignment carries the count and its named serving to every day',
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
      final List<DateTime> days = <DateTime>[
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 3),
      ];
      final List<MealPlanEntry> added = await repo.assignAcrossDays(
        dates: days,
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'corn',
        servings: 6,
        servingOptionId: 'label-cup',
      );
      expect(added, hasLength(2));
      for (final DateTime date in days) {
        final MealPlanEntry entry = (await repo.entriesFor(date)).single;
        expect(entry.servings, 6);
        expect(entry.servingOptionId, 'label-cup');
        expect(entry.isLogged, isFalse);
        expect(entry.macroSnapshot, isNull);
      }
    },
  );
}
