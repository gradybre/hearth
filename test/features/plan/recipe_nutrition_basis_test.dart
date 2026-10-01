import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';
import 'package:hearth/features/plan/log_sheet.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

Food _rice() =>
    aFoodPer100g('Rice', id: 'rice', kcal: 200, protein: 10, carbs: 30, fat: 5);
Recipe _recipe({bool missing = false}) => aRecipe(
  id: 'recipe',
  title: 'Rice supper',
  servings: 4,
  ingredients: <RecipeIngredient>[
    anIngredient('Rice', amount: 400, unit: Units.gram, foodId: 'rice'),
    if (missing) anIngredient('Sauce', amount: 100, unit: Units.gram),
  ],
);

Future<void> _open(
  WidgetTester tester, {
  bool frozen = false,
  bool missingSnapshot = false,
  bool missing = false,
  Size size = const Size(500, 1600),
  double scale = 1,
}) async {
  final Food food = _rice();
  final Recipe recipe = _recipe(missing: missing);
  MealPlanEntry entry = const MealPlanEntry(
    id: 'entry',
    dayId: 'day',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'recipe',
    servings: 1,
  );
  if (frozen) {
    entry = entry.log(
      liveMacros: const Macros(kcal: 123, proteinG: 7),
      at: DateTime.utc(2026, 9, 30),
      label: 'Rice supper as eaten',
      coverage: const NutrientCoverage.notRecorded(),
    );
  }
  if (missingSnapshot) {
    entry = MealPlanEntry(
      id: entry.id,
      dayId: entry.dayId,
      slot: entry.slot,
      refType: entry.refType,
      refId: entry.refId,
      servings: entry.servings,
      isLogged: true,
      loggedAt: DateTime.utc(2026, 9, 30),
    );
  }
  await pumpHearthApp(
    tester,
    recipes: <Recipe>[recipe],
    foods: <Food>[food],
    size: size,
    textScale: scale,
  );
  unawaited(
    showLogSheet(
      tester.element(find.byType(Scaffold).first),
      date: DateTime(2026, 9, 30),
      slot: MealSlot.dinner,
      existing: EntryResolver.resolve(
        entry,
        recipes: <String, Recipe>{recipe.id: recipe},
        foods: <String, Food>{food.id: food},
      ),
    ),
  );
  await pumpFrames(tester);
}

void main() {
  testWidgets(
    'missing snapshot never labels current recipe as saved nutrition',
    (WidgetTester tester) async {
      await _open(tester, missingSnapshot: true);
      expect(
        find.text('Saved nutrition is unavailable for this meal.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your portion · saved nutrition'),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('200 kcal'),
        ),
        findsNothing,
      );
      expect(find.textContaining('Whole dish'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Update logged portion'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'recipe portion review distinguishes serving, whole dish and typed portion',
    (WidgetTester tester) async {
      await _open(tester);
      expect(find.textContaining('Per serving · 200 kcal'), findsOneWidget);
      expect(
        find.textContaining('Whole dish (4 servings) · 800 kcal'),
        findsOneWidget,
      );
      expect(find.textContaining('Your portion · 200 kcal'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '0.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);
      expect(find.textContaining('Your portion · 100 kcal'), findsOneWidget);
      expect(find.textContaining('Per serving · 200 kcal'), findsOneWidget);
      expect(
        find.textContaining('Whole dish (4 servings) · 800 kcal'),
        findsOneWidget,
      );
    },
  );

  testWidgets('partial recipe totals remain explicitly known amounts', (
    WidgetTester tester,
  ) async {
    await _open(tester, missing: true);
    expect(
      find.text('Known nutrition · some ingredients are not counted'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Your portion · 200 kcal · P 10 g · C 30 g · F 5 g (known)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('historical recipe correction never shows today’s whole dish', (
    WidgetTester tester,
  ) async {
    await _open(tester, frozen: true);
    expect(
      find.textContaining('Your portion · saved nutrition · 123 kcal'),
      findsOneWidget,
    );
    expect(find.textContaining('Whole dish'), findsNothing);
    expect(find.textContaining('Per serving'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(
      find.textContaining('Your portion · saved nutrition · 246 kcal'),
      findsOneWidget,
    );
    expect(find.textContaining('800 kcal'), findsNothing);
  });

  testWidgets('basis wording and portion actions stay reachable at 3×', (
    WidgetTester tester,
  ) async {
    await _open(tester, missing: true, size: const Size(320, 568), scale: 3);
    final SweepTools tools = SweepTools(tester);
    await tools.bring(find.textContaining('Whole dish (4 servings)'));
    await tools.bring(find.textContaining('Your portion · 200 kcal'));
    await tools.bring(find.text('Save planned portion'));
    expect(find.text('Save planned portion').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
