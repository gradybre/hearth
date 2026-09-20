import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';
import 'package:hearth/features/plan/log_sheet.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('Plan only and reopen keep the package-selected nutrition row', (
    tester,
  ) async {
    final food = Food(
      id: 'f',
      name: 'Package example',
      source: FoodSource.manual,
      packSize: Quantity.of(10, Units.ounce),
      servingOptions: [
        ServingOption(
          id: 'default',
          label: 'Default cup',
          amount: Quantity.of(1, Units.cup),
          macros: const Macros(kcal: 200, fiberG: 7),
        ),
        ServingOption(
          id: 'package',
          label: 'Label cup',
          amount: Quantity.of(1, Units.cup),
          macros: const Macros(kcal: 100),
        ),
      ],
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'package',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
        isApproximate: true,
      ),
    );
    final db = await pumpHearthApp(tester, foods: [food]);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Add to breakfast'));
    await pumpFrames(tester);
    await tester.tap(find.text(food.name));
    await pumpFrames(tester);
    await tester.tap(find.text('oz'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.textContaining('600 kcal'), findsOneWidget);
    await tester.tap(find.text('Plan only'));
    await pumpFrames(tester, frames: 12);
    final rows = await db.select(db.mealPlanEntries).get();
    final entry = PlanMapper.entryToDomain(rows.single);
    final resolved = EntryResolver.resolve(
      entry,
      recipes: {},
      foods: {food.id: food},
    );
    expect(resolved.contribution.kcal, closeTo(600, 1e-8));
    expect(resolved.contribution.fiberG, isNull);
    unawaited(
      showLogSheet(
        tester.element(find.byType(Scaffold).first),
        date: DateTime.now(),
        slot: MealSlot.breakfast,
        existing: resolved,
      ),
    );
    await pumpFrames(tester, frames: 12);
    expect(find.textContaining('600 kcal'), findsOneWidget);
    await tester.tap(find.text('Log it'));
    await pumpFrames(tester, frames: 12);
    final logged = PlanMapper.entryToDomain(
      (await db.select(db.mealPlanEntries).get()).single,
    );
    expect(logged.macroSnapshot!.macros.kcal, closeTo(600, 1e-8));
    expect(logged.macroSnapshot!.macros.fiberG, isNull);
    expect(logged.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
  });
}
