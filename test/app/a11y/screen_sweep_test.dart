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

/// Every screen, at every text size, in both themes (spec §6.3).
///
/// The existing scaling test drives a synthetic specimen. This drives the real
/// thing, because the bugs are in the screens: an empty state whose artwork
/// does not shrink, a header whose buttons run out of row, a card built for one
/// line of a title.
///
/// Dynamic type is *honoured*, not capped — so the correct behaviour at 3x is
/// that the layout gives way, never that the text stops growing. A failure here
/// is an overflow, which Flutter reports as an exception rather than as a
/// visibly broken screen.
void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    // Long on purpose: a short title fits anywhere and proves nothing.
    title: 'Slow-braised beef chilli with charred poblano and lime crema',
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
          anIngredient('cumin', amount: 2, unit: Units.tsp, sectionId: 's1'),
        ],
        steps: <RecipeStep>[
          aStep(
            'Brown the beef over a high heat until it has taken real colour, '
            'about eight minutes, then set it aside to rest.',
            sectionId: 's1',
          ),
        ],
      ),
    ],
  );

  Food yoghurt() => Food(
    id: 'f-yoghurt',
    householdId: 'household-1',
    name: 'Full-fat Greek yoghurt, strained',
    brand: 'A brand with a fairly long name',
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

  /// The four tabs, by the label the shell shows.
  const List<String> tabs = <String>['Recipes', 'Plan', 'Shopping', 'Foods'];

  /// Default, the reflow threshold, the stack threshold, and the largest iOS
  /// accessibility size.
  const List<double> scales = <double>[1.0, 1.4, 2.0, 3.0];

  /// A phone, and a desk. The shell swaps layouts on width, so a sweep that
  /// only ever pumps a phone leaves the sidebar — a fixed-width rail full of
  /// text — untested at every size that matters.
  const Size phone = Size(390, 844);
  const Size desktop = Size(900, 500);

  Future<void> open(
    WidgetTester tester, {
    required double scale,
    required Brightness brightness,
    Size size = phone,
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
    textScale: scale,
    brightness: brightness,
    launchTarget: launchTarget,
  );

  for (final Brightness brightness in Brightness.values) {
    final String theme = brightness == Brightness.light ? 'light' : 'dark';

    for (final double scale in scales) {
      testWidgets('every tab survives ${scale}x text in $theme', (
        WidgetTester tester,
      ) async {
        await open(tester, scale: scale, brightness: brightness);
        await pumpFrames(tester);

        for (final String tab in tabs) {
          await tester.tap(find.text(tab).last);
          await pumpFrames(tester, frames: 10);
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab overflowed at ${scale}x text in $theme',
          );
        }
      });
    }
  }

  group('the same four tabs on a desk, where the sidebar is', () {
    // The sidebar is a fixed 208pt rail with a way home, a section heading and
    // four labelled rows in it, and none of that was ever pumped at a size
    // larger than 1x. A short window is the honest case: half a laptop screen.
    for (final double scale in scales) {
      testWidgets('the sidebar survives ${scale}x text', (
        WidgetTester tester,
      ) async {
        await open(
          tester,
          scale: scale,
          brightness: Brightness.light,
          size: desktop,
        );
        await pumpFrames(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the sidebar overflowed at ${scale}x text',
        );

        for (final String tab in tabs) {
          await tester.tap(find.text(tab).last);
          await pumpFrames(tester, frames: 10);
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab overflowed at ${scale}x text on a desktop window',
          );
        }
      });
    }

    testWidgets('and so does a window short enough to be a palette', (
      WidgetTester tester,
    ) async {
      // 400 tall at 3x is where the rail ran out of room by 106 points.
      await open(
        tester,
        scale: 3.0,
        brightness: Brightness.light,
        size: const Size(900, 400),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('the home screen, which is above the shell (spec §6.2)', () {
    // Neither sweep passed a launch target, so both always started inside
    // Nutrition and the front door of the app was swept by nobody.
    for (final double scale in scales) {
      for (final Brightness brightness in Brightness.values) {
        final String theme = brightness == Brightness.light ? 'light' : 'dark';
        testWidgets('survives ${scale}x text in $theme', (
          WidgetTester tester,
        ) async {
          await open(
            tester,
            scale: scale,
            brightness: brightness,
            launchTarget: LaunchTarget.home,
          );
          await pumpFrames(tester);

          expect(find.text('Hearth'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('and survives it on a desk, where the column is centred', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        scale: 3.0,
        brightness: Brightness.light,
        size: desktop,
        launchTarget: LaunchTarget.home,
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('the screens behind the tabs', () {
    testWidgets('a recipe reads at 3x text', (WidgetTester tester) async {
      await open(tester, scale: 3.0, brightness: Brightness.light);
      await pumpFrames(tester);

      await tester.tap(find.textContaining('Slow-braised beef chilli').first);
      await pumpFrames(tester, frames: 10);

      expect(tester.takeException(), isNull);
    });

    testWidgets('and so does the week view', (WidgetTester tester) async {
      await open(tester, scale: 3.0, brightness: Brightness.light);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);

      await tester.tap(find.text('Week'));
      await pumpFrames(tester, frames: 10);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the household screen too', (WidgetTester tester) async {
      await open(tester, scale: 3.0, brightness: Brightness.light);
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.people_outline));
      await pumpFrames(tester, frames: 10);

      expect(tester.takeException(), isNull);
    });
  });

  group('an empty app, which is what a first run looks like', () {
    for (final double scale in scales) {
      testWidgets('every empty state survives ${scale}x text', (
        WidgetTester tester,
      ) async {
        await pumpHearthApp(
          tester,
          textScale: scale,
          brightness: Brightness.light,
        );
        await pumpFrames(tester);

        for (final String tab in tabs) {
          await tester.tap(find.text(tab).last);
          await pumpFrames(tester, frames: 10);
          expect(
            tester.takeException(),
            isNull,
            reason: 'the empty $tab state overflowed at ${scale}x text',
          );
        }
      });
    }
  });

  group('the sheets, where a fixed height is easiest to write', () {
    // Bottom sheets are the likeliest place to clip: they are sized to their
    // content, often with a max-height fraction, and the content is text.
    Future<void> at3x(WidgetTester tester) async {
      await open(tester, scale: 3.0, brightness: Brightness.light);
      await pumpFrames(tester);
    }

    testWidgets('the log sheet', (WidgetTester tester) async {
      await at3x(tester);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);

      // At 3x the slot sections are below the fold, and a ListView does not
      // build what it is not showing — so the button has to be scrolled to
      // before it can be tapped.
      await tester.scrollUntilVisible(
        find.byTooltip('Add to dinner'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Add to dinner'));
      await pumpFrames(tester, frames: 15);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the macro targets sheet', (WidgetTester tester) async {
      await at3x(tester);
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Week'));
      await pumpFrames(tester, frames: 10);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the shopping export sheet', (WidgetTester tester) async {
      await at3x(tester);
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Build from the plan'));
      await pumpFrames(tester, frames: 20);

      await tester.scrollUntilVisible(
        find.text('Take it shopping'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Take it shopping'));
      await pumpFrames(tester, frames: 10);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the recipe editor', (WidgetTester tester) async {
      await at3x(tester);
      await pumpFrames(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New recipe'));
      await pumpFrames(tester, frames: 15);

      expect(tester.takeException(), isNull);
    });

    testWidgets('cook-along, which is read at arm\'s length', (
      WidgetTester tester,
    ) async {
      // The one screen where big text is the point, not an edge case.
      await at3x(tester);
      // Tapped near its top-left, not its centre. At 3x this title is 648px
      // tall on an 844px screen, so its centre sits under the navigation bar —
      // tester.tap ignores occlusion and would hit the bar instead. A person
      // taps a part of the title they can see.
      final Finder title = find
          .textContaining('Slow-braised beef chilli')
          .first;
      await tester.tapAt(tester.getTopLeft(title) + const Offset(20, 20));
      await pumpFrames(tester, frames: 10);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cook'));
      await pumpFrames(tester, frames: 15);

      expect(tester.takeException(), isNull);
    });
  });
}
