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

/// Logging in the food's own servings (spec §5.6, U03).
///
/// A food knows several — "170 g pot", "100 g", "1 tbsp" — and logging could
/// only ever count the default one. Eating half a pot meant working out what
/// that was as a multiple of something else, in your head, in a kitchen.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'pot',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 170, proteinG: 17),
      ),
      ServingOption(
        id: 'hundred',
        label: '100 g',
        amount: Quantity.of(100, Units.gram),
        macros: const Macros(kcal: 100, proteinG: 10),
        isReference: true,
      ),
      ServingOption(
        id: 'spoon',
        label: '1 tbsp',
        amount: Quantity.of(1, Units.tbsp),
        macros: const Macros(kcal: 15, proteinG: 1.5),
      ),
    ],
  );

  Future<void> openPicker(WidgetTester tester) async {
    await pumpHearthApp(tester, foods: <Food>[yoghurt()], targets: targets);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('offers the food\'s own servings, in its own words', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    expect(find.text('Serving'), findsOneWidget);
    expect(find.text('170 g pot'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
  });

  testWidgets('and counts the one you chose, not the default', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    // The default pot is 170 kcal.
    expect(find.textContaining('170 kcal'), findsWidgets);

    await tester.tap(find.text('100 g'));
    await pumpFrames(tester, frames: 8);

    // 1 x 170 g, expressed in 100 g units, is 1.7 of them — and 1.7 x 100
    // kcal is the same 170. Switching the unit must not change the food.
    expect(find.textContaining('170 kcal'), findsWidgets);
  });

  testWidgets('switching between masses keeps the amount', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    await tester.tap(find.text('100 g'));
    await pumpFrames(tester, frames: 8);

    // A pot is 170 g, so in 100 g units that is 1.7.
    expect(find.text('1.7'), findsOneWidget);
  });

  testWidgets('a serving it cannot express is not offered', (
    WidgetTester tester,
  ) async {
    // A tablespoon is a volume and the default pot is a mass. Without a
    // density the food does not carry there is no honest way to write one as
    // a multiple of the other — and the stored count *is* a multiple of the
    // default, so offering it would mean storing a number that means
    // something else (§5.5: a figure nobody stated is not invented).
    await openPicker(tester);

    expect(find.text('170 g pot'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(
      find.text('1 tbsp'),
      findsNothing,
      reason: 'a serving that cannot be converted must not be offered',
    );
  });

  testWidgets('and correcting the portion does not rewrite the meal', (
    WidgetTester tester,
  ) async {
    // Non-negotiable #3, and the way the first version of this broke it: a
    // meal logged as 1.7 x 100 g re-opened and Updated without a keystroke
    // went from 170 kcal to 289, because the stored count was in one unit and
    // everything downstream read it in another. The count is stored in the
    // default serving now, so the two agree.
    const Macros eaten = Macros(kcal: 170, proteinG: 17);
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[yoghurt()],
      entries: <MealPlanEntry>[
        MealPlanEntry(
          id: 'e-yog',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'f-yoghurt',
          servings: 1,
        ).log(
          liveMacros: eaten,
          at: DateTime.utc(2026, 9, 7, 8),
          label: 'Greek yoghurt',
          coverage: NutrientCoverage.ofOne(eaten),
        ),
      ],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    // The calories, not the whole snapshot: re-logging deliberately takes a
    // fresh one, so its `loggedAt` moves and always will. What must not move
    // is the food.
    double kcalOf(String? snapshot) =>
        ((jsonDecode(snapshot!) as Map<String, Object?>)['kcal']! as num)
            .toDouble();

    final double before = kcalOf(
      (await db.select(db.mealPlanEntries).get()).single.macroSnapshot,
    );

    await tester.longPress(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Edit portion'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Update'));
    await pumpFrames(tester, frames: 20);

    expect(
      kcalOf((await db.select(db.mealPlanEntries).get()).single.macroSnapshot),
      closeTo(before, 0.001),
      reason: 'pressing Update rewrote a meal nobody edited',
    );
  });

  testWidgets('what is stored is the same meal, whichever unit typed it', (
    WidgetTester tester,
  ) async {
    // The invariant the first version of this broke. `servings` means
    // multiples of the default serving everywhere downstream — correcting a
    // portion, projecting a planned meal, repeating a recent one all rebuild
    // the macros from `defaultServing` — so a count stored in any other unit
    // is reinterpreted later. Logged as 1.7 x 100 g and re-opened, this meal
    // became 289 kcal from 170 without a keystroke.
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[yoghurt()],
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);

    // Enter it in 100 g units. Switching alone changes only what is on
    // screen, so this has to type a number in the new unit — which is the
    // whole path, and what the first version of this test never did.
    await tester.tap(find.text('100 g'));
    await pumpFrames(tester, frames: 8);
    expect(find.text('1.7'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '3.4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, frames: 8);

    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    final List<MealPlanEntryRow> rows = await db
        .select(db.mealPlanEntries)
        .get();
    // 3.4 x 100 g is 340 g, which is two 170 g pots.
    expect(
      rows.single.servings,
      closeTo(2.0, 0.001),
      reason:
          'stored as ${rows.single.servings} of the default serving, and '
          'everything downstream reads that as that many 170 g pots',
    );
  });
}
