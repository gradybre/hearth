import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/recipes/recipe_scaler.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  final DateTime tuesday = DateTime.utc(2026, 8, 25, 18, 30);

  MealPlanEntry plannedDinner({double servings = 1}) => MealPlanEntry(
    id: 'entry-1',
    dayId: 'day-1',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'recipe-1',
    servings: servings,
  );

  group('freezing (spec §4)', () {
    test('logging captures macros, portion, and label', () {
      final MealPlanEntry logged = plannedDinner(servings: 1.5).log(
        liveMacros: const Macros(kcal: 400, proteinG: 30),
        at: tuesday,
        label: 'Chicken and rice',
        coverage: const NutrientCoverage.notRecorded(),
      );

      expect(logged.isLogged, isTrue);
      expect(logged.loggedAt, tuesday);
      expect(logged.macroSnapshot!.servings, 1.5);
      expect(logged.macroSnapshot!.label, 'Chicken and rice');
      expect(logged.macroSnapshot!.macros.kcal, 600);
      expect(logged.macroSnapshot!.macros.proteinG, 45);
    });

    test('a logged entry reports from its snapshot, not from live data', () {
      final MealPlanEntry logged = plannedDinner().log(
        liveMacros: const Macros(kcal: 400),
        at: tuesday,
        label: 'Chicken and rice',
        coverage: const NutrientCoverage.notRecorded(),
      );
      // Even handed wildly different live macros, history does not move.
      expect(
        logged.contribution(plannedMacros: const Macros(kcal: 9999)).kcal,
        400,
      );
    });

    test('editing the recipe afterwards leaves the log untouched', () {
      final Map<String, Food> foods = <String, Food>{
        'food-chicken': aFoodPer100g(
          'chicken breast',
          kcal: 165,
          protein: 31,
          id: 'food-chicken',
        ),
      };
      final Recipe original = aRecipe(
        id: 'recipe-1',
        servings: 2,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            amount: 400,
            unit: Units.gram,
            foodId: 'food-chicken',
          ),
        ],
      );

      final MealPlanEntry logged = plannedDinner().log(
        liveMacros: MacroCalculator.forRecipe(
          original,
          foods: foods,
        ).perServing,
        at: tuesday,
        label: original.title,
        coverage: MacroCalculator.forRecipe(original, foods: foods).coverage,
      );
      final double loggedKcal = logged.macroSnapshot!.macros.kcal;

      // The partner triples the recipe the next day.
      final Recipe edited = RecipeScaler.byMultiplier(original, 3).recipe;
      expect(
        MacroCalculator.forRecipe(edited, foods: foods).total.kcal,
        greaterThan(
          MacroCalculator.forRecipe(original, foods: foods).total.kcal,
        ),
      );

      // Tuesday's dinner is exactly what it was.
      expect(logged.macroSnapshot!.macros.kcal, loggedKcal);
      expect(logged.contribution().kcal, loggedKcal);
    });

    test('deleting the food behind a log does not change the log', () {
      final MealPlanEntry logged = plannedDinner().log(
        liveMacros: const Macros(kcal: 250, proteinG: 20),
        at: tuesday,
        label: 'Greek yogurt',
        coverage: const NutrientCoverage.notRecorded(),
      );
      // Soft delete removes it from search, never from history.
      expect(logged.contribution().kcal, 250);
      expect(logged.macroSnapshot!.label, 'Greek yogurt');
    });

    test('editing a logged entry carries the snapshot through untouched', () {
      final MealPlanEntry logged = plannedDinner().log(
        liveMacros: const Macros(kcal: 400),
        at: tuesday,
        label: 'Chicken and rice',
        coverage: const NutrientCoverage.notRecorded(),
      );
      final MealPlanEntry moved = logged.copyWith(slot: MealSlot.lunch);

      expect(moved.macroSnapshot, logged.macroSnapshot);
      expect(moved.contribution().kcal, 400);
    });

    test('re-logging deliberately takes a fresh snapshot', () {
      final MealPlanEntry first = plannedDinner().log(
        liveMacros: const Macros(kcal: 400),
        at: tuesday,
        label: 'Chicken and rice',
        coverage: const NutrientCoverage.notRecorded(),
      );
      final MealPlanEntry corrected = first.log(
        liveMacros: const Macros(kcal: 400),
        at: tuesday.add(const Duration(minutes: 5)),
        label: 'Chicken and rice',
        portion: 0.5,
        coverage: const NutrientCoverage.notRecorded(),
      );

      expect(corrected.macroSnapshot!.macros.kcal, 200);
      expect(corrected.macroSnapshot!.servings, 0.5);
      // The original object is unchanged — snapshots are immutable values.
      expect(first.macroSnapshot!.macros.kcal, 400);
    });
  });

  group('planned but not logged', () {
    test('costs live, scaled by the planned portion', () {
      expect(
        plannedDinner(servings: 2)
            .contribution(plannedMacros: const Macros(kcal: 300))
            .kcal,
        600,
      );
    });

    test('contributes nothing when live macros are unavailable', () {
      expect(plannedDinner().contribution(), Macros.zero);
    });
  });
}
