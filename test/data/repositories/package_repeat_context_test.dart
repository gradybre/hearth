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
  test('Log again retains the serving its repeated count refers to', () async {
    final db = HearthDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var id = 0;
    final repository = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'u',
      idFactory: () => 'id-${id++}',
    );
    final source = await repository.add(
      date: DateTime(2026, 9, 19),
      slot: MealSlot.lunch,
      refType: PlanRefType.food,
      refId: 'corn',
      servings: 6,
      servingOptionId: 'label-cup',
      loggedMacros: const Macros(kcal: 100),
      label: 'Corn',
    );
    final repeated = await repository.logAgain(
      recent: RecentLogs.from([source]).single,
      date: DateTime(2026, 9, 20),
      slot: MealSlot.lunch,
      liveMacros: const Macros(kcal: 100),
    );
    expect(repeated.servingOptionId, 'label-cup');
    expect(repeated.macroSnapshot!.macros.kcal, 600);
  });
}
