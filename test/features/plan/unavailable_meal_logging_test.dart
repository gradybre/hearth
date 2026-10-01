import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

void main() {
  for (final PlanRefType type in PlanRefType.values) {
    testWidgets('a missing planned ${type.name} explains why it cannot log', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(
        tester,
        entries: <MealPlanEntry>[
          MealPlanEntry(
            id: 'meal-missing',
            dayId: 'day-1',
            slot: MealSlot.breakfast,
            refType: type,
            refId: 'missing-source',
            servings: 2,
          ),
        ],
      );
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester, frames: 12);
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      await tester.tap(
        find.byKey(const ValueKey<String>('meal-log-meal-missing')),
      );
      await pumpFrames(tester, frames: 12);
      expect(await db.select(db.mealPlanEntries).get(), before);
      expect(
        find.text(
          'This ${type.name} is no longer in your library '
          'and cannot be logged.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('meal-cook-meal-missing')),
        findsNothing,
      );
    });
  }

  testWidgets('a removed serving cannot be logged as a zero-calorie meal', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[aFoodPer100g('Oats', id: 'oats', kcal: 380)],
      entries: const <MealPlanEntry>[
        MealPlanEntry(
          id: 'meal-oats',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'oats',
          servings: 2,
          servingOptionId: 'removed-pot',
        ),
      ],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    // The separate logging control must preserve the missing portion, never
    // freeze zero or silently select the food's current default instead.
    await tester.tap(find.byKey(const ValueKey<String>('meal-log-meal-oats')));
    await pumpFrames(tester, frames: 12);

    final MealPlanEntryRow stored =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(stored.isLogged, isFalse);
    expect(stored.macroSnapshot, isNull);
    expect(stored.servingOptionId, 'removed-pot');
    expect(stored.servings, 2);
    expect(
      find.textContaining('planned serving is no longer available'),
      findsOneWidget,
    );
  });
}
