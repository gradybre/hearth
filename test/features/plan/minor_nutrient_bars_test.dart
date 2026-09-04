import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Fibre, sodium and cholesterol on the plan (spec §5.6).
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  Food food(String name, Macros macros) => aFood(
    name,
    id: 'f-${name.toLowerCase()}',
    servingOptions: <ServingOption>[
      aServing(amount: 100, unit: Units.gram, macros: macros),
    ],
  );

  MealPlanEntry logged(String foodId, Macros macros) => MealPlanEntry(
    id: 'e-$foodId',
    dayId: 'day-1',
    slot: MealSlot.lunch,
    refType: PlanRefType.food,
    refId: foodId,
    servings: 1,
  ).log(liveMacros: macros, at: DateTime.utc(2026, 8, 31, 12), label: foodId);

  Future<HearthDatabase> openDay(
    WidgetTester tester, {
    required Macros eaten,
    MacroTargets? withTargets,
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[food('Oats', eaten)],
      entries: <MealPlanEntry>[logged('f-oats', eaten)],
      targets: withTargets ?? targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    return db;
  }

  testWidgets('a day whose foods know nothing shows no bars at all', (
    WidgetTester tester,
  ) async {
    // Three rows of dashes would be worse than an absence, and "0 of 28 g"
    // would be a claim nobody made.
    await openDay(tester, eaten: const Macros(kcal: 400, proteinG: 20));

    expect(find.textContaining('of 28 g'), findsNothing);
    expect(find.text('Fibre'), findsNothing);
  });

  testWidgets('one that knows fibre shows it against the Daily Value', (
    WidgetTester tester,
  ) async {
    await openDay(
      tester,
      eaten: const Macros(kcal: 400, proteinG: 20, fiberG: 14),
    );

    expect(find.text('Fibre'), findsOneWidget);
    expect(find.text('14 of 28 g'), findsOneWidget);
    // Sodium was never known, so it is absent rather than zero.
    expect(find.text('Sodium'), findsNothing);
  });

  testWidgets('fibre reaching its target reads as done, not as over', (
    WidgetTester tester,
  ) async {
    // The distinction the whole feature turns on. Passing a floor is an
    // achievement; the same fraction of sodium is not.
    await openDay(tester, eaten: const Macros(kcal: 400, fiberG: 30));

    expect(find.text('on target'), findsOneWidget);
    expect(find.textContaining('over'), findsNothing);
  });

  testWidgets('sodium past its budget says so in words, not just colour', (
    WidgetTester tester,
  ) async {
    // Never colour alone (§6.3).
    await openDay(tester, eaten: const Macros(kcal: 400, sodiumMg: 2600));

    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('2600 of 2300 mg'), findsOneWidget);
    // The unit spaced the way the rest of the row spaces it.
    expect(find.text('300 mg over'), findsOneWidget);
  });

  testWidgets('sodium nearly spent is quiet, not encouraging', (
    WidgetTester tester,
  ) async {
    // 2,200 of 2,300 mg is not doing well, it is nearly over — and a row that
    // said "on target" there would praise the thing the budget exists to
    // discourage.
    await openDay(tester, eaten: const Macros(kcal: 400, sodiumMg: 2200));

    expect(find.text('2200 of 2300 mg'), findsOneWidget);
    expect(find.text('on target'), findsNothing);
    expect(find.textContaining('over'), findsNothing);
    expect(find.text('left'), findsNothing);
  });

  testWidgets('and a household target replaces the Daily Value', (
    WidgetTester tester,
  ) async {
    await openDay(
      tester,
      eaten: const Macros(kcal: 400, fiberG: 14),
      withTargets: const MacroTargets(
        kcal: 2000,
        proteinG: 150,
        carbG: 200,
        fatG: 70,
        fiberG: 40,
      ),
    );

    expect(find.text('14 of 40 g'), findsOneWidget);
  });

  testWidgets('the targets sheet leaves them blank for the Daily Value', (
    WidgetTester tester,
  ) async {
    // A field pre-filled with 28 would be indistinguishable afterwards from a
    // 28 somebody typed, and the two mean different things.
    final HearthDatabase db = await openDay(
      tester,
      eaten: const Macros(kcal: 400, fiberG: 14),
    );
    // `.last` is the card's own heading; the first is the page title, and
    // only the card opens the sheet.
    await tester.tap(find.text('Today').last);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Fibre g'), findsOneWidget);
    expect(
      find.textContaining('Leave blank for the Daily Values'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save targets'));
    await pumpFrames(tester, frames: 20);

    final List<MacroTargetRow> rows = await db.select(db.macroTargets).get();
    expect(rows.single.fiberG, isNull);
    expect(rows.single.sodiumMg, isNull);
  });
}
