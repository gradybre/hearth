import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Cooking a recipe you have scaled (Brendan's report).
///
/// He doubled a turkey bowl on the recipe page — 1 lb became 2 lb — tapped
/// Cook, and the step beside the turkey said 16 oz. Which is one pound: the
/// original amount, in the unit it happened to be typed in. Two separate
/// wrongs in one line, and the dangerous one is that cooking it would have
/// used half the turkey.
void main() {
  Recipe turkeyBowl() => aRecipe(
    id: 'recipe-turkey',
    title: 'Turkey apple bowl',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 'sec',
        ingredients: <RecipeIngredient>[
          // Authored in ounces, which is how the two bugs came apart: the
          // reading surfaces promote it to pounds, the cook-along did not.
          anIngredient(
            'ground turkey',
            amount: 16,
            unit: Units.ounce,
            sectionId: 'sec',
          ),
        ],
        steps: <RecipeStep>[
          aStep('Brown the ground turkey.', sectionId: 'sec', stepNumber: 1),
        ],
      ),
    ],
  );

  Future<void> openRecipe(WidgetTester tester) async {
    await pumpHearthApp(tester, recipes: <Recipe>[turkeyBowl()]);
    await pumpFrames(tester);
    await tester.tap(find.text('Turkey apple bowl'));
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('the steps read in the same unit as the ingredient list', (
    WidgetTester tester,
  ) async {
    // Cook-along is a reading surface — it is *the* reading surface — so it
    // honours the reader's units like every other one. Showing "16 oz" beside
    // a list that says "1 lb" makes a cook check whether they are the same
    // number.
    await openRecipe(tester);
    expect(find.text('1 lb'), findsOneWidget);

    await tester.tap(find.text('Cook'));
    await pumpFrames(tester, frames: 12);

    expect(find.textContaining('1 lb ground turkey'), findsOneWidget);
    expect(find.textContaining('16 oz'), findsNothing);
  });

  testWidgets('doubling the recipe doubles what the steps say', (
    WidgetTester tester,
  ) async {
    // The one that would have cost him a meal: the Cook button sat outside
    // the body that holds the scale, so it handed over the recipe as written.
    await openRecipe(tester);
    await tester.tap(find.text('2×'));
    await pumpFrames(tester);
    expect(find.text('2 lb'), findsOneWidget);

    await tester.tap(find.text('Cook'));
    await pumpFrames(tester, frames: 12);

    expect(find.textContaining('2 lb ground turkey'), findsOneWidget);
    expect(find.textContaining('1 lb'), findsNothing);
  });
}
