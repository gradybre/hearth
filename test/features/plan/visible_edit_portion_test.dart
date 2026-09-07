import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Changing a portion without knowing to press and hold (spec §5.6, U06).
///
/// The only way in was a long press. Nothing on the row said so, so it was
/// something you either knew or did not — and the gesture is unreachable to
/// anyone driving the app by switch or voice.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  const Macros eaten = Macros(kcal: 170, proteinG: 17);

  Future<void> openDay(WidgetTester tester, {double scale = 1.0}) async {
    await pumpHearthApp(
      tester,
      textScale: scale,
      foods: <Food>[
        aFood(
          'Greek yoghurt',
          id: 'f-yoghurt',
          servingOptions: <ServingOption>[
            ServingOption(
              id: 'pot',
              label: '170 g pot',
              amount: Quantity.of(170, Units.gram),
              macros: eaten,
            ),
          ],
        ),
      ],
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
  }

  testWidgets('the meal row offers a way in that can be seen', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    await tester.tap(find.byTooltip('Edit Greek yoghurt'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Edit portion'), findsOneWidget);
    expect(find.text('Remove from this day'), findsOneWidget);
  });

  testWidgets('and a screen reader can find it', (WidgetTester tester) async {
    // The row excludes its own descendants from semantics, so a button put
    // inside it would be invisible to anyone listening — which is the
    // opposite of what a visible affordance is for.
    // Disposed at the end of the body rather than in a tear-down: the
    // end-of-test check for live handles runs before tear-downs do.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await openDay(tester);

    // Asserted on the node itself. A tooltip alone sets `tooltip`, which not
    // every screen reader announces; this is the affordance that exists so
    // the gesture is not the only way in, so it needs a label.
    final SemanticsNode node = tester.getSemantics(
      find.byTooltip('Edit Greek yoghurt'),
    );

    expect(
      node.label,
      'Edit Greek yoghurt',
      reason: 'the way in is not announced to anyone listening',
    );
    expect(node.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('long press still works, as a shortcut', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    await tester.longPress(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Edit portion'), findsOneWidget);
  });

  testWidgets('and a plain tap still belongs to the row', (
    WidgetTester tester,
  ) async {
    // The row's own job is one-tap logging, and the button beside it must not
    // take that over. Asserted as "the sheet did not open" rather than as the
    // row's new state: the harness serves the day's entries from a fixed
    // override, so a toggle does not come back through it.
    await openDay(tester);

    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);

    expect(
      find.text('Edit portion'),
      findsNothing,
      reason: 'tapping the row opened the options instead of logging',
    );
  });

  testWidgets('the button is big enough to hit', (WidgetTester tester) async {
    await openDay(tester);

    final Size size = tester.getSize(find.byTooltip('Edit Greek yoghurt'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
