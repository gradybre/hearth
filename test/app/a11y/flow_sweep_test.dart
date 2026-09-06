import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The app at large text, a step or two past the tabs (spec §6.3).
///
/// The screen sweep visits four tabs. Every overflow found on a small phone
/// so far has been past one of them — a sheet opened, an item chosen, a row
/// long-pressed — including one that put both actions of a long-pressed meal
/// off the bottom of the screen, so it could be neither edited nor removed.
/// A sweep that stops at the four tabs is a sweep of four screens.
void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Slow chilli with all the trimmings',
    servings: 4,
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o1',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 160, proteinG: 15, carbG: 8, fatG: 8),
      ),
    ],
  );

  MealPlanEntry breakfast() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 1,
  );

  Future<void> open(
    WidgetTester tester, {
    required Size size,
    required double scale,
  }) => pumpHearthApp(
    tester,
    size: size,
    recipes: <Recipe>[chilli()],
    foods: <Food>[yoghurt()],
    entries: <MealPlanEntry>[breakfast()],
    targets: const MacroTargets(
      kcal: 2200,
      proteinG: 170,
      carbG: 200,
      fatG: 70,
    ),
    textScale: scale,
  );

  /// Brings [finder] onto the screen and taps it.
  ///
  /// `scrollUntilVisible` stops as soon as the finder matches anything, which
  /// an off-screen widget does — so it is followed by `ensureVisible`, which
  /// is the one that moves it into view.
  Future<void> reach(WidgetTester tester, Finder finder) async {
    final Finder one = finder.first;

    // Dragged rather than scrolled to, and against the last scroll view on
    // screen — which is the sheet's when one is open, and the page's when not.
    // `scrollUntilVisible` picks its own scrollable and there are several once
    // anything is layered.
    // The unfiltered finder: asking `.first` whether it is empty throws,
    // because taking the first of nothing is the error, not the answer.
    if (finder.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        // The unfiltered finder again: dragUntilVisible asks it whether it is
        // empty on every step, and `.first` of nothing throws rather than
        // answering.
        finder,
        // The last *vertical* scroll view. Every text field contains a
        // horizontal one of its own for its editable, so "the last
        // scrollable" on a sheet full of fields is a text box, and dragging
        // it goes nowhere.
        find
            .byWidgetPredicate(
              (Widget widget) =>
                  widget is Scrollable &&
                  (widget.axisDirection == AxisDirection.down ||
                      widget.axisDirection == AxisDirection.up),
            )
            .last,
        const Offset(0, -120),
      );
      await pumpFrames(tester, frames: 4);
    }

    // Present is not the same as on screen: an off-screen widget still
    // matches a finder, which is the trap this whole file exists to point at.
    await tester.ensureVisible(one);
    await pumpFrames(tester, frames: 4);
    await tester.tap(one);
    await pumpFrames(tester, frames: 12);
  }

  void expectSurvived(WidgetTester tester, String step) =>
      expect(tester.takeException(), isNull, reason: '$step overflowed');

  // The sizes the screen sweep uses, at the two scales that matter: ordinary,
  // and the largest iOS offers.
  const List<({Size size, String where})> devices =
      <({Size size, String where})>[
        (size: Size(390, 844), where: 'a phone'),
        (size: Size(320, 568), where: 'a small phone'),
      ];

  for (final ({Size size, String where}) device in devices) {
    for (final double scale in <double>[1.0, 3.0]) {
      final String at = '${scale}x on ${device.where}';

      // One flow per test, each from a fresh start. Walking several in one
      // test means dismissing each sheet to reach the next, and a sheet that
      // covers the whole screen at the largest text has no scrim to tap —
      // which is friction in the test rather than anything about the app.
      testWidgets('the day and its targets survive $at', (
        WidgetTester tester,
      ) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester, frames: 12);
        expectSurvived(tester, 'the day at $at');

        await reach(tester, find.text('Today').last);
        expectSurvived(tester, 'the targets sheet at $at');
      });

      testWidgets('a meal\'s own options survive $at', (
        WidgetTester tester,
      ) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester, frames: 12);

        // Where Remove lives, and where both actions were off the bottom of
        // a small phone until this sweep went looking.
        await reach(tester, find.text('Slow chilli with all the trimmings'));
        expectSurvived(tester, 'the entry options at $at');
      });

      testWidgets('choosing something to log survives $at', (
        WidgetTester tester,
      ) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester, frames: 12);

        // Breakfast, which is the slot on screen without scrolling at every size.
        await reach(tester, find.byTooltip('Add to breakfast'));
        expectSurvived(tester, 'the picker at $at');

        await reach(tester, find.text('Slow chilli with all the trimmings'));
        expectSurvived(tester, 'the confirm view at $at');
      });

      testWidgets('a recipe opens and reads $at', (WidgetTester tester) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Recipes').last);
        await pumpFrames(tester, frames: 12);
        expectSurvived(tester, 'the library at $at');

        await reach(tester, find.text('Slow chilli with all the trimmings'));
        expectSurvived(tester, 'the recipe at $at');
      });

      testWidgets('the shopping list builds $at', (WidgetTester tester) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Shopping').last);
        await pumpFrames(tester, frames: 12);
        expectSurvived(tester, 'the shopping tab at $at');
      });
    }
  }
}
