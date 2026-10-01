import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
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
  combinedIngredientsTests();

  group('nutrition per serving', () {
    testWidgets('a fully matched recipe shows its numbers', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        shortRibs(oilFoodId: 'food-oil'),
        foods: <Food>[oliveOilPerTbsp()],
      );

      expect(find.text('Nutrition'), findsOneWidget);
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

      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.textContaining('not matched to a food'), findsOneWidget);
    });

    testWidgets('a recipe with no ingredients shows no nutrition section', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        aRecipe(id: 'recipe-empty', title: 'Just a title'),
      );

      expect(find.text('Nutrition'), findsNothing);
    });
  });

  group('nutrition basis and confidence', () {
    Future<void> choose(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await pumpFrames(tester);
    }

    testWidgets('whole dish scales while per serving stays the same', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        shortRibs(oilFoodId: 'food-oil'),
        foods: <Food>[oliveOilPerTbsp()],
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Per serving'))
            .selected,
        isTrue,
      );
      expect(
        find.text('4 servings · 60 kcal each · 240 kcal whole dish'),
        findsOneWidget,
      );
      await choose(tester, 'Whole dish');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        240,
      );
      await choose(tester, '2×');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        480,
      );
      expect(find.text('Serves 8'), findsOneWidget);
      expect(
        find.text('8 servings · 60 kcal each · 480 kcal whole dish'),
        findsOneWidget,
      );
      await choose(tester, 'Per serving');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        60,
      );
    });

    testWidgets('both bases qualify partial nutrition and minor nutrients', (
      WidgetTester tester,
    ) async {
      final Food oil = aFood(
        'Oil',
        id: 'oil',
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.tbsp,
            macros: const Macros(kcal: 120, fatG: 14, fiberG: 2, sodiumMg: 100),
          ),
        ],
      );
      final Recipe recipe = aRecipe(
        id: 'partial',
        title: 'Partial supper',
        servings: 4,
        ingredients: <RecipeIngredient>[
          anIngredient('oil', amount: 2, unit: Units.tbsp, foodId: 'oil'),
          anIngredient('mystery beans', amount: 1, unit: Units.can),
        ],
      );
      await openRecipe(tester, recipe, foods: <Food>[oil]);
      expect(
        find.text('Known nutrition · 1 of 2 ingredients counted'),
        findsOneWidget,
      );
      expect(
        find.text(
          '4 servings · 60 kcal each known · 240 kcal whole dish known',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Some ingredients are not counted'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<MinorNutrientsLine>(find.byType(MinorNutrientsLine))
            .macros
            .fiberG,
        1,
      );
      await choose(tester, 'Whole dish');
      expect(
        tester
            .widget<MinorNutrientsLine>(find.byType(MinorNutrientsLine))
            .macros
            .fiberG,
        4,
      );
      expect(find.textContaining('not matched to a food'), findsOneWidget);
      await choose(tester, '2×');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        480,
      );
      expect(
        find.text('Known nutrition · 1 of 2 ingredients counted'),
        findsOneWidget,
      );
    });

    testWidgets('an approximate package remains approximate in both bases', (
      WidgetTester tester,
    ) async {
      final Quantity servingAmount = Quantity.of(0.5, Units.cup);
      final Quantity packageAmount = Quantity.of(200, Units.gram);
      final Food sauce = aFood(
        'Sauce',
        id: 'sauce',
        packSize: packageAmount,
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 4,
          servingOptionId: 'half-cup',
          servingAmount: servingAmount,
          packageAmount: packageAmount,
          isApproximate: true,
        ),
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'half-cup',
            label: 'Half cup',
            amount: servingAmount,
            macros: const Macros(kcal: 100, sodiumMg: 50),
          ),
        ],
      );
      await openRecipe(
        tester,
        aRecipe(
          id: 'approximate',
          title: 'Saucy supper',
          servings: 4,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'sauce',
              amount: 100,
              unit: Units.gram,
              foodId: 'sauce',
            ),
          ],
        ),
        foods: <Food>[sauce],
      );
      expect(find.text('Uses approximate package servings'), findsOneWidget);
      expect(
        find.text(
          '4 servings · about 50 kcal each · about 200 kcal whole dish',
        ),
        findsOneWidget,
      );
      await choose(tester, 'Whole dish');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        200,
      );
      expect(find.text('Uses approximate package servings'), findsOneWidget);
      await choose(tester, '2×');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        400,
      );
      expect(find.textContaining('about 50 kcal each'), findsOneWidget);
    });

    testWidgets('unknown stays unknown in the whole dish', (
      WidgetTester tester,
    ) async {
      await openRecipe(tester, shortRibs());
      await choose(tester, 'Whole dish');
      expect(find.text('Nutrition not available yet'), findsOneWidget);
      expect(find.byType(MacroStatsRow), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('fractional yield is stated without rounding away the basis', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        aRecipe(
          id: 'fractional',
          title: 'Quarter serving',
          servings: 0.25,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'oil',
              amount: 2,
              unit: Units.tbsp,
              foodId: 'food-oil',
            ),
          ],
        ),
        foods: <Food>[oliveOilPerTbsp()],
      );
      expect(find.text('Serves ¼'), findsOneWidget);
      expect(
        find.text('¼ servings · 960 kcal each · 240 kcal whole dish'),
        findsOneWidget,
      );
    });

    testWidgets('a missing yield does not claim per-serving nutrition', (
      WidgetTester tester,
    ) async {
      await openRecipe(
        tester,
        aRecipe(
          id: 'zero-yield',
          title: 'Yield missing',
          servings: 0,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'olive oil',
              amount: 2,
              unit: Units.tbsp,
              foodId: 'food-oil',
            ),
          ],
        ),
        foods: <Food>[oliveOilPerTbsp()],
      );
      expect(
        find.text('Set a recipe yield to see nutrition per serving.'),
        findsOneWidget,
      );
      expect(find.byType(MacroStatsRow), findsNothing);
      await choose(tester, 'Whole dish');
      expect(
        tester.widget<MacroStatsRow>(find.byType(MacroStatsRow)).macros.kcal,
        240,
      );
      expect(
        find.text('Recipe yield needs a positive number of servings'),
        findsOneWidget,
      );
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

      await tester.drag(find.byType(ListView).last, const Offset(0, -250));
      await pumpFrames(tester);
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

/// Reading the ingredients as one list rather than three.
///
/// Two teaspoons of cumin in the beef and two in the sauce is four teaspoons
/// to buy, and adding that up by eye is the thing this removes.
void combinedIngredientsTests() {
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
            'ground cumin',
            amount: 2,
            unit: Units.tsp,
            sectionId: 'sec-beef',
          ),
        ],
        steps: <RecipeStep>[
          aStep('Brown the beef', sectionId: 'sec-beef', stepNumber: 1),
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
          aStep('Whisk the sauce', sectionId: 'sec-sauce', stepNumber: 2),
        ],
      ),
    ],
  );

  group('combining the ingredients', () {
    testWidgets('the same thing in two sections adds up', (
      WidgetTester tester,
    ) async {
      await openRecipe(tester, ragu());

      // As written: two lines of two.
      expect(find.text('2 tsp'), findsNWidgets(2));

      await tester.tap(find.text('Combined'));
      await pumpFrames(tester);

      expect(find.text('1⅓ tbsp'), findsOneWidget);
      expect(find.text('2 tsp'), findsNothing);
    });

    testWidgets('the method stays grouped, because cooking is', (
      WidgetTester tester,
    ) async {
      // Combining the ingredients is a way of reading the list. The steps
      // belong to their sections — cook-along reads a step's amounts out of
      // the section it is in.
      await openRecipe(tester, ragu());
      await tester.tap(find.text('Combined'));
      await pumpFrames(tester);

      expect(find.text('Beef'), findsOneWidget);
      expect(find.text('Sauce'), findsOneWidget);
      expect(find.textContaining('Brown the beef'), findsOneWidget);
      expect(find.textContaining('Whisk the sauce'), findsOneWidget);
    });

    testWidgets('it composes with scaling rather than fighting it', (
      WidgetTester tester,
    ) async {
      await openRecipe(tester, ragu());
      await tester.tap(find.text('Combined'));
      await pumpFrames(tester);
      // Double the recipe: four teaspoons becomes eight.
      await tester.tap(find.text('2×'));
      await pumpFrames(tester);

      expect(find.text('2⅔ tbsp'), findsOneWidget);
    });

    testWidgets('a recipe with one section is not offered the choice', (
      WidgetTester tester,
    ) async {
      // There is nothing to combine, and a switch between a list and the same
      // list is a decision nobody should be asked to make.
      await openRecipe(tester, shortRibs());

      expect(find.text('Combined'), findsNothing);
      expect(find.text('By section'), findsNothing);
    });
  });
}
