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

/// Typing the amount you actually ate (spec §5.6, F06).
///
/// A food served in 170 g pots could only ever be logged as a count of pots,
/// so 125 g of it meant dividing by 170 in a kitchen and typing 0.735 into a
/// stepper that moves in quarters. The raw units join the food's own servings
/// on the same chip row: what changes is the number under your thumb, never
/// the number in the row — `servings` still means multiples of the default
/// serving, and everything downstream still reads it that way.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  /// One serving, measured by mass. 170 g is 281 kcal, so 85 g is half of it.
  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'pot',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 281, proteinG: 17),
      ),
    ],
  );

  Food juice() => aFood(
    'Orange juice',
    id: 'f-juice',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'glass',
        label: '250 ml glass',
        amount: Quantity.of(250, Units.millilitre),
        macros: const Macros(kcal: 110, carbG: 26),
      ),
    ],
  );

  Food bar() => aFood(
    'Protein bar',
    id: 'f-bar',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'one',
        label: '1 bar',
        amount: Quantity.of(1, Units.bar),
        macros: const Macros(kcal: 210, proteinG: 20),
      ),
    ],
  );

  /// Opens the log sheet on breakfast and picks [name].
  Future<HearthDatabase> pick(
    WidgetTester tester,
    List<Food> foods,
    String name,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: foods,
      targets: targets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text(name).last);
    await pumpFrames(tester, frames: 12);
    return db;
  }

  Future<void> type(WidgetTester tester, String amount) async {
    await tester.enterText(find.byType(TextField).last, amount);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, frames: 8);
  }

  double kcalOf(String? snapshot) =>
      ((jsonDecode(snapshot!) as Map<String, Object?>)['kcal']! as num)
          .toDouble();

  testWidgets('85 g of a 170 g serving freezes half its calories', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pick(tester, <Food>[
      yoghurt(),
    ], 'Greek yoghurt');

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '85');
    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(
      row.servings,
      closeTo(0.5, 1e-9),
      reason:
          'the stored count is still multiples of the 170 g default '
          'serving, whatever unit typed it',
    );
    expect(
      kcalOf(row.macroSnapshot),
      closeTo(140.5, 1e-6),
      reason: 'half a 281 kcal serving is what was eaten and what freezes',
    );
  });

  testWidgets('the resolved portion is visible before it is committed', (
    WidgetTester tester,
  ) async {
    await pick(tester, <Food>[yoghurt()], 'Greek yoghurt');

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '125');

    // 125 / 170 is 0.74 of a pot, and that is the number being stored.
    expect(find.textContaining('0.74'), findsOneWidget);
    expect(find.textContaining('170 g pot'), findsWidgets);
  });

  testWidgets('switching g, oz and the serving keeps the same quantity', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pick(tester, <Food>[
      yoghurt(),
    ], 'Greek yoghurt');

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '85');

    // 85 g is 3 oz to the precision an ounce field is typed in.
    await tester.tap(find.widgetWithText(ChoiceChip, 'oz'));
    await pumpFrames(tester, frames: 8);
    expect(find.text('3'), findsOneWidget);

    // And half a pot, which is what it was all along.
    await tester.tap(find.widgetWithText(ChoiceChip, '170 g pot'));
    await pumpFrames(tester, frames: 8);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    expect(
      (await db.select(db.mealPlanEntries).get()).single.servings,
      closeTo(0.5, 1e-9),
      reason: 'three trips round the chip row must not move the portion',
    );
  });

  testWidgets('a food counted in bars is offered no raw units', (
    WidgetTester tester,
  ) async {
    // Its serving already is the unit, and turning a bar into grams needs a
    // weight nobody stated (spec §5.5).
    await pick(tester, <Food>[bar()], 'Protein bar');

    expect(find.widgetWithText(ChoiceChip, 'g'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'oz'), findsNothing);
    expect(find.textContaining('1 bar'), findsWidgets);
  });

  testWidgets('a drink is offered ml and fl oz, never g', (
    WidgetTester tester,
  ) async {
    await pick(tester, <Food>[juice()], 'Orange juice');

    expect(find.widgetWithText(ChoiceChip, 'ml'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'fl oz'), findsOneWidget);
    expect(
      find.widgetWithText(ChoiceChip, 'g'),
      findsNothing,
      reason: 'crossing volume and mass needs a density the food has not got',
    );
  });

  testWidgets('a food with one stored serving still gets the chip row', (
    WidgetTester tester,
  ) async {
    // The row used to appear only when a food had two servings to choose
    // between. A raw unit is always a second way to type it.
    await pick(tester, <Food>[yoghurt()], 'Greek yoghurt');

    expect(find.text('Serving'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '170 g pot'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'g'), findsOneWidget);
  });

  testWidgets('zero, blank and unreadable amounts are refused', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pick(tester, <Food>[
      yoghurt(),
    ], 'Greek yoghurt');

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '85');

    for (final String rubbish in <String>['0', '', 'abc', '0.0']) {
      await type(tester, rubbish);
      expect(
        find.text('85'),
        findsOneWidget,
        reason: '"$rubbish" is not a portion, so the last real one stands',
      );
    }

    // A negative one never reaches the parser: the field's formatter has no
    // minus sign in it, and `_commit` would refuse the number underneath it
    // anyway. Both layers, because a portion below zero is not a smaller
    // portion.
    await type(tester, '-20');
    expect(find.text('-20'), findsNothing);

    await type(tester, '85');
    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    expect(
      (await db.select(db.mealPlanEntries).get()).single.servings,
      closeTo(0.5, 1e-9),
      reason: 'a rejected amount must not reach the day',
    );
  });

  testWidgets('the unit is remembered for the next time that food is logged', (
    WidgetTester tester,
  ) async {
    await pick(tester, <Food>[yoghurt()], 'Greek yoghurt');

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '85');
    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 16);

    // One serving, in the unit this food is always weighed in.
    expect(
      find.text('170'),
      findsOneWidget,
      reason:
          'somebody who weighs everything should not re-pick grams every '
          'time',
    );
  });

  testWidgets('an entry typed in ounces re-opens in ounces', (
    WidgetTester tester,
  ) async {
    const Macros eaten = Macros(kcal: 281, proteinG: 17);
    await pumpHearthApp(
      tester,
      foods: <Food>[yoghurt()],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
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

    Future<void> openTheEntry() async {
      await tester.longPress(find.text('Greek yoghurt').last);
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Edit portion'));
      await pumpFrames(tester, frames: 16);
    }

    // Corrected in ounces, which is how this one was typed.
    await openTheEntry();
    await tester.tap(find.widgetWithText(ChoiceChip, 'oz'));
    await pumpFrames(tester, frames: 8);
    await tester.tap(find.text('Update'));
    await pumpFrames(tester, frames: 20);

    // The same food logged again in grams, so grams is now what this food is
    // remembered as. The entry above must ignore that.
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 16);
    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await pumpFrames(tester, frames: 8);
    await type(tester, '200');
    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 20);

    await openTheEntry();

    // One pot is 6 oz, 170 g, or 1 pot. Which number is on screen says which
    // unit it re-opened in.
    expect(
      find.text('6'),
      findsOneWidget,
      reason:
          'it was corrected in ounces, so that is what it re-opens in — '
          'not the grams this food is otherwise remembered as',
    );
    expect(find.text('170'), findsNothing);
  });
}
