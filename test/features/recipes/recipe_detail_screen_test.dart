import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/macro_stats_row.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Food oliveOilPerTbsp() => aFood(
  'Olive oil',
  id: 'food-oil',
  servingOptions: <ServingOption>[
    aServing(
      amount: 1,
      unit: Units.tbsp,
      macros: const Macros(kcal: 120, fatG: 14),
    ),
  ],
);

Recipe shortRibs({String? oilFoodId}) => aRecipe(
  id: 'recipe-1',
  title: 'Braised short ribs',
  servings: 4,
  sections: <RecipeSection>[
    aSection(
      id: 'sec',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'olive oil',
          amount: 2,
          unit: Units.tbsp,
          sectionId: 'sec',
          foodId: oilFoodId,
        ),
      ],
    ),
  ],
);

Future<void> openRecipe(
  WidgetTester tester,
  Recipe recipe, {
  List<Food> foods = const <Food>[],
}) async {
  await pumpHearthApp(tester, recipes: <Recipe>[recipe], foods: foods);
  await pumpFrames(tester);
  await tester.tap(find.text(recipe.title));
  await pumpFrames(tester, frames: 12);
}

void main() {
  group('nutrition per serving', () {
    testWidgets('a fully matched recipe shows its numbers', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        shortRibs(oilFoodId: 'food-oil'),
        foods: <Food>[oliveOilPerTbsp()],
      );

      expect(find.text('Nutrition per serving'), findsOneWidget);
      expect(find.byType(MacroStatsRow), findsOneWidget);
      // 2 tbsp at 120 kcal / 14 g fat per tbsp, across 4 servings.
      expect(find.text('60'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('an unmatched ingredient still shows the section, flagged', (
      WidgetTester tester,
    ) async {
      // Missing data flags, never blocks (spec §5.3): unlike the dense
      // library card, this screen has room for the caveat, so the section
      // stays rather than disappearing.
      await openRecipe(tester, shortRibs());

      expect(find.text('Nutrition per serving'), findsOneWidget);
      expect(find.textContaining('not matched to a food'), findsOneWidget);
    });

    testWidgets('a recipe with no ingredients shows no nutrition section', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        aRecipe(id: 'recipe-empty', title: 'Just a title'),
      );

      expect(find.text('Nutrition per serving'), findsNothing);
    });
  });

  group('amounts beside the directions', () {
    Recipe ragu() => aRecipe(
      id: 'recipe-ragu',
      title: 'Beef ragu bowl',
      servings: 4,
      sections: <RecipeSection>[
        aSection(
          id: 'sec-beef',
          name: 'Beef',
          sortOrder: 0,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'ground beef',
              amount: 2,
              unit: Units.pound,
              sectionId: 'sec-beef',
            ),
            anIngredient(
              'ground cumin',
              amount: 2,
              unit: Units.tsp,
              sectionId: 'sec-beef',
            ),
          ],
          steps: <RecipeStep>[
            aStep(
              'Brown the ground beef with the cumin',
              sectionId: 'sec-beef',
              stepNumber: 1,
            ),
          ],
        ),
        aSection(
          id: 'sec-sauce',
          name: 'Sauce',
          sortOrder: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'ground cumin',
              amount: 2,
              unit: Units.tsp,
              sectionId: 'sec-sauce',
            ),
          ],
          steps: <RecipeStep>[
            aStep(
              'Whisk the cumin into the sauce',
              sectionId: 'sec-sauce',
              stepNumber: 2,
            ),
          ],
        ),
      ],
    );

    testWidgets('a step says how much of what it names', (
      WidgetTester tester,
    ) async {
      await openRecipe(tester, ragu());

      expect(find.textContaining('2 lb ground beef'), findsOneWidget);
    });

    testWidgets('the same ingredient in two sections is never added up', (
      WidgetTester tester,
    ) async {
      // Brendan's requirement: two teaspoons in the sauce and two with the
      // beef is two teaspoons beside each step, never the four that
      // consolidating across the recipe would produce.
      await openRecipe(tester, ragu());

      expect(find.textContaining('2 tsp ground cumin'), findsNWidgets(2));
      expect(find.textContaining('4 tsp'), findsNothing);
    });

    testWidgets('scaling the recipe scales what the steps say', (
      WidgetTester tester,
    ) async {
      // The numbers come from the scaled ingredients rather than the step
      // text, so doubling the recipe cannot leave them behind.
      await openRecipe(tester, ragu());

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await pumpFrames(tester, frames: 12);

      // Five servings of a four-serving recipe: the beef goes up with it.
      expect(find.textContaining('2 lb ground beef'), findsNothing);
      expect(find.textContaining('ground beef'), findsWidgets);
    });

    testWidgets('a step naming nothing measurable stays uncluttered', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        aRecipe(
          id: 'recipe-rest',
          title: 'Resting',
          sections: <RecipeSection>[
            aSection(
              id: 'sec',
              ingredients: <RecipeIngredient>[
                anIngredient(
                  'ground beef',
                  amount: 2,
                  unit: Units.pound,
                  sectionId: 'sec',
                ),
              ],
              steps: <RecipeStep>[
                aStep('Let it rest for ten minutes', sectionId: 'sec'),
              ],
            ),
          ],
        ),
      );

      // StepAmounts is always in the tree and renders nothing when it has
      // nothing to say, so the icon is what marks a line actually appearing.
      expect(find.byIcon(Icons.straighten), findsNothing);
    });
  });
}
