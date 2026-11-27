import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The day's summary, compact (spec §5.6, U01).
///
/// The rings are the better picture of a day and the worse first screen: at
/// ordinary text they push the first meal below the fold, and the meals are
/// what the day is for.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  Future<HearthDatabase> openDay(
    WidgetTester tester, {
    Macros eaten = const Macros(kcal: 400, proteinG: 20),
    Size size = const Size(390, 844),

    /// Whether anything has been logged into the day at all.
    ///
    /// False is the ordinary state of a morning, and it is the one the
    /// summary used to have nothing to say about.
    bool logged = true,
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      size: size,
      foods: <Food>[
        aFood(
          'Oats',
          id: 'f-oats',
          servingOptions: <ServingOption>[
            aServing(amount: 100, unit: Units.gram, macros: eaten),
          ],
        ),
      ],
      entries: <MealPlanEntry>[
        if (logged)
          const MealPlanEntry(
            id: 'e-oats',
            dayId: 'day-1',
            slot: MealSlot.breakfast,
            refType: PlanRefType.food,
            refId: 'f-oats',
            servings: 1,
          ).log(
            liveMacros: eaten,
            at: DateTime.utc(2026, 9, 7, 8),
            label: 'Oats',
            coverage: NutrientCoverage.ofOne(eaten),
          ),
      ],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    return db;
  }

  testWidgets('opens compact, and the first meal is above the fold', (
    WidgetTester tester,
  ) async {
    // The promise U01 makes: at 390x844 and ordinary text you can see what
    // you ate for breakfast without scrolling past a summary of it.
    await openDay(tester);

    // The meal itself, not just its heading. Expanded, the heading lands at
    // 806 of 844 — technically on screen, with everything it labels below
    // the fold — so asserting on the heading alone passes in both layouts
    // and proves nothing.
    final Rect meal = tester.getRect(find.text('Oats'));

    expect(
      meal.bottom,
      lessThanOrEqualTo(844),
      reason:
          'the first meal is ${meal.bottom.round()} points down, below the '
          'fold at ordinary text on a 390x844 phone',
    );
  });

  testWidgets('the day\u2019s figures are there before anything is logged', (
    WidgetTester tester,
  ) async {
    // Brendan's report: the daily macros only turned up once you had logged
    // something. A morning is the ordinary state of a day and the summary has
    // plenty to say about it — what the targets are, and that all of each one
    // is still to go.
    //
    // "Nothing logged yet" carries the claim a bare zero would otherwise
    // make, so the figures do not have to be withheld to stay honest.
    await openDay(tester, logged: false);

    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('0 of 2000 kcal'), findsOneWidget);
    expect(find.textContaining('Protein 0/150'), findsOneWidget);
    expect(find.textContaining('Carbs 0/200'), findsOneWidget);
    expect(find.textContaining('Fat 0/70'), findsOneWidget);
  });

  testWidgets('says all three minor nutrients, dash and all', (
    WidgetTester tester,
  ) async {
    // The compact view must not make them disappear again. An absent row and
    // a feature that was never built look the same from the sofa, which is
    // how this was reported the first time.
    await openDay(tester);

    expect(find.textContaining('Fiber'), findsWidgets);
    expect(find.textContaining('Sodium'), findsWidgets);
    expect(find.textContaining('Cholesterol'), findsWidgets);

    // A dash, never a zero: nothing eaten was ever asked about fiber.
    expect(find.textContaining('Fiber —'), findsOneWidget);
  });

  testWidgets('and the calories, with the word as well as the arrow', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    // The pair of numbers sits under the headline the pair was worked out
    // from, and the headline carries the unit: "1600 left" at 34pt, with no
    // kcal on it, reads as a quantity of nothing in particular.
    expect(find.text('400 of 2000 kcal'), findsOneWidget);
    expect(find.text('1600 kcal left'), findsOneWidget);
  });

  testWidgets('over target says over, not left', (WidgetTester tester) async {
    await openDay(tester, eaten: const Macros(kcal: 2400, proteinG: 20));

    expect(find.text('400 kcal over'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('Details brings the rings back, and Less puts them away', (
    WidgetTester tester,
  ) async {
    // The previously approved presentation is still there; it is one tap
    // away rather than in the way.
    await openDay(tester);
    expect(
      find.text('Fiber'),
      findsNothing,
      reason: 'the bars are the expanded view',
    );

    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Fiber'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);

    // Scrolled to before it is pressed, because the expanded card is taller
    // than the window: three rings, three bars and the calorie headline
    // above them put this control below the fold on a 844pt phone. A tap at
    // a point outside the view hits nothing and throws nothing, so without
    // this the card stayed open and the failure was reported against the
    // *next* line — "Details not found" — which is not where the fault was.
    await tester.ensureVisible(find.text('Less'));
    await tester.tap(find.text('Less'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Details'), findsOneWidget);
  });

  test('a stored choice is read back, not just written', () async {
    // The write had a test and the read did not, so replacing `build` with a
    // bare `false` — the preference stored and then permanently ignored —
    // left every test in this file green.
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);
    await PreferenceStore(db)
        .writeFlag(PreferenceStore.daySummaryExpanded, value: true);

    final ProviderContainer container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    expect(await container.read(daySummaryExpandedProvider.future), isTrue);
  });

  testWidgets('a partial total is marked as a floor, not printed bare', (
    WidgetTester tester,
  ) async {
    // The defect §5.6 exists to prevent, in the view everyone now sees by
    // default: a running total that does not account for everything eaten
    // reads exactly like one that does.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Oats',
          id: 'f-oats',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 200, fiberG: 14),
            ),
          ],
        ),
        aFood(
          'Milk',
          id: 'f-milk',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 60),
            ),
          ],
        ),
      ],
      entries: <MealPlanEntry>[
        for (final ({String id, Macros macros}) part
            in <({String id, Macros macros})>[
              (id: 'f-oats', macros: const Macros(kcal: 200, fiberG: 14)),
              (id: 'f-milk', macros: const Macros(kcal: 60)),
            ])
          MealPlanEntry(
            id: 'e-${part.id}',
            dayId: 'day-1',
            slot: MealSlot.breakfast,
            refType: PlanRefType.food,
            refId: part.id,
            servings: 1,
          ).log(
            liveMacros: part.macros,
            at: DateTime.utc(2026, 9, 7, 8),
            label: part.id,
            coverage: NutrientCoverage.ofOne(part.macros),
          ),
      ],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    expect(
      find.text('Fiber ≥14/28g'),
      findsOneWidget,
      reason:
          'a floor printed bare reads exactly like a complete total, which '
          'is the whole thing this column is for',
    );
  });

  testWidgets('and the choice is remembered on this device', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openDay(tester);

    await tester.tap(find.text('Details'));
    await pumpFrames(tester, frames: 12);

    expect(
      await PreferenceStore(db).readFlag(PreferenceStore.daySummaryExpanded),
      isTrue,
      reason: 'the choice was not written to the device',
    );
  });
}
