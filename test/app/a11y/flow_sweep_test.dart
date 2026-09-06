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
  // A tap that lands on nothing is a warning on the console and a green test,
  // which is how three of these flows first shipped never reaching the screen
  // they were named after. Here it is a failure.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

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
  /// Brings [finder] onto the screen, scrolling if it has not been built yet.
  ///
  /// Returns the finder narrowed to the one it brought — the *last* match,
  /// not the first. With a sheet open, the row behind the modal matches too
  /// and comes first, so acting on `.first` acts on the page underneath and
  /// the flow never goes anywhere.
  Future<Finder> bring(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        // The unfiltered finder: dragUntilVisible asks it whether it is empty
        // on every step, and `.first` of nothing throws rather than answering.
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

    final Finder one = finder.last;

    // Present is not the same as on screen: an off-screen widget still
    // matches a finder, which is the trap this whole file exists to point at.
    await tester.ensureVisible(one);
    await pumpFrames(tester, frames: 4);
    return one;
  }

  /// Scrolls until [finder] matches at least [atLeast] widgets.
  ///
  /// `dragUntilVisible` stops at the first match, which is no use when the
  /// thing wanted is the *second* one — "Today" is the page's title as well
  /// as the card's heading, and only the card opens the targets sheet. With
  /// one match it looked found, tapping the title did nothing, and the flow
  /// reported success from a screen it had never left.
  Future<void> bringNth(WidgetTester tester, Finder finder, int atLeast) async {
    final Finder scroller = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.down ||
                  widget.axisDirection == AxisDirection.up),
        )
        .last;

    for (int i = 0; i < 40 && finder.evaluate().length < atLeast; i++) {
      await tester.drag(scroller, const Offset(0, -120));
      await pumpFrames(tester, frames: 2);
    }
  }

  Future<void> reach(WidgetTester tester, Finder finder) async {
    await tester.tap(await bring(tester, finder));
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

        await bringNth(tester, find.text('Today'), 2);
        await reach(tester, find.text('Today'));
        expect(
          find.text('Weekly targets'),
          findsOneWidget,
          reason: 'the targets sheet never opened at $at',
        );
        expectSurvived(tester, 'the targets sheet at $at');

        // Read to the end of it. A ListView builds lazily, so the buttons at
        // the bottom are not laid out at all until something scrolls to them
        // — and a row that overflows off the right-hand edge cannot overflow
        // if it was never built. Putting the original Row back passed every
        // case in this file until this step existed.
        await bring(tester, find.text('Save targets'));
        expectSurvived(tester, 'the end of the targets sheet at $at');
      });

      testWidgets('the expanded summary survives $at', (
        WidgetTester tester,
      ) async {
        // The rings and slim bars are behind Details now (U01), and behind a
        // tap is where a sweep stops looking: they were still shipped, still
        // reachable, and swept at no size or theme at all.
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester, frames: 12);

        await reach(tester, find.text('Details'));
        expect(
          find.text('Less'),
          findsOneWidget,
          reason: 'the summary never expanded at $at',
        );
        expectSurvived(tester, 'the expanded summary at $at');

        // And its far end, for the same reason the targets sheet needs it.
        await bring(tester, find.text('Cholesterol'));
        expectSurvived(tester, 'the end of the expanded summary at $at');
      });

      testWidgets('a meal\'s own options survive $at', (
        WidgetTester tester,
      ) async {
        await open(tester, size: device.size, scale: scale);
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester, frames: 12);

        // Behind a long press, not a tap. Tapping the row toggles it logged
        // and leaves the day screen exactly where it was, so a flow that only
        // tapped never opened the sheet it was named after.
        final Finder meal = await bring(
          tester,
          find.text('Slow chilli with all the trimmings'),
        );
        await tester.longPress(meal);
        await pumpFrames(tester, frames: 12);

        expect(
          find.text('Edit portion'),
          findsOneWidget,
          reason: 'the options sheet never opened at $at',
        );
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

        // Scoped to the log sheet. The same recipe title is on the day screen
        // behind the modal and is not reliably ordered after it, so an
        // unscoped finder tapped the row underneath — which opened its swipe
        // action while the flow reported having chosen something.
        await reach(
          tester,
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text('Slow chilli with all the trimmings'),
          ),
        );

        // That the picker is gone, rather than that some particular part of
        // the confirm view is present: the confirm view is a lazy list, so at
        // the largest text its lower half is not built and asserting on
        // something down there fails for a reason that has nothing to do
        // with whether the flow arrived.
        expect(
          find.text('Add to this meal'),
          findsNothing,
          reason: 'the confirm view never opened at $at',
        );
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
