import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/widgets/minor_nutrient_bars.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
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

  MealPlanEntry logged(String foodId, Macros macros) =>
      MealPlanEntry(
        id: 'e-$foodId',
        dayId: 'day-1',
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: foodId,
        servings: 1,
      ).log(
        liveMacros: macros,
        at: DateTime.utc(2026, 8, 31, 12),
        label: foodId,
        coverage: NutrientCoverage.ofOne(macros),
      );

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

  testWidgets('a day whose foods know nothing still shows all three', (
    WidgetTester tester,
  ) async {
    // Hiding them was the first design, and it is why this was reported as
    // three missing bars rather than three empty ones: an absent row and a
    // feature that was never built look the same from the sofa.
    await openDay(tester, eaten: const Macros(kcal: 400, proteinG: 20));

    expect(find.text('Fibre'), findsOneWidget);
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('Cholesterol'), findsOneWidget);

    // A dash, never a zero. "0 of 28 g" would claim the day had no fibre,
    // when the truth is that nothing eaten was ever asked.
    expect(find.text('— of 28 g'), findsOneWidget);
    expect(find.textContaining('0 of 28 g'), findsNothing);

    // And it says which silence this is.
    expect(find.textContaining('did not say'), findsWidgets);
  });

  testWidgets('a stated half gram is not rounded away to nothing', (
    WidgetTester tester,
  ) async {
    // 0.4 printed as "0 of 28 g" would be indistinguishable from a stated
    // zero, which is the one distinction this whole row exists to draw.
    await openDay(tester, eaten: const Macros(kcal: 400, fiberG: 0.4));

    expect(find.text('0.4 of 28 g'), findsOneWidget);
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
    // Sodium is there too, and says nobody has stated one — a dash rather
    // than a zero, because "0 of 2300 mg" would be a claim the day never
    // made. Hiding it was the first design and it made the whole feature
    // invisible: an absent row and an unbuilt feature look the same.
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('— of 2300 mg'), findsOneWidget);
    expect(find.text('0 of 2300 mg'), findsNothing);
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

  group('on the week, which is where a trend lives', () {
    testWidgets('shows the three there too, and says which silence it is', (
      WidgetTester tester,
    ) async {
      // The week had its guard removed and the day did not, which is how a
      // fix for this shipped once already without landing on the screen it
      // was reported from. One test each, so neither can regress alone.
      await pumpHearthApp(tester, targets: targets);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Week'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Fibre'), findsOneWidget);
      expect(find.text('Sodium'), findsOneWidget);
      expect(find.text('Cholesterol'), findsOneWidget);

      // A dash and the target, never a zero — and it says that the silence
      // is an empty day rather than foods that were asked and did not know.
      expect(find.text('— of 2300 mg'), findsOneWidget);
      expect(find.text('nothing logged yet'), findsWidgets);
    });
  });

  group('what the note says, in each of its states', () {
    // The user-visible half of the coverage work, and it had no test at all:
    // the old assertion matched `textContaining('did not say')`, which the
    // single-clause version already satisfied.
    Widget barOf(MinorCoverage coverage, {int silent = 0}) => MaterialApp(
      theme: HearthTheme.light(),
      home: Scaffold(
        body: MinorNutrientBars(
          progress: DayProgress.from(
            consumed: const Macros(kcal: 400, fiberG: 5),
            targets: targets,
            countedParts: 2,
            unknownCounts: <MinorNutrient, int>{MinorNutrient.fiber: silent},
            coverage: NutrientCoverage(<MinorNutrient, MinorCoverage>{
              MinorNutrient.fiber: coverage,
            }),
          ),
        ),
      ),
    );

    testWidgets('a floor says it is one', (WidgetTester tester) async {
      await tester.pumpWidget(barOf(MinorCoverage.partial));
      await pumpFrames(tester);

      expect(find.textContaining('at least this'), findsOneWidget);
    });

    testWidgets('history from before says that instead', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(barOf(MinorCoverage.notRecorded));
      await pumpFrames(tester);

      expect(find.textContaining('before Hearth'), findsOneWidget);
    });

    testWidgets('and both can be true at once, so both are said', (
      WidgetTester tester,
    ) async {
      // "1 of 2 did not say" on its own implies the other one fully did. It
      // did not — it was missing an ingredient's worth.
      await tester.pumpWidget(barOf(MinorCoverage.partial, silent: 1));
      await pumpFrames(tester);

      expect(find.textContaining('1 of 2 did not say'), findsOneWidget);
      expect(find.textContaining('at least this'), findsOneWidget);
    });

    testWidgets('a complete total says nothing at all', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(barOf(MinorCoverage.complete));
      await pumpFrames(tester);

      expect(find.textContaining('at least this'), findsNothing);
      expect(find.textContaining('did not say'), findsNothing);
    });
  });
}
