import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The day's primary action (spec §5.6, and the November 2026 templates).
///
/// Logging used to be a small `+` at the end of each meal's heading — four of
/// them, the smallest controls on the screen, on the screen the success bar
/// is measured on. This is the way in for somebody who has just eaten rather
/// than somebody who has already scrolled to the meal they mean.
void main() {
  Future<void> openDay(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    await pumpHearthApp(
      tester,
      size: size,
      textScale: textScale,
      foods: <Food>[
        aFood(
          'Oats',
          id: 'f-oats',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 400, proteinG: 20),
            ),
          ],
        ),
      ],
      entries: const <MealPlanEntry>[],
      targets: const MacroTargets(
        kcal: 2000,
        proteinG: 150,
        carbG: 200,
        fatG: 70,
      ),
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('the day offers one way in, and it is the loudest thing after '
      'the figure', (WidgetTester tester) async {
    await openDay(tester);

    expect(find.text('Log food'), findsOneWidget);

    // Sized for a kitchen, not to the 48pt floor: it is pressed with the
    // hand that just put the pan down (spec §5.6, §6.3).
    final Size button = tester.getSize(
      find.ancestor(
        of: find.text('Log food'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.height, greaterThanOrEqualTo(HearthTouch.kitchenTarget));
  });

  testWidgets('it asks which meal, and opens that meal', (
    WidgetTester tester,
  ) async {
    await openDay(tester);
    await tester.tap(find.text('Log food'));
    await pumpFrames(tester, frames: 12);

    // Asked rather than guessed: the clock is wrong often enough, the log
    // sheet cannot be corrected once it is open, and this screen can be
    // showing a day that is not today.
    expect(find.text('Log food to'), findsOneWidget);
    for (final MealSlot slot in MealSlot.values) {
      expect(find.text(slot.label), findsWidgets);
    }

    await tester.tap(find.text('Log food to').last);
    await pumpFrames(tester);
    // The title is not a control; the meals are.
    expect(find.text('Log food to'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: find.text('Dinner')),
    );
    await pumpFrames(tester, frames: 16);

    // The log sheet, opened for the meal that was chosen rather than for
    // whichever one the hour of the day suggested.
    expect(find.textContaining('Dinner'), findsWidgets);
    expect(find.text('Log food to'), findsNothing);
  });

  testWidgets('the shorter path for a meal you have scrolled to still works', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    // The new button is an addition, not a replacement. Somebody already
    // looking at Lunch should not have to go back up and say "Lunch".
    await tester.tap(find.byTooltip('Add to lunch'));
    await pumpFrames(tester, frames: 16);

    expect(find.text('Log food to'), findsNothing);
    expect(find.textContaining('Lunch'), findsWidgets);
  });
}
