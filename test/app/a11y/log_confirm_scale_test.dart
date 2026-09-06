import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
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

      expect(find.text('Log it'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'scrolling to the button overflowed at ${scale}x text',
      );
    });
  }
}
