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
}
