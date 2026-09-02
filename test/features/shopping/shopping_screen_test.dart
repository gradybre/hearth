import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The shopping list on screen (spec §5.7).
void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Chilli',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'ground beef',
            amount: 1,
            unit: Units.pound,
            sectionId: 's1',
          ),
          anIngredient('cumin', amount: 2, unit: Units.tsp, sectionId: 's1'),
        ],
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

  Future<void> openShopping(
    WidgetTester tester, {
    List<MealPlanEntry> entries = const <MealPlanEntry>[],
  }) async {
    await pumpHearthApp(tester, recipes: <Recipe>[chilli()], entries: entries);
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
  }

  Future<void> build(WidgetTester tester) async {
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('an empty list says what it would be built from', (
    WidgetTester tester,
  ) async {
    await openShopping(tester);

    expect(find.text('Nothing on the list yet.'), findsOneWidget);
    expect(find.text('Shopping for'), findsOneWidget);
  });

  testWidgets('building pulls the plan in, without the spices', (
    WidgetTester tester,
  ) async {
    // Seasonings are bought on their own rhythm, so cumin stays off by
    // default even though the recipe calls for it.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    expect(find.text('ground beef'), findsOneWidget);
    expect(find.text('cumin'), findsNothing);
  });

  testWidgets('and the spices come when asked for', (
    WidgetTester tester,
  ) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await tester.tap(find.byType(Switch));
    await pumpFrames(tester);
    await build(tester);

    expect(find.text('cumin'), findsOneWidget);
  });

  testWidgets('tapping a line ticks it off, and says so in words', (
    WidgetTester tester,
  ) async {
    // Never colour alone (§6.3): a done line carries the tick mark itself.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    await tester.tap(find.text('ground beef'));
    await pumpFrames(tester, frames: 20);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('an amount can be changed without touching the recipe', (
    WidgetTester tester,
  ) async {
    // Brendan's case: 1 lb of beef, but he wants 2 because that is how it is
    // sold. The recipe still calls for 1.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.text('1 lb'));
    await pumpFrames(tester, frames: 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'How much to get'),
      '2',
    );
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('2 lb'), findsOneWidget);
    expect(find.textContaining('recipes call for 1 lb'), findsOneWidget);
    // Marked as changed by hand, with an icon rather than colour alone.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('saying what you already have changes what to buy', (
    WidgetTester tester,
  ) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.text('1 lb'));
    await pumpFrames(tester, frames: 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'How much to get'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Leave empty if none'),
      '1',
    );
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('1 lb'), findsOneWidget);
    expect(find.textContaining('have 1 lb'), findsOneWidget);
  });

  testWidgets('an item added by hand survives a rebuild', (
    WidgetTester tester,
  ) async {
    // The plan never put coffee here, so the plan gets no vote on removing it.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.byTooltip('Add an item by hand'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, 'Coffee');
    await tester.tap(find.text('Add'));
    await pumpFrames(tester, frames: 20);
    expect(find.text('Coffee'), findsOneWidget);

    await build(tester);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('a tick survives a rebuild too', (WidgetTester tester) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);
    await tester.tap(find.text('ground beef'));
    await pumpFrames(tester, frames: 20);

    await build(tester);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
