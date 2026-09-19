import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';

void main() {
  final pack = Quantity.of(10, Units.ounce);
  final cup = Quantity.of(1, Units.cup);
  final selected = ServingOption(
    id: 'label-cup',
    label: 'Label cup',
    amount: cup,
    macros: const Macros(kcal: 100),
  );
  Food food({bool removed = false}) => Food(
    id: 'corn',
    name: 'Corn',
    source: FoodSource.manual,
    packSize: pack,
    servingOptions: [
      ServingOption(
        id: 'default',
        label: 'Other cup',
        amount: cup,
        macros: const Macros(kcal: 200, fiberG: 7),
      ),
      if (!removed) selected,
    ],
    packageNutrition: PackageNutrition.manual(
      servingsPerPackage: 2,
      servingOptionId: selected.id,
      servingAmount: cup,
      packageAmount: pack,
      isApproximate: true,
    ),
  );
  final source =
      const MealPlanEntry(
        id: 'old',
        dayId: 'd',
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'corn',
        servings: 6,
        servingOptionId: 'label-cup',
      ).log(
        liveMacros: selected.macros,
        label: 'Corn',
        at: DateTime(2026, 9, 18),
        usesApproximatePackage: true,
        coverage: NutrientCoverage.ofOne(selected.macros),
      );
  for (final removed in [false, true]) {
    testWidgets(
      removed
          ? 'repeat refuses a removed serving'
          : 'one tap repeat freezes 600 kcal from the selected cup',
      (tester) async {
        final db = await pumpHearthApp(
          tester,
          foods: [food(removed: removed)],
          recentLogs: RecentLogs.from([source]),
        );
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester);
        await tester.tap(find.byTooltip('Add to breakfast'));
        await pumpFrames(tester);
        await tester.tap(find.text('log again · 6 servings'));
        await pumpFrames(tester, frames: 12);
        final rows = await db.select(db.mealPlanEntries).get();
        if (removed) {
          expect(rows, isEmpty);
          expect(find.textContaining('has been removed'), findsOneWidget);
        } else {
          final entry = PlanMapper.entryToDomain(rows.single);
          expect(entry.servingOptionId, 'label-cup');
          expect(entry.macroSnapshot!.macros.kcal, 600);
          expect(entry.macroSnapshot!.macros.fiberG, isNull);
          expect(entry.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
        }
      },
    );
  }
}
