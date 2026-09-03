import 'package:hearth/domain/foods/no_match_rule.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_list_builder.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// Which of the plan a shopping list is made of (spec §5.7).
void main() {
  final DateTime monday = DateTime(2026, 9, 7);
  final DateTime friday = DateTime(2026, 9, 11);
  final DateTime nextWed = DateTime(2026, 9, 16);

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
          anIngredient('coriander', sectionId: 's1', optional: true),
        ],
      ),
    ],
  );

  Recipe bolognese() => aRecipe(
    id: 'r-bol',
    title: 'Bolognese',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's2',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'ground beef',
            amount: 1,
            unit: Units.pound,
            sectionId: 's2',
          ),
        ],
      ),
    ],
  );

  Food yogurt() => aFood(
    'Greek yogurt',
    id: 'f-yog',
    servingOptions: <ServingOption>[
      aServing(amount: 170, unit: Units.gram, macros: const Macros(kcal: 100)),
    ],
  );

  MealPlanEntry planned({
    required String id,
    required String refId,
    PlanRefType type = PlanRefType.recipe,
    double servings = 4,
    bool logged = false,
  }) {
    final MealPlanEntry base = MealPlanEntry(
      id: id,
      dayId: 'day',
      slot: MealSlot.dinner,
      refType: type,
      refId: refId,
      servings: servings,
    );
    return logged
        ? base.log(
            liveMacros: const Macros(kcal: 500),
            at: DateTime(2026, 9, 8),
            label: 'eaten',
          )
        : base;
  }

  List<ShoppingLine> build({
    required Map<DateTime, List<MealPlanEntry>> byDay,
    DateTime? from,
    DateTime? to,
    bool includeSeasonings = false,
  }) => ShoppingListBuilder.forRange(
    from: from ?? monday,
    to: to ?? nextWed,
    entriesByDay: byDay,
    recipes: <String, Recipe>{'r-chilli': chilli(), 'r-bol': bolognese()},
    foods: <String, Food>{'f-yog': yogurt()},
    seasonings: NoMatchRules.none,
    includeSeasonings: includeSeasonings,
  );

  ShoppingLine? named(List<ShoppingLine> lines, String name) {
    for (final ShoppingLine line in lines) {
      if (line.name == name) return line;
    }
    return null;
  }

  group('what the plan adds up to', () {
    test('the same ingredient in two recipes is one line', () {
      final List<ShoppingLine> lines = build(
        byDay: <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[planned(id: 'a', refId: 'r-chilli')],
          friday: <MealPlanEntry>[planned(id: 'b', refId: 'r-bol')],
        },
      );

      expect(
        named(lines, 'ground beef')!.planned.single.amountIn(Units.pound),
        2,
      );
    });

    test('a recipe planned at half its yield contributes half', () {
      final List<ShoppingLine> lines = build(
        byDay: <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[
            planned(id: 'a', refId: 'r-chilli', servings: 2),
          ],
        },
      );

      expect(
        named(lines, 'ground beef')!.planned.single.amountIn(Units.pound),
        0.5,
      );
    });

    test('an optional ingredient stays off the list', () {
      final List<ShoppingLine> lines = build(
        byDay: <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[planned(id: 'a', refId: 'r-chilli')],
        },
      );

      expect(named(lines, 'coriander'), isNull);
    });

    test(
      'a food planned on its own gets a line the recipes cannot give it',
      () {
        // The consolidator only walks recipes. A yoghurt planned for Tuesday is
        // still shopping.
        final List<ShoppingLine> lines = build(
          byDay: <DateTime, List<MealPlanEntry>>{
            monday: <MealPlanEntry>[
              planned(
                id: 'a',
                refId: 'f-yog',
                type: PlanRefType.food,
                servings: 3,
              ),
            ],
          },
        );

        final ShoppingLine yog = named(lines, 'Greek yogurt')!;
        expect(yog.planned.single.amountIn(Units.gram), 510);
      },
    );
  });

  group('what it leaves out', () {
    test('anything already logged — it was bought before it was eaten', () {
      // Brendan's case: a recipe cooked on Tuesday and still being eaten on
      // Thursday must not send him to the shop for it again.
      final List<ShoppingLine> lines = build(
        byDay: <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[
            planned(id: 'a', refId: 'r-chilli', logged: true),
          ],
        },
      );

      expect(lines, isEmpty);
    });

    test('anything outside the range', () {
      final List<ShoppingLine> lines = build(
        from: friday,
        to: nextWed,
        byDay: <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[planned(id: 'a', refId: 'r-chilli')],
          nextWed: <MealPlanEntry>[planned(id: 'b', refId: 'r-bol')],
        },
      );

      // Monday's chilli is before the range; only the bolognese counts.
      expect(
        named(lines, 'ground beef')!.planned.single.amountIn(Units.pound),
        1,
      );
    });

    test('seasonings, unless you ask for them', () {
      // Spices are bought on their own rhythm. NoMatchRules already knows
      // which lines those are.
      Map<DateTime, List<MealPlanEntry>> day() =>
          <DateTime, List<MealPlanEntry>>{
            monday: <MealPlanEntry>[planned(id: 'a', refId: 'r-chilli')],
          };

      expect(named(build(byDay: day()), 'cumin'), isNull);
      expect(
        named(build(byDay: day(), includeSeasonings: true), 'cumin'),
        isNotNull,
      );
    });
  });

  group('two spellings of one ingredient are one line', () {
    // Recipes say "sun-dried tomatoes" and "sun dried tomatoes"
    // interchangeably. While the hyphen survived normalisation these were
    // different keys, so the list showed two lines for one thing and you
    // bought it twice — the exact opposite of what aggregation is for.
    test('an unmatched ingredient keys the same either way', () {
      expect(
        ShoppingListBuilder.keyFor(name: 'Sun-dried tomatoes'),
        ShoppingListBuilder.keyFor(name: 'sun dried tomatoes'),
      );
    });

    test('and a matched one still keys by its food', () {
      // Unchanged: a matched line never depended on the wording at all.
      expect(
        ShoppingListBuilder.keyFor(foodId: 'food-1', name: 'Sun-dried'),
        'food-1',
      );
    });
  });

  group('a meal you order rather than cook (spec §5.2, §5.7)', () {
    test('never reaches the list, however firmly it is planned', () {
      // The bug this exists to stop: a Chipotle bowl planned for Thursday
      // sending you to the shop for 4 oz of chicken and 2 oz of sour cream.
      final Recipe bowl = aRecipe(
        id: 'r-bowl',
        title: 'Burrito bowl',
        servings: 1,
        kind: RecipeKind.eatenOut,
        ingredients: <RecipeIngredient>[
          anIngredient('chicken', amount: 4, unit: Units.ounce),
          anIngredient('white rice', amount: 4, unit: Units.ounce),
        ],
      );

      final List<ShoppingLine> lines = ShoppingListBuilder.forRange(
        from: DateTime.utc(2026, 9, 7),
        to: DateTime.utc(2026, 9, 13),
        entriesByDay: <DateTime, List<MealPlanEntry>>{
          DateTime.utc(2026, 9, 10): <MealPlanEntry>[
            const MealPlanEntry(
              id: 'e-bowl',
              dayId: 'd1',
              slot: MealSlot.lunch,
              refType: PlanRefType.recipe,
              refId: 'r-bowl',
              servings: 1,
            ),
          ],
        },
        recipes: <String, Recipe>{'r-bowl': bowl},
        foods: const <String, Food>{},
      );

      expect(lines, isEmpty);
    });

    test('and does not take the week\'s cooking down with it', () {
      // The exclusion has to be per recipe, not per day: eating out on
      // Thursday says nothing about Wednesday's chilli.
      final Recipe bowl = aRecipe(
        id: 'r-bowl',
        title: 'Burrito bowl',
        servings: 1,
        kind: RecipeKind.eatenOut,
        ingredients: <RecipeIngredient>[
          anIngredient('chicken', amount: 4, unit: Units.ounce),
        ],
      );
      final Recipe chilli = aRecipe(
        id: 'r-chilli',
        title: 'Chilli',
        servings: 4,
        ingredients: <RecipeIngredient>[
          anIngredient('ground beef', amount: 1, unit: Units.pound),
        ],
      );

      final List<ShoppingLine> lines = ShoppingListBuilder.forRange(
        from: DateTime.utc(2026, 9, 7),
        to: DateTime.utc(2026, 9, 13),
        entriesByDay: <DateTime, List<MealPlanEntry>>{
          DateTime.utc(2026, 9, 10): <MealPlanEntry>[
            const MealPlanEntry(
              id: 'e-bowl',
              dayId: 'd1',
              slot: MealSlot.lunch,
              refType: PlanRefType.recipe,
              refId: 'r-bowl',
              servings: 1,
            ),
            const MealPlanEntry(
              id: 'e-chilli',
              dayId: 'd1',
              slot: MealSlot.dinner,
              refType: PlanRefType.recipe,
              refId: 'r-chilli',
              servings: 4,
            ),
          ],
        },
        recipes: <String, Recipe>{'r-bowl': bowl, 'r-chilli': chilli},
        foods: const <String, Food>{},
      );

      expect(lines.map((ShoppingLine l) => l.name), <String>['ground beef']);
    });
  });
}
