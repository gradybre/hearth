import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/log_sheet.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

void main() {
  final DateTime destination = DateTime(2026, 10, 2);
  final DateTime beforeMidnight = DateTime(2026, 10, 1, 23, 59);
  final DateTime afterMidnight = DateTime(2026, 10, 2, 0, 1);
  Food burger() => aFood(
    'Steakburger',
    id: 'burger',
    brand: "Freddy's",
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'one',
        label: '1 burger',
        amount: Quantity.of(1, Units.item),
        macros: const Macros(kcal: 460, proteinG: 26, carbG: 32, fatG: 24),
      ),
    ],
  );
  Future<void> open(
    WidgetTester tester, {
    required DateTime Function() clock,
  }) async {
    unawaited(
      showLogSheet(
        tester.element(find.byType(Scaffold).first),
        date: destination,
        slot: MealSlot.dinner,
        clock: clock,
      ),
    );
    await pumpFrames(tester, frames: 12);
  }

  Future<void> assertPlan(HearthDatabase db) async {
    final MealPlanEntryRow entry =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(
      entry.isLogged,
      isFalse,
      reason:
          'the visible planning action must not turn into eating at midnight',
    );
    expect(entry.macroSnapshot, isNull);
    expect(entry.mealSlot, 'dinner');
    expect((await db.select(db.mealPlanDays).get()).single.day, destination);
  }

  testWidgets('an unchanged Add to plan button still plans after midnight', (
    WidgetTester tester,
  ) async {
    DateTime clock = beforeMidnight;
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[burger()],
    );
    await open(tester, clock: () => clock);
    await tester.tap(find.text('Steakburger'));
    await pumpFrames(tester);
    expect(find.text('Dinner · Tomorrow'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add to plan'), findsOneWidget);
    clock = afterMidnight;
    // Deliberately no pump/rebuild between changing the clock and tapping
    // the still-visible action. Its intent must be the one the label promised.
    await tester.tap(find.text('Add to plan'));
    await pumpFrames(tester, frames: 16);
    await assertPlan(db);
  });

  testWidgets('a recent quick action retains its planning intent at midnight', (
    WidgetTester tester,
  ) async {
    DateTime clock = beforeMidnight;
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[burger()],
      recentLogs: <RecentLog>[
        RecentLog(
          refType: PlanRefType.food,
          refId: 'burger',
          label: 'Steakburger',
          servings: 2,
          lastLoggedAt: DateTime(2026, 9, 30),
          timesLogged: 1,
          mealSlot: MealSlot.dinner,
        ),
      ],
    );
    await open(tester, clock: () => clock);
    expect(find.text('add to plan · 2 × 1 burger'), findsOneWidget);
    clock = afterMidnight;
    await tester.tap(find.text('add to plan · 2 × 1 burger'));
    await pumpFrames(tester, frames: 16);
    await assertPlan(db);
    expect((await db.select(db.mealPlanEntries).get()).single.servings, 2);
  });

  testWidgets('a restaurant planning handoff remains a plan after midnight', (
    WidgetTester tester,
  ) async {
    DateTime clock = beforeMidnight;
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[burger()],
    );
    await open(tester, clock: () => clock);
    expect(find.text('Plan a restaurant meal'), findsOneWidget);
    clock = afterMidnight;
    await tester.tap(find.text('Plan a restaurant meal'));
    await pumpFrames(tester);
    await tester.tap(find.text("Freddy's").last);
    await pumpFrames(tester);
    await tester.tap(find.text('Steakburger').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Review meal'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).first, 'Friday burger');
    expect(find.text('Save and add to dinner'), findsOneWidget);
    await tester.tap(find.text('Save and add to dinner'));
    await pumpFrames(tester, frames: 24);
    await assertPlan(db);
  });
  testWidgets(
    'relative words refresh after midnight while the opening action stays planned',
    (WidgetTester tester) async {
      DateTime clock = beforeMidnight;
      final HearthDatabase db = await pumpHearthApp(
        tester,
        foods: <Food>[burger()],
      );
      await open(tester, clock: () => clock);
      await tester.tap(find.text('Steakburger'));
      await pumpFrames(tester);
      expect(find.text('Dinner · Tomorrow'), findsOneWidget);
      clock = afterMidnight;
      await tester.tap(find.byTooltip('Larger portion'));
      await pumpFrames(tester);
      expect(find.text('Dinner · Today'), findsOneWidget);
      expect(find.text('Dinner · Tomorrow'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Add to plan'), findsOneWidget);
      await tester.tap(find.text('Add to plan'));
      await pumpFrames(tester, frames: 16);
      await assertPlan(db);
      expect((await db.select(db.mealPlanEntries).get()).single.servings, 1.25);
    },
  );

  for (final DateTime clock in <DateTime>[
    afterMidnight,
    DateTime(2026, 10, 3),
  ]) {
    testWidgets(
      'a fresh sheet for ${clock.day == 2 ? 'today' : 'a past day'} still offers Log it',
      (WidgetTester tester) async {
        final HearthDatabase db = await pumpHearthApp(
          tester,
          foods: <Food>[burger()],
        );
        await open(tester, clock: () => clock);
        await tester.tap(find.text('Steakburger'));
        await pumpFrames(tester);
        expect(find.widgetWithText(FilledButton, 'Log it'), findsOneWidget);
        await tester.tap(find.text('Log it'));
        await pumpFrames(tester, frames: 16);
        expect(
          (await db.select(db.mealPlanEntries).get()).single.isLogged,
          isTrue,
        );
        expect(
          (await db.select(db.mealPlanDays).get()).single.day,
          destination,
        );
      },
    );
  }
}
