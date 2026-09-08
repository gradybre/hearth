import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
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

    // The rings are the expanded view now; the day opens compact (U01). This
    // file is about the rings, so it asks for them.
    await tester.tap(find.text('Details'));
    await pumpFrames(tester, frames: 8);
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

  Future<void> openLogged(
    WidgetTester tester, {
    required double kcal,
    required double proteinG,
  }) => openToday(
    tester,
    foods: <Food>[chicken(kcal: kcal, proteinG: proteinG)],
    entries: <MealPlanEntry>[
      const MealPlanEntry(
        id: 'entry-1',
        dayId: 'day-1',
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'food-chicken',
        servings: 1,
      ).log(
        liveMacros: Macros(kcal: kcal, proteinG: proteinG),
        at: DateTime.now(),
        label: 'Roast chicken',
        coverage: const NutrientCoverage.notRecorded(),
      ),
    ],
  );

  testWidgets('nine tenths of the way is already good news', (
    WidgetTester tester,
  ) async {
    // 2160 of 2400. Landing exactly on a target is luck, and a day that only
    // turns encouraging at the last mouthful encourages nobody.
    await openLogged(tester, kcal: 2200, proteinG: 0);

    expect(find.text('on target'), findsOneWidget);
  });

  testWidgets('passing a protein target is an achievement, not a warning', (
    WidgetTester tester,
  ) async {
    // The case the whole tone idea exists for. 200 g of a 180 g target is
    // over, and it is exactly what you were trying to do — so it reads the
    // same as hitting it, while calories at 2200 of 2400 read good too.
    await openLogged(tester, kcal: 2200, proteinG: 200);

    expect(find.text('on target'), findsNWidgets(2));
    expect(find.textContaining('over'), findsNothing);
  });

  testWidgets('over target, it says so in words as well as colour', (
    WidgetTester tester,
  ) async {
    // §6.3: never colour alone. Going over is the one state worth
    // interrupting for, so it is the one that gets an icon and a word.
    await openLogged(tester, kcal: 3000, proteinG: 300);

    // Calories are past a ceiling and say so; protein is past a floor and
    // reads as done. Colour could not tell those two apart on its own —
    // simulated for deuteranopia the green and the red are about 1.2:1 apart.
    expect(find.text('600 over'), findsOneWidget);
    expect(find.text('on target'), findsOneWidget);
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
    // The two thresholds A11y.macroColumns reflows at, the default, and the
    // top of the range. 3.0 used to be unreachable from here: the Recipes
    // empty state is rendered on the way to the Plan tab and clipped at that
    // size, so this loop stopped at 2.0 and said so. That defect is fixed —
    // see the width cap in `CentredMessage` — and this rung is worth having
    // rather than a comment explaining its absence.
    for (final double scale in <double>[1.0, 1.4, 2.0, 3.0]) {
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
