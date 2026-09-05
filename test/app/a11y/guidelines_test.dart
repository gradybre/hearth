import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The §6.3 baseline, checked by Flutter's own auditors rather than by eye.
///
/// These are the guidelines the framework ships: every tappable thing is big
/// enough to hit and carries a label a screen reader can read, and text meets
/// WCAG AA contrast against what is behind it. Written as a sweep because the
/// baseline is not optional and a per-screen habit is how it rots.
void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Slow-braised beef chilli',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'ground beef',
            amount: 2,
            unit: Units.pound,
            sectionId: 's1',
          ),
        ],
        steps: <RecipeStep>[
          aStep('Brown the beef, then braise it.', sectionId: 's1'),
        ],
      ),
    ],
  );

  Food yoghurt() => Food(
    id: 'f-yoghurt',
    householdId: 'household-1',
    name: 'Greek yoghurt',
    source: FoodSource.manual,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o1',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 160, proteinG: 15, carbG: 8, fatG: 8),
      ),
    ],
  );

  MealPlanEntry tonight() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 4,
  );

  const List<String> tabs = <String>['Recipes', 'Plan', 'Shopping', 'Foods'];

  const Size phone = Size(390, 844);
  const Size desktop = Size(900, 500);

  Future<void> open(
    WidgetTester tester,
    Brightness brightness, {
    Size size = phone,
    double textScale = 1.0,
    LaunchTarget? launchTarget,
  }) => pumpHearthApp(
    tester,
    size: size,
    recipes: <Recipe>[chilli()],
    foods: <Food>[yoghurt()],
    entries: <MealPlanEntry>[tonight()],
    targets: const MacroTargets(
      kcal: 2200,
      proteinG: 170,
      carbG: 200,
      fatG: 70,
    ),
    textScale: textScale,
    brightness: brightness,
    launchTarget: launchTarget,
  );

  for (final Brightness brightness in Brightness.values) {
    final String theme = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('every tap target is reachable and labelled in $theme', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, brightness);
      await pumpFrames(tester);

      for (final String tab in tabs) {
        await tester.tap(find.text(tab).last);
        await pumpFrames(tester, frames: 10);

        // Big enough to hit — a 44pt target is the difference between logging
        // a meal one-handed in a kitchen and not.
        //
        // iOS only, deliberately. Android's guideline asks for 48, and Hearth
        // ships iOS, macOS and Windows (CLAUDE.md) — growing every button in
        // the app by four points to satisfy a platform it does not run on
        // would be the guideline choosing the design language.
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        // And named, so VoiceOver reads something other than "button".
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });

    testWidgets('text meets WCAG AA contrast in $theme', (
      WidgetTester tester,
    ) async {
      // Dark mode is where this usually breaks: a palette tuned on paper-cream
      // does not automatically survive being inverted.
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, brightness);
      await pumpFrames(tester);

      for (final String tab in tabs) {
        await tester.tap(find.text(tab).last);
        await pumpFrames(tester, frames: 10);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });
  }

  group('the screens you spend the most time on', () {
    Future<void> check(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    // The front door of the app, which this sweep never reached: it passed no
    // launch target, so every run above started inside Nutrition. Both themes,
    // because the cards are the one place on it carrying the accent.
    for (final Brightness brightness in Brightness.values) {
      testWidgets('the home screen, in '
          '${brightness == Brightness.light ? 'light' : 'dark'}', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await open(tester, brightness, launchTarget: LaunchTarget.home);
        await pumpFrames(tester);

        expect(find.text('Hearth'), findsOneWidget);
        await check(tester);
        handle.dispose();
      });
    }

    testWidgets('the home screen on a desk, at the largest text', (
      WidgetTester tester,
    ) async {
      // A desktop window at 3x is where the shell's own chrome grows: nothing
      // in this sweep had ever been pumped anywhere but a phone at 1x.
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(
        tester,
        Brightness.light,
        size: desktop,
        textScale: 3.0,
        launchTarget: LaunchTarget.home,
      );
      await pumpFrames(tester);

      await check(tester);
      handle.dispose();
    });

    testWidgets('and the sidebar beside a section, at the largest text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light, size: desktop, textScale: 3.0);
      await pumpFrames(tester);

      await check(tester);
      handle.dispose();
    });

    testWidgets('a recipe', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light);
      await pumpFrames(tester);

      await tester.tap(find.text('Slow-braised beef chilli').first);
      await pumpFrames(tester, frames: 10);

      await check(tester);
      handle.dispose();
    });

    // Both themes for this one: it is the screen most likely to be read in a
    // dim kitchen, and a palette tuned on paper-cream does not automatically
    // survive being inverted.
    for (final Brightness brightness in Brightness.values) {
      testWidgets('cook-along, which is used with wet hands, in '
          '${brightness == Brightness.light ? 'light' : 'dark'}', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await open(tester, brightness);
        await pumpFrames(tester);
        await tester.tap(find.text('Slow-braised beef chilli').first);
        await pumpFrames(tester, frames: 10);

        await tester.tap(find.widgetWithText(FloatingActionButton, 'Cook'));
        await pumpFrames(tester, frames: 15);

        await check(tester);
        handle.dispose();
      });
    }

    testWidgets('the day you log into', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester, frames: 10);

      await check(tester);
      handle.dispose();
    });

    testWidgets('and the week', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Week'));
      await pumpFrames(tester, frames: 10);

      await check(tester);
      handle.dispose();
    });

    testWidgets('a built shopping list', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light);
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Build from the plan'));
      await pumpFrames(tester, frames: 20);

      await check(tester);
      handle.dispose();
    });

    testWidgets('the household screen', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light);
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.people_outline));
      await pumpFrames(tester, frames: 10);

      await check(tester);
      handle.dispose();
    });
  });
}
