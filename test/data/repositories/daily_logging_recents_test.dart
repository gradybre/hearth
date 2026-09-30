import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';

void main() {
  test('meal recents read personal history and keep the meal-specific serving basis', () async {
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);
    DateTime clock = DateTime(2026, 9, 28, 8);
    PlanRepository repository(String userId) => PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: userId,
      clock: () => clock,
    );
    final PlanRepository me = repository('me');
    Future<void> add(
      PlanRepository repo,
      MealSlot slot,
      String foodId,
      double servings,
      String servingId,
    ) async {
      await repo.add(
        date: clock,
        slot: slot,
        refType: PlanRefType.food,
        refId: foodId,
        servings: servings,
        servingOptionId: servingId,
        loggedMacros: const Macros(kcal: 100),
        label: foodId,
      );
    }

    await add(me, MealSlot.breakfast, 'oats', 2, 'pot');
    clock = DateTime(2026, 9, 28, 12);
    await add(me, MealSlot.lunch, 'oats', 4, 'bowl');
    clock = DateTime(2026, 9, 29, 8);
    await add(
      repository('partner'),
      MealSlot.breakfast,
      'partners-oats',
      8,
      'pot',
    );
    final RecentLog breakfast = (await me.recentLogs(
      preferredSlot: MealSlot.breakfast,
    )).single;
    final RecentLog all = (await me.recentLogs()).single;
    expect(breakfast.refId, 'oats');
    expect(breakfast.servings, 2);
    expect(breakfast.servingOptionId, 'pot');
    expect(breakfast.mealSlot, MealSlot.breakfast);
    expect(all.servings, 4);
    expect(all.servingOptionId, 'bowl');
    expect(all.timesLogged, 2);
  });
}
