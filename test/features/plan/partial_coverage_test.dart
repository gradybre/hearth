import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
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

  group('through the door the app actually uses', () {
    // The tests above hand `log` a coverage. Nothing in `lib/` did, and that
    // is how this shipped inert: `log`'s optional parameter fell back to
    // reading coverage off the summed total, which answers "complete" for
    // exactly the partial recipe this exists to qualify — and froze that
    // claim, which is worse than the absent key it replaced.
    late HearthDatabase db;
    late PlanRepository repository;

    setUp(() {
      db = HearthDatabase.forTesting(NativeDatabase.memory());
      repository = PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: PendingWriteStore(db),
        userId: 'user-1',
        clock: () => DateTime.utc(2026, 9, 5, 8),
        idFactory: () => 'entry-1',
      );
    });

    tearDown(() => db.close());

    test('a recipe logged through the repository freezes partial', () async {
      final ResolvedEntry live = EntryResolver.resolveAll(
        <MealPlanEntry>[entryFor(logged: false)],
        recipes: <String, Recipe>{'recipe-porridge': porridge()},
        foods: foods,
      ).single;

      final MealPlanEntry logged = await repository.add(
        date: DateTime(2026, 9, 5),
        slot: MealSlot.breakfast,
        refType: PlanRefType.recipe,
        refId: 'recipe-porridge',
        servings: 1,
        loggedMacros: live.perServing,
        loggedCoverage: live.liveCoverage,
        label: 'Porridge',
      );

      expect(
        logged.macroSnapshot!.coverage.of(MinorNutrient.fiber),
        MinorCoverage.partial,
      );
    });

    test('and a plain food logged the same way freezes complete', () async {
      // The fallback is right *here* — one food's non-null value really does
      // mean the food stated it. It is only a recipe's total that lies.
      final MealPlanEntry logged = await repository.add(
        date: DateTime(2026, 9, 5),
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-oats',
        servings: 1,
        loggedMacros: const Macros(kcal: 380, fiberG: 5),
        label: 'Oats',
      );

      expect(
        logged.macroSnapshot!.coverage.of(MinorNutrient.fiber),
        MinorCoverage.complete,
      );
      expect(
        logged.macroSnapshot!.coverage.of(MinorNutrient.sodium),
        MinorCoverage.unknown,
      );
    });
  });

  group('an ingredient nobody could cost', () {
    test('makes the total a floor, not a complete answer', () async {
      // A gap contributes nothing to the sum *because* it is a hole. On the
      // recipe page `incompleteReason` says so beside the number; frozen into
      // a snapshot that sentence does not travel, so the coverage has to.
      final Recipe unmatched = aRecipe(
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
          // Named, quantified, and matched to nothing.
          anIngredient('A spoon of something', amount: 1, unit: Units.item),
        ],
      );

      final ResolvedEntry resolved = EntryResolver.resolveAll(
        <MealPlanEntry>[entryFor(logged: false)],
        recipes: <String, Recipe>{'recipe-porridge': unmatched},
        foods: foods,
      ).single;

      expect(
        resolved.liveCoverage.of(MinorNutrient.fiber),
        MinorCoverage.partial,
      );
    });

    test('but salt to taste is not a hole', () async {
      // The two deliberate exclusions really are excused — they were never
      // going to contribute, so their silence is not missing information.
      final Recipe seasoned = aRecipe(
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
          anIngredient('A pinch of salt', needsNoMatch: true),
        ],
      );

      final ResolvedEntry resolved = EntryResolver.resolveAll(
        <MealPlanEntry>[entryFor(logged: false)],
        recipes: <String, Recipe>{'recipe-porridge': seasoned},
        foods: foods,
      ).single;

      expect(
        resolved.liveCoverage.of(MinorNutrient.fiber),
        MinorCoverage.complete,
      );
    });

    test('and a recipe of nothing but gaps is unknown, not unrecorded', () {
      // `notRecorded` absorbs a sum, so answering it here would silence the
      // coverage note for every other meal that day. "Asked and nothing knew"
      // is the honest answer and combines like one.
      final Recipe hopeless = aRecipe(
        id: 'recipe-porridge',
        title: 'Porridge',
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('Something', amount: 1, unit: Units.item),
        ],
      );

      final ResolvedEntry resolved = EntryResolver.resolveAll(
        <MealPlanEntry>[entryFor(logged: false)],
        recipes: <String, Recipe>{'recipe-porridge': hopeless},
        foods: foods,
      ).single;

      expect(
        resolved.liveCoverage.of(MinorNutrient.fiber),
        MinorCoverage.unknown,
      );
    });
  });

  group('the one-tap confirm, which is the commonest gesture there is', () {
    late HearthDatabase db;
    late PlanRepository repository;

    setUp(() {
      db = HearthDatabase.forTesting(NativeDatabase.memory());
      repository = PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: PendingWriteStore(db),
        userId: 'user-1',
        clock: () => DateTime.utc(2026, 9, 5, 8),
        idFactory: () => 'entry-1',
      );
    });

    tearDown(() => db.close());

    test('freezes the coverage the recipe really had', () async {
      // The door the last round missed. `add` was covered; this one was not,
      // and it is the tap that confirms a planned meal — so a partial recipe
      // was still freezing "complete" on the commonest action in the app.
      final MealPlanEntry planned = await repository.add(
        date: DateTime(2026, 9, 5),
        slot: MealSlot.breakfast,
        refType: PlanRefType.recipe,
        refId: 'recipe-porridge',
        servings: 1,
      );

      final ResolvedEntry live = EntryResolver.resolveAll(
        <MealPlanEntry>[planned],
        recipes: <String, Recipe>{'recipe-porridge': porridge()},
        foods: foods,
      ).single;

      final MealPlanEntry? logged = await repository.logEntry(
        planned.id,
        liveMacros: live.perServing,
        liveCoverage: live.liveCoverage,
        label: 'Porridge',
      );

      expect(
        logged!.macroSnapshot!.coverage.of(MinorNutrient.fiber),
        MinorCoverage.partial,
      );
    });

    test('and editing the portion afterwards keeps it', () async {
      // Re-logging builds a fresh snapshot. It must carry what the old one
      // knew, including fields a newer client wrote (§4).
      final MealPlanEntry planned = await repository.add(
        date: DateTime(2026, 9, 5),
        slot: MealSlot.breakfast,
        refType: PlanRefType.recipe,
        refId: 'recipe-porridge',
        servings: 1,
      );
      final ResolvedEntry live = EntryResolver.resolveAll(
        <MealPlanEntry>[planned],
        recipes: <String, Recipe>{'recipe-porridge': porridge()},
        foods: foods,
      ).single;

      await repository.logEntry(
        planned.id,
        liveMacros: live.perServing,
        liveCoverage: live.liveCoverage,
        label: 'Porridge',
      );
      final MealPlanEntry? bigger = await repository.logEntry(
        planned.id,
        liveMacros: live.perServing,
        liveCoverage: live.liveCoverage,
        label: 'Porridge',
        portion: 2,
      );

      expect(bigger!.macroSnapshot!.servings, 2);
      expect(
        bigger.macroSnapshot!.coverage.of(MinorNutrient.fiber),
        MinorCoverage.partial,
      );
    });
  });

  group('a recipe of nothing but seasoning', () {
    test('takes nothing away from the meals beside it', () {
      // It contributes no nutrition, so nothing about it is missing. Calling
      // it unknown would drag an otherwise complete day to "partial" over an
      // entry that added nothing at all.
      final Recipe allSalt = aRecipe(
        id: 'recipe-porridge',
        title: 'Seasoning',
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('A pinch of salt', needsNoMatch: true),
          anIngredient('Pepper to taste', needsNoMatch: true),
        ],
      );

      final ResolvedEntry resolved = EntryResolver.resolveAll(
        <MealPlanEntry>[entryFor(logged: false)],
        recipes: <String, Recipe>{'recipe-porridge': allSalt},
        foods: foods,
      ).single;

      expect(
        resolved.liveCoverage.of(MinorNutrient.fiber),
        MinorCoverage.complete,
      );
    });
  });
}
