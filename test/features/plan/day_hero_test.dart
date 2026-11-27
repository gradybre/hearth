import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/ink_card.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The day's calorie headline (spec §5.6, §6.3, and the November 2026
/// templates).
///
/// The screen is opened to find out one thing, and these are the rules about
/// how it says it: in words before colour, on a ground of its own, and out of
/// the way entirely when the words have grown too big to lead with.
/// Inside the summary card, not merely somewhere on the day.
///
/// Several of these figures are also a slot subtotal or an entry's own
/// amount further down the screen, and an unscoped finder would happily
/// match one of those while the headline said something else entirely.
Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(InkCard), matching: finder);

void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  Future<void> openDay(
    WidgetTester tester, {
    Macros eaten = const Macros(kcal: 400, proteinG: 20),
    MacroTargets? dayTargets = targets,
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
            aServing(amount: 100, unit: Units.gram, macros: eaten),
          ],
        ),
      ],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'e-oats',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'f-oats',
          servings: 1,
        ).log(
          liveMacros: eaten,
          at: DateTime.utc(2026, 9, 7, 8),
          label: 'Oats',
          coverage: NutrientCoverage.ofOne(eaten),
        ),
      ],
      targets: dayTargets,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('the day leads with what is left, and shows its working', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    // The headline carries the unit. At 34pt "1600 left" is a quantity of
    // nothing in particular.
    expect(find.text('1600 kcal left'), findsOneWidget);
    // And the pair it was worked out from is still on the card, because a
    // figure you cannot check is a figure you have to trust.
    expect(find.text('400 of 2000 kcal'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('it is drawn on ink, not on the paper around it', (
    WidgetTester tester,
  ) async {
    await openDay(tester);

    // The inversion is the templates' loudest move and the easiest thing to
    // lose in a later refactor, because nothing else fails when a card goes
    // back to being a card.
    expect(find.byType(InkCard), findsOneWidget);
  });

  testWidgets('over target says so in a word, not only in a colour', (
    WidgetTester tester,
  ) async {
    await openDay(tester, eaten: const Macros(kcal: 2400, proteinG: 20));

    expect(find.text('400 kcal over'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
    // §6.3: the arrow repeats the word. Simulated for deuteranopia the two
    // tones collapse, so the colour is the third thing to say it.
    expect(_inCard(find.byIcon(Icons.arrow_upward)), findsOneWidget);
  });

  testWidgets('landing on the target says on target, not zero left', (
    WidgetTester tester,
  ) async {
    await openDay(tester, eaten: const Macros(kcal: 2000, proteinG: 20));

    expect(find.text('On target'), findsOneWidget);
    expect(find.textContaining('0 kcal left'), findsNothing);
  });

  testWidgets('with no targets there is nothing to fill, and no bar', (
    WidgetTester tester,
  ) async {
    await openDay(tester, dayTargets: null);

    // The total itself, since there is no remainder to report. A bar with
    // nothing to fill against would be a drawing of a number we do not have.
    //
    // Scoped to the card: "400 kcal" is also the breakfast slot's subtotal
    // and the logged entry's own figure, and an unscoped finder here would
    // pass on either of them while the headline said something else.
    expect(_inCard(find.text('400 kcal')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('at three times the text the headline gives way to the figures', (
    WidgetTester tester,
  ) async {
    // The rule this guards is §6.3's, not a preference: a 34pt headline is
    // 102pt here, and with a bar under it the day's actual numbers left the
    // first screen entirely. The card falls back to the one-line readout
    // §5.6 approved rather than shrinking the headline, because shrinking it
    // still cost the fold.
    await openDay(tester, size: const Size(320, 568), textScale: 3.0);

    expect(find.text('1600 kcal left'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(_inCard(find.text('400 kcal')), findsOneWidget);
    expect(_inCard(find.text('of 2000 kcal')), findsOneWidget);
    expect(_inCard(find.text('1600 left')), findsOneWidget);
  });
}
