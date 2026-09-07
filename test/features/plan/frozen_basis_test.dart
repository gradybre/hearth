import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Correcting a portion uses the basis the meal was logged on (spec §4).
///
/// Rule 3: editing a food later must never rewrite what was already eaten. A
/// portion correction is the one screen that writes a *new* snapshot for an
/// old meal, so it is the one place that rule can be broken from the inside.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  /// The food as it stands *today* — someone corrected the label since.
  Food yoghurtNow() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'pot',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 200, proteinG: 20),
      ),
    ],
  );

  /// What was actually eaten, months ago, when the pot said 170.
  const Macros asEaten = Macros(kcal: 170, proteinG: 17);

  testWidgets('a later edit to the food does not change the old meal', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[yoghurtNow()],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'e-yog',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'f-yoghurt',
          servings: 1,
        ).log(
          liveMacros: asEaten,
          at: DateTime.utc(2026, 6, 1, 8),
          label: 'Greek yoghurt',
          coverage: NutrientCoverage.ofOne(asEaten),
        ),
      ],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    double kcalOf(String? snapshot) =>
        ((jsonDecode(snapshot!) as Map<String, Object?>)['kcal']! as num)
            .toDouble();

    expect(
      kcalOf((await db.select(db.mealPlanEntries).get()).single.macroSnapshot),
      closeTo(170, 0.001),
    );

    // Correct the portion — to the same portion. Nothing about the meal
    // changed, and nothing about it should.
    await tester.longPress(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Edit portion'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Update'));
    await pumpFrames(tester, frames: 20);

    expect(
      kcalOf((await db.select(db.mealPlanEntries).get()).single.macroSnapshot),
      closeTo(170, 0.001),
      reason:
          'the meal was re-costed from the food as it stands today, so an '
          'edit made months later rewrote what was eaten',
    );
  });

  testWidgets('and halving it halves what was eaten, not what it costs now', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[yoghurtNow()],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'e-yog',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'f-yoghurt',
          servings: 1,
        ).log(
          liveMacros: asEaten,
          at: DateTime.utc(2026, 6, 1, 8),
          label: 'Greek yoghurt',
          coverage: NutrientCoverage.ofOne(asEaten),
        ),
      ],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    await tester.longPress(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Edit portion'));
    await pumpFrames(tester, frames: 12);

    await tester.enterText(find.byType(TextField).last, '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, frames: 8);
    await tester.tap(find.text('Update'));
    await pumpFrames(tester, frames: 20);

    double kcalOf(String? snapshot) =>
        ((jsonDecode(snapshot!) as Map<String, Object?>)['kcal']! as num)
            .toDouble();

    expect(
      kcalOf((await db.select(db.mealPlanEntries).get()).single.macroSnapshot),
      closeTo(85, 0.001),
      reason: 'half of the meal that was eaten is 85, not half of today\'s 200',
    );
  });
}
