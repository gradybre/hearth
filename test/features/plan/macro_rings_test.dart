import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The four macros as rings (spec §5.6).
///
/// A ring draws a proportion, so the number inside it has to be the one the
/// arc is a picture of — what has been eaten. What is left moved underneath,
/// and only appears when it is worth saying.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2400,
    proteinG: 180,
    carbG: 220,
    fatG: 70,
  );

  Food chicken({double kcal = 300, double proteinG = 60}) => aFood(
    'Roast chicken',
    id: 'food-chicken',
    servingOptions: <ServingOption>[
      aServing(
        amount: 200,
        unit: Units.gram,
        macros: Macros(kcal: kcal, proteinG: proteinG),
      ),
    ],
  );

  Future<void> openToday(
    WidgetTester tester, {
    List<MealPlanEntry> entries = const <MealPlanEntry>[],
    List<Food> foods = const <Food>[],
  }) async {
    await pumpHearthApp(
      tester,
      targets: targets,
      entries: entries,
      foods: foods,
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
  }

  testWidgets('each ring says what its target is', (WidgetTester tester) async {
    await openToday(tester);

    // The unit is not repeated inside the ring — the label above it already
    // says which macro this is, and the spoken label keeps the unit.
    expect(find.text('of 2400'), findsOneWidget);
    expect(find.text('of 180'), findsOneWidget);
    expect(find.text('of 220'), findsOneWidget);
    expect(find.text('of 70'), findsOneWidget);
  });

  testWidgets('the number in the ring is what has been eaten', (
    WidgetTester tester,
  ) async {
    // Nothing logged, so every ring reads zero — not the whole target as a
    // remainder. The arc and the numeral have to agree.
    await openToday(tester);

    expect(find.text('0'), findsNWidgets(4));
    expect(find.text('2400'), findsNothing);
  });

  testWidgets('under target, a ring says nothing extra', (
    WidgetTester tester,
  ) async {
    // The part-filled arc already says "under". Repeating it in words beneath
    // all four rings, every day, is noise rather than news.
    await openToday(tester);

    expect(find.textContaining('left'), findsNothing);
    expect(find.textContaining('over'), findsNothing);
  });

  testWidgets('over target, it says so in words as well as colour', (
    WidgetTester tester,
  ) async {
    // §6.3: never colour alone. Going over is the one state worth
    // interrupting for, so it is the one that gets an icon and a word.
    await openToday(
      tester,
      foods: <Food>[chicken(kcal: 3000, proteinG: 300)],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'entry-1',
          dayId: 'day-1',
          slot: MealSlot.dinner,
          refType: PlanRefType.food,
          refId: 'food-chicken',
          servings: 1,
        ).log(
          liveMacros: const Macros(kcal: 3000, proteinG: 300),
          at: DateTime.now(),
          label: 'Roast chicken',
        ),
      ],
    );

    expect(find.textContaining('over'), findsWidgets);
  });

  testWidgets('a screen reader hears the amount and the target', (
    WidgetTester tester,
  ) async {
    // The label is assembled by hand, so it does not follow the layout on its
    // own — and half a readout is worse than none.
    await openToday(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'Protein: 0 of 180 g')),
      findsOneWidget,
    );
  });

  group('dynamic type is honoured, not capped (spec §6.3)', () {
    // The rule the whole macro dashboard is built on: the numbers keep
    // growing and the layout gives way around them. A ring is the hardest
    // case, because the numbers live *inside* it — an 88pt ring clipped them
    // at default size, which is how this test came to exist.
    // The two thresholds A11y.macroColumns reflows at, and the default.
    // Larger scales are worth checking too, but the Recipes empty state
    // clips at 3.0 and is rendered before this test can reach the Plan tab —
    // a real defect, and a separate one.
    for (final double scale in <double>[1.0, 1.4, 2.0]) {
      testWidgets('at text scale $scale nothing is clipped', (
        WidgetTester tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        // A RenderFlex overflow throws in a test, so rendering at all is the
        // assertion. The readouts are checked too, so a layout that "fits"
        // by dropping one of them fails here rather than passing quietly.
        await openToday(tester);

        expect(find.text('of 2400'), findsOneWidget);
        expect(find.text('0'), findsNWidgets(4));
      });
    }
  });

  testWidgets('with no targets, the rings give way to the prompt', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);

    expect(find.text('No targets set for this week'), findsOneWidget);
    expect(find.textContaining('of 180'), findsNothing);
  });
}
