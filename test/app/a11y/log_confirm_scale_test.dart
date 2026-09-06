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

/// Logging a meal at the largest text size (spec §6.3, R07).
///
/// The sweep opens the log sheet but never picks anything, so it only ever
/// sees the picker — which scrolls. The view you get *after* choosing
/// something is a different widget with no scroll view at all, and it is the
/// one every logged meal goes through.
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

  // The sizes the rest of the accessibility sweep uses. A 320-wide phone at
  // 3x overflows before this sheet is even opened — a separate, older fault
  // on a size nothing in the project tests, and not this one to fix here.
  for (final ({double scale, Size size, String where}) at
      in <({double scale, Size size, String where})>[
        (scale: 1.0, size: const Size(390, 844), where: 'a phone'),
        (scale: 2.0, size: const Size(390, 844), where: 'a phone'),
        (scale: 3.0, size: const Size(390, 844), where: 'a phone'),
      ]) {
    final double scale = at.scale;
    testWidgets('choosing something to log survives ${scale}x on ${at.where}', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        size: at.size,
        recipes: <Recipe>[chilli()],
        foods: <Food>[yoghurt()],
        targets: const MacroTargets(
          kcal: 2200,
          proteinG: 170,
          carbG: 200,
          fatG: 70,
        ),
        textScale: scale,
      );

      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester, frames: 12);

      // Open the sheet for a meal, then actually choose something — which is
      // the step the sweep never takes. Breakfast because it is the slot that
      // is on screen without scrolling at every text size.
      // At the largest sizes the meal rows are below the fold and are not
      // built at all, so they have to be scrolled to before they can be
      // tapped — which is itself the day screen behaving correctly.
      await tester.scrollUntilVisible(find.byTooltip('Add to breakfast'), 200);
      await pumpFrames(tester, frames: 6);
      await tester.tap(find.byTooltip('Add to breakfast').first);
      await pumpFrames(tester, frames: 12);
      expect(tester.takeException(), isNull, reason: 'the picker overflowed');

      await tester.tap(find.text('Slow chilli with all the trimmings').last);
      await pumpFrames(tester, frames: 12);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the confirm view overflowed at ${scale}x text',
      );

      // And the thing you came to press is reachable. At the largest sizes
      // it is below the fold, which is fine and is the point: the view
      // scrolls now, where before it simply ran off the bottom of the screen
      // with no way to reach what was down there.
      await tester.dragUntilVisible(
        find.text('Log it'),
        find.byType(ListView).last,
        const Offset(0, -120),
      );
      await pumpFrames(tester, frames: 4);

      // Asserted as a position on the screen, not as a widget in the tree.
      // An overflowing Column still builds and lays out its children — they
      // are simply painted past the bottom edge — so `findsOneWidget` is true
      // of a button 200 pixels below the screen, and dragUntilVisible stops
      // as soon as the finder matches anything at all. Only the geometry
      // tells the two apart.
      final Rect button = tester.getRect(find.byType(FilledButton).last);
      expect(
        button.bottom,
        lessThanOrEqualTo(at.size.height),
        reason: 'the button you came to press is off the bottom of the screen',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'scrolling to the button overflowed at ${scale}x text',
      );
    });
  }

  testWidgets('Remove is nowhere near the button beside it', (
    WidgetTester tester,
  ) async {
    // A Wrap tidied these into one right-aligned run and put Remove eight
    // points from Update at every text size, while both grew — so the
    // mis-tap risk was worst for the people who set large text. Remove
    // deletes a logged meal and its frozen snapshot at once, and this route
    // has no undo: the restore behind Undo is wired to the swipe, which this
    // never goes through.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[chilli()],
      foods: <Food>[yoghurt()],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'e1',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.recipe,
          refId: 'r-chilli',
          servings: 1,
        ),
      ],
      targets: const MacroTargets(
        kcal: 2200,
        proteinG: 170,
        carbG: 200,
        fatG: 70,
      ),
      // At ordinary text size. The gap this pins was eight points at *every*
      // scale, so 1x demonstrates it — and the route to this view crosses
      // another screen that overflows at 3x on its own account, which is a
      // separate fault and not this test's business.
      textScale: 1.0,
    );

    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    await tester.scrollUntilVisible(
      find.text('Slow chilli with all the trimmings'),
      200,
    );
    // scrollUntilVisible stops as soon as the finder matches *anything*,
    // which an off-screen widget does — the same trap this file exists to
    // point at. ensureVisible is the one that moves it onto the screen.
    await tester.ensureVisible(
      find.text('Slow chilli with all the trimmings').first,
    );
    await pumpFrames(tester, frames: 4);
    await tester.longPress(
      find.text('Slow chilli with all the trimmings').first,
    );
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Edit portion'));
    await pumpFrames(tester, frames: 12);

    await tester.dragUntilVisible(
      find.text('Remove'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await pumpFrames(tester, frames: 4);

    final Rect remove = tester.getRect(find.text('Remove'));
    final Rect primary = tester.getRect(find.byType(FilledButton).last);

    expect(
      primary.left - remove.right,
      greaterThan(48),
      reason:
          'Remove sits ${(primary.left - remove.right).round()} points from '
          'the button beside it, and there is no undo behind it',
    );
  });
}
