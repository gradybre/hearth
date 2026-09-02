import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Saving a good week and having it again (spec §5.6).
void main() {
  Recipe chilli() => aRecipe(id: 'r-chilli', title: 'Chilli', servings: 4);

  MealPlanEntry tonight() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 4,
  );

  Future<void> openWeek(
    WidgetTester tester, {
    List<MealPlanEntry> entries = const <MealPlanEntry>[],
  }) async {
    await pumpHearthApp(tester, recipes: <Recipe>[chilli()], entries: entries);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Week'));
    await pumpFrames(tester);
  }

  Future<void> save(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Save this week to use again'));
    await pumpFrames(tester, frames: 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'Call it something'),
      name,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('a planned week can be saved and says how much it kept', (
    WidgetTester tester,
  ) async {
    await openWeek(tester, entries: <MealPlanEntry>[tonight()]);

    await save(tester, 'A good week');

    expect(find.textContaining('Saved "A good week"'), findsOneWidget);
    expect(find.textContaining('1 meal'), findsOneWidget);
  });

  testWidgets('an empty week says so rather than saving nothing', (
    WidgetTester tester,
  ) async {
    // Saving a template of nothing is something you would only ever do by
    // accident.
    await openWeek(tester);

    await save(tester, 'Nothing at all');

    expect(find.textContaining('Nothing is planned'), findsOneWidget);
  });

  testWidgets('a saved week can be put onto another one', (
    WidgetTester tester,
  ) async {
    await openWeek(tester, entries: <MealPlanEntry>[tonight()]);
    await save(tester, 'A good week');

    await tester.tap(find.byTooltip('Next week'));
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Use a saved week'));
    await pumpFrames(tester, frames: 10);
    await tester.tap(find.text('A good week'));
    await pumpFrames(tester, frames: 20);

    // The count, not "done": applying is additive, so the number is how you
    // tell it landed on a week that already had things on it.
    expect(find.textContaining('Added 1 meal'), findsOneWidget);
    // And the one from saving is gone rather than queued in front of it.
    expect(find.textContaining('Saved "A good week"'), findsNothing);
  });

  testWidgets('with nothing saved, it says how to save one', (
    WidgetTester tester,
  ) async {
    await openWeek(tester, entries: <MealPlanEntry>[tonight()]);

    await tester.tap(find.byTooltip('Use a saved week'));
    await pumpFrames(tester, frames: 10);

    expect(find.textContaining('No saved weeks yet'), findsOneWidget);
  });
}
