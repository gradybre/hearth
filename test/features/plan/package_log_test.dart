import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';

import '../../support/app_harness.dart';

/// Logging a raw weight of a food that only knows cups (spec R9–R12).
///
/// The jar says 10 oz on the front and 'about 2 servings' of 1 cup on the
/// back. Thirty ounces of it is six of the nutrition serving the label was
/// reviewed against — and the sheet has to say the count came from an
/// approximate one.
void main() {
  ServingOption cup(String id, {required double kcal, double? fiberG}) =>
      ServingOption(
        id: id,
        label: '1 cup',
        amount: Quantity.of(1, Units.cup),
        macros: Macros(kcal: kcal, proteinG: 1, fiberG: fiberG),
      );

  // Two rows reading '1 cup'; the relationship is anchored to the second.
  // The default row states fibre and the selected one does not, so macros
  // and coverage taken from different rows disagree visibly.
  final Food cheese = Food(
    id: 'food-cheese',
    name: 'Shredded cheddar',
    source: FoodSource.manual,
    servingOptions: <ServingOption>[
      cup('cup-a', kcal: 200, fiberG: 7),
      cup('cup-b', kcal: 100),
    ],
    packSize: Quantity.of(10, Units.ounce),
    packageNutrition: PackageNutrition.manual(
      servingsPerPackage: 2,
      servingOptionId: 'cup-b',
      servingAmount: Quantity.of(1, Units.cup),
      packageAmount: Quantity.of(10, Units.ounce),
      isApproximate: true,
    ),
  );

  Future<HearthDatabase> openSheet(WidgetTester tester) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[cheese],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Add to breakfast'));
    await pumpFrames(tester);
    await tester.tap(find.text('Shredded cheddar'));
    await pumpFrames(tester);
    return db;
  }

  testWidgets('a weight can be typed against a food measured in cups', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    // Offered because this food can really answer it, not because ounces
    // exist.
    expect(find.text('oz'), findsOneWidget);
  });

  testWidgets('switching to it changes neither the portion nor the macros', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);
    expect(find.textContaining('200 kcal'), findsOneWidget);

    await tester.tap(find.text('oz'));
    await pumpFrames(tester);

    // Reading one cup in ounces is not a new amount.
    expect(find.textContaining('200 kcal'), findsOneWidget);
    expect(find.text('Uses approximate package servings'), findsNothing);
  });

  testWidgets('and thirty ounces is six of the selected serving', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openSheet(tester);
    await tester.tap(find.text('oz'));
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField).last, '30');
    await pumpFrames(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);

    // 600, not 1200: the second cup row is the one the package was reviewed
    // against, and it carries 100 kcal.
    expect(find.textContaining('600 kcal'), findsOneWidget);
    expect(find.text('Uses approximate package servings'), findsOneWidget);

    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 12);

    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(row.servings, closeTo(6, 1e-6));
    expect(row.macroSnapshot, contains('600'));
    final snapshot = jsonDecode(row.macroSnapshot!) as Map<String, dynamic>;
    expect(snapshot['fiber_g'], isNull);
    expect(snapshot['coverage']['fiber'], 'unknown');
    expect(
      row.macroSnapshot,
      contains('uses_approximate_package_nutrition'),
      reason: 'the qualifier is frozen with the meal, not looked up later',
    );
  });

  testWidgets('planning it keeps the serving the count is in', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openSheet(tester);
    await tester.tap(find.text('oz'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, '30');
    await pumpFrames(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.textContaining('600 kcal'), findsOneWidget);

    await tester.tap(find.text('Plan only'));
    await pumpFrames(tester, frames: 12);

    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    // Six of the row the package was reviewed against. A planned entry has
    // no snapshot to answer from, so a count stored without its row reads
    // back against the food's first cup and doubles the meal.
    expect(row.servings, closeTo(6, 1e-6));
    expect(row.servingOptionId, 'cup-b');
    expect(row.macroSnapshot, isNull);

    expect(
      EntryResolver.resolve(
        PlanMapper.entryToDomain(row),
        recipes: const <String, Recipe>{},
        foods: <String, Food>{cheese.id: cheese},
      ).contribution.kcal,
      closeTo(600, 1e-9),
      reason: 'reopening the day must not re-cost it against the first row',
    );
  });

  test('a planned portion whose serving has gone cannot be costed', () {
    // Not re-costed against the first row, which would be a silent change to
    // a portion somebody chose.
    final Food without = Food(
      id: cheese.id,
      name: cheese.name,
      source: FoodSource.manual,
      servingOptions: <ServingOption>[cup('cup-a', kcal: 200, fiberG: 7)],
    );
    final ResolvedEntry resolved = EntryResolver.resolve(
      MealPlanEntry(
        id: 'entry-1',
        dayId: 'day-1',
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: cheese.id,
        servings: 6,
        servingOptionId: 'cup-b',
      ),
      recipes: const <String, Recipe>{},
      foods: <String, Food>{without.id: without},
    );

    expect(resolved.isResolvable, isFalse);
    expect(resolved.isUncostable, isTrue);
    expect(resolved.contribution.kcal, 0);
  });

  group('repeating it in one tap', () {
    MealPlanEntry loggedSix(Food food) =>
        MealPlanEntry(
          id: 'entry-1',
          dayId: 'day-1',
          slot: MealSlot.dinner,
          refType: PlanRefType.food,
          refId: food.id,
          servings: 6,
          servingOptionId: 'cup-b',
        ).log(
          liveMacros: const Macros(kcal: 100, proteinG: 1),
          at: DateTime.utc(2026, 9, 18, 19),
          label: food.name,
          coverage: const NutrientCoverage.notRecorded(),
        );

    test('carries the serving the portion counted', () {
      final RecentLog recent = RecentLogs.from(<MealPlanEntry>[
        loggedSix(cheese),
      ]).single;

      expect(recent.servings, 6);
      expect(recent.servingOptionId, 'cup-b');

      final ServingOption serving = EntryResolver.servingForEntry(
        cheese,
        recent.servingOptionId,
      )!;
      // 600, which is the meal that was eaten. The food's first row would
      // repeat it as 1200 and freeze that as history — the whole of F1.
      expect(serving.macros.scaledBy(recent.servings).kcal, closeTo(600, 1e-9));
      expect(
        cheese.defaultServing!.macros.scaledBy(recent.servings).kcal,
        closeTo(1200, 1e-9),
      );
    });

    test('and declines when that serving has gone', () {
      final Food without = Food(
        id: cheese.id,
        name: cheese.name,
        source: FoodSource.manual,
        servingOptions: <ServingOption>[cup('cup-a', kcal: 200, fiberG: 7)],
      );
      final RecentLog recent = RecentLogs.from(<MealPlanEntry>[
        loggedSix(cheese),
      ]).single;

      // Null rather than the default row: there is no honest number to
      // repeat, so the one-tap path has to ask instead of guessing.
      expect(
        EntryResolver.servingForEntry(without, recent.servingOptionId),
        isNull,
      );
    });
  });

  testWidgets('and reading that amount back in cups does not re-cost it', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.text('oz'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, '30');
    await pumpFrames(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.textContaining('600 kcal'), findsOneWidget);

    // A chip is a change of reading, not of amount — the same reason a
    // remembered unit on a reopened entry may not move the macros either.
    await tester.tap(find.text('1 cup').first);
    await pumpFrames(tester);

    expect(find.textContaining('600 kcal'), findsOneWidget);
  });
}
