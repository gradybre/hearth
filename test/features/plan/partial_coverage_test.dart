import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';

import '../../support/fixtures.dart';

/// A partial total stays qualified all the way to the day (spec §5.6, R06).
///
/// A recipe with five grams of known fibre and one ingredient that never
/// stated any sums, by `Macros._add`, to a non-null five grams. The number is
/// real and it is a **floor** — and every screen between the recipe and the
/// day used to lose that distinction, because a non-null subtotal is
/// indistinguishable from a complete one once the ingredients are out of
/// sight.
///
/// Once the meal is logged the ingredients are gone for good, so the
/// qualification has to be frozen with the numbers or it cannot exist at all.
void main() {
  final Food oats = aFood(
    'Oats',
    id: 'food-oats',
    servingOptions: <ServingOption>[
      aServing(
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 380, fiberG: 5),
      ),
    ],
  );
  // States calories and nothing else — the ingredient that does not know.
  final Food syrup = aFood(
    'Golden syrup',
    id: 'food-syrup',
    servingOptions: <ServingOption>[
      aServing(amount: 20, unit: Units.gram, macros: const Macros(kcal: 60)),
    ],
  );

  Recipe porridge() => aRecipe(
    id: 'recipe-porridge',
    title: 'Porridge',
    servings: 1,
    ingredients: <RecipeIngredient>[
      anIngredient('Oats', amount: 100, unit: Units.gram, foodId: 'food-oats'),
      anIngredient(
        'Golden syrup',
        amount: 20,
        unit: Units.gram,
        foodId: 'food-syrup',
      ),
    ],
  );

  final Map<String, Food> foods = <String, Food>{
    'food-oats': oats,
    'food-syrup': syrup,
  };

  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 120,
    carbG: 200,
    fatG: 60,
  );

  MealPlanEntry entryFor({required bool logged}) {
    const MealPlanEntry planned = MealPlanEntry(
      id: 'entry-porridge',
      dayId: 'day-1',
      slot: MealSlot.breakfast,
      refType: PlanRefType.recipe,
      refId: 'recipe-porridge',
      servings: 1,
    );
    if (!logged) return planned;

    final ResolvedEntry live = EntryResolver.resolveAll(
      <MealPlanEntry>[planned],
      recipes: <String, Recipe>{'recipe-porridge': porridge()},
      foods: foods,
    ).single;

    return planned.log(
      liveMacros: live.perServing,
      at: DateTime.utc(2026, 9, 5, 8),
      label: 'Porridge',
      coverage: live.liveCoverage,
    );
  }

  DayProgress dayOf(MealPlanEntry entry) {
    final List<ResolvedEntry> resolved = EntryResolver.resolveAll(
      <MealPlanEntry>[entry],
      recipes: <String, Recipe>{'recipe-porridge': porridge()},
      foods: foods,
    );
    return DayProgress.fromParts(
      parts: EntryResolver.eatenParts(resolved),
      coverage: EntryResolver.eatenCoverage(resolved),
      targets: targets,
    );
  }

  test('the recipe itself knows one ingredient did not say', () {
    final ResolvedEntry resolved = EntryResolver.resolveAll(
      <MealPlanEntry>[entryFor(logged: false)],
      recipes: <String, Recipe>{'recipe-porridge': porridge()},
      foods: foods,
    ).single;

    expect(resolved.perServing.fiberG, 5);
    expect(
      resolved.liveCoverage.of(MinorNutrient.fiber),
      MinorCoverage.partial,
    );
    // Calories are stated by both, so they are not in doubt.
    expect(resolved.perServing.kcal, 440);
  });

  test('and the day says so once it is logged', () {
    // The failure this whole change is about: 5 g rendered as a complete
    // total, with the qualification stranded on the recipe page.
    final MinorProgress fibre = dayOf(entryFor(logged: true))
        .minor(MinorNutrient.fiber);

    expect(fibre.consumed, 5);
    expect(fibre.isKnown, isTrue);
    expect(fibre.isPartial, isTrue, reason: 'the total is a floor, not a sum');
  });

  test('a planned meal is qualified the same way, from live coverage', () {
    final ResolvedEntry resolved = EntryResolver.resolveAll(
      <MealPlanEntry>[entryFor(logged: false)],
      recipes: <String, Recipe>{'recipe-porridge': porridge()},
      foods: foods,
    ).single;

    expect(
      resolved.contributionCoverage.of(MinorNutrient.fiber),
      MinorCoverage.partial,
    );
  });

  test('editing the recipe afterwards cannot make yesterday look complete', () {
    // Rule 3, at the one seam where it could be lost: the frozen coverage
    // answers, not today's ingredients.
    final MealPlanEntry logged = entryFor(logged: true);

    final Recipe mended = aRecipe(
      id: 'recipe-porridge',
      title: 'Porridge',
      servings: 1,
      ingredients: <RecipeIngredient>[
        anIngredient(
          'Oats',
          amount: 100,
          unit: Units.gram,
          foodId: 'food-oats',
        ),
      ],
    );

    final ResolvedEntry resolved = EntryResolver.resolveAll(
      <MealPlanEntry>[logged],
      recipes: <String, Recipe>{'recipe-porridge': mended},
      foods: foods,
    ).single;

    expect(
      resolved.contributionCoverage.of(MinorNutrient.fiber),
      MinorCoverage.partial,
    );
  });

  test('a recipe whose every ingredient states it is complete', () {
    final Recipe plain = aRecipe(
      id: 'recipe-porridge',
      title: 'Porridge',
      servings: 1,
      ingredients: <RecipeIngredient>[
        anIngredient(
          'Oats',
          amount: 100,
          unit: Units.gram,
          foodId: 'food-oats',
        ),
      ],
    );

    final ResolvedEntry resolved = EntryResolver.resolveAll(
      <MealPlanEntry>[entryFor(logged: false)],
      recipes: <String, Recipe>{'recipe-porridge': plain},
      foods: foods,
    ).single;

    expect(
      resolved.liveCoverage.of(MinorNutrient.fiber),
      MinorCoverage.complete,
    );
  });
}
