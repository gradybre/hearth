import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  final DateTime loggedAt = DateTime.utc(2026, 8, 27, 18, 30);

  final Food chicken = aFoodPer100g(
    'Chicken breast',
    kcal: 165,
    protein: 31,
    id: 'food-chicken',
  );

  final Recipe ribs = aRecipe(
    id: 'recipe-ribs',
    title: 'Braised short ribs',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 'sec',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            amount: 400,
            unit: Units.gram,
            sectionId: 'sec',
            foodId: 'food-chicken',
          ),
        ],
      ),
    ],
  );

  final Map<String, Recipe> recipes = <String, Recipe>{'recipe-ribs': ribs};
  final Map<String, Food> foods = <String, Food>{'food-chicken': chicken};

  MealPlanEntry entry({
    PlanRefType refType = PlanRefType.recipe,
    String refId = 'recipe-ribs',
    double servings = 1,
    bool logged = false,
    Macros? snapshotMacros,
    String label = '',
  }) {
    final MealPlanEntry base = MealPlanEntry(
      id: 'entry-1',
      dayId: 'day-1',
      slot: MealSlot.dinner,
      refType: refType,
      refId: refId,
      servings: servings,
    );
    if (!logged) return base;
    return base.log(
      liveMacros: snapshotMacros ?? const Macros(kcal: 400),
      at: loggedAt,
      label: label,
      coverage: const NutrientCoverage.notRecorded(),
    );
  }

  group('resolving a recipe', () {
    test('costs it per serving from the live library', () {
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(),
        recipes: recipes,
        foods: foods,
      );

      expect(resolved.label, 'Braised short ribs');
      expect(resolved.isResolvable, isTrue);
      // 400 g chicken at 165/100 g = 660 kcal, over 4 servings.
      expect(resolved.perServing.kcal, closeTo(165, 0.01));
    });

    test('a planned entry is costed live and scaled by its portion', () {
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(servings: 2),
        recipes: recipes,
        foods: foods,
      );
      expect(resolved.contribution.kcal, closeTo(330, 0.02));
    });
  });

  group('resolving a food', () {
    test('counts multiples of its default serving', () {
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(refType: PlanRefType.food, refId: 'food-chicken', servings: 1.5),
        recipes: recipes,
        foods: foods,
      );

      expect(resolved.label, 'Chicken breast');
      expect(resolved.servingLabel, '100 g');
      expect(resolved.contribution.kcal, closeTo(247.5, 0.01));
    });
  });

  group('a logged entry answers from its snapshot (spec §4)', () {
    test('and ignores the live library entirely', () {
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(logged: true, snapshotMacros: const Macros(kcal: 900)),
        recipes: recipes,
        foods: foods,
      );
      expect(resolved.contribution.kcal, 900);
    });

    test('stays readable after the recipe is deleted', () {
      // The payoff of freezing: history survives its source disappearing.
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(
          logged: true,
          snapshotMacros: const Macros(kcal: 900),
          label: 'Braised short ribs',
        ),
        recipes: const <String, Recipe>{},
        foods: const <String, Food>{},
      );

      expect(resolved.label, 'Braised short ribs');
      expect(resolved.contribution.kcal, 900);
      expect(resolved.isResolvable, isFalse);
      // It is not "uncostable" — it was already costed, permanently.
      expect(resolved.isUncostable, isFalse);
    });
  });

  group('a planned entry whose reference is gone', () {
    test('is flagged rather than silently counted as zero', () {
      final ResolvedEntry resolved = EntryResolver.resolve(
        entry(refId: 'recipe-that-vanished'),
        recipes: recipes,
        foods: foods,
      );

      expect(resolved.isResolvable, isFalse);
      expect(resolved.isUncostable, isTrue);
      expect(resolved.label, 'Removed recipe');
      expect(resolved.contribution, Macros.zero);
    });
  });

  group('day totals', () {
    List<ResolvedEntry> day() => EntryResolver.resolveAll(
      <MealPlanEntry>[
        const MealPlanEntry(
          id: 'a',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'food-chicken',
          servings: 1,
        ).log(
          liveMacros: const Macros(kcal: 165, proteinG: 31),
          at: loggedAt,
          label: 'Chicken breast',
          coverage: const NutrientCoverage.notRecorded(),
        ),
        const MealPlanEntry(
          id: 'b',
          dayId: 'day-1',
          slot: MealSlot.dinner,
          refType: PlanRefType.recipe,
          refId: 'recipe-ribs',
          servings: 1,
        ),
      ],
      recipes: recipes,
      foods: foods,
    );

    test('eaten counts only what was logged (spec §5.6)', () {
      // What matters is what you ate, not what you intended to.
      expect(EntryResolver.eaten(day()).kcal, 165);
    });

    test('stillPlanned counts only what has not been eaten', () {
      expect(EntryResolver.stillPlanned(day()).kcal, closeTo(165, 0.01));
    });

    test('the two never double-count the same entry', () {
      final List<ResolvedEntry> entries = day();
      final double total =
          EntryResolver.eaten(entries).kcal +
          EntryResolver.stillPlanned(entries).kcal;
      expect(total, closeTo(330, 0.02));
    });

    test('slots partition the day', () {
      final List<ResolvedEntry> entries = day();
      expect(EntryResolver.inSlot(entries, MealSlot.breakfast), hasLength(1));
      expect(EntryResolver.inSlot(entries, MealSlot.dinner), hasLength(1));
      expect(EntryResolver.inSlot(entries, MealSlot.lunch), isEmpty);
    });
  });
}
