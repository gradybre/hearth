import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

void main() {
  testWidgets('a third of a menu portion stays readable and exact at 3x', (
    tester,
  ) async {
    final db = await pumpHearthApp(
      tester,
      size: const Size(320, 568),
      textScale: 3,
      recipes: <Recipe>[
        aRecipe(
          id: 'saved-usual',
          title: 'Rice side',
          servings: 1,
          kind: RecipeKind.eatenOut,
          notes: 'Corner Kitchen',
          ingredients: [
            anIngredient(
              'Rice',
              amount: 100,
              unit: Units.gram,
              foodId: 'usual-rice',
            ),
          ],
        ),
      ],
      foods: <Food>[
        aFood(
          'Rice',
          id: 'usual-rice',
          brand: 'Corner Kitchen',
          source: FoodSource.restaurant,
          servingOptions: [
            aServing(
              amount: 300,
              unit: Units.gram,
              macros: const Macros(kcal: 600),
            ),
          ],
        ),
      ],
    );
    final tools = SweepTools(tester);
    await tools.tab('Recipes');
    await tools.reach(find.text('Add recipe'));
    await tools.reach(find.text('Eat out'));
    await tools.reach(find.text('Corner Kitchen'));
    await tools.reach(find.byKey(const Key('usual-customize-saved-usual')));
    await tools.bring(find.byTooltip('One more'));
    expect(tester.takeException(), isNull);
    expect(find.text('⅓×'), findsOneWidget);

    final review = find.byKey(const Key('usual-review-variation'));
    await tester.dragUntilVisible(
      review,
      SweepTools.verticalScroller,
      const Offset(0, 180),
      maxIteration: 100,
    );
    await tools.reach(review);
    final draft = tester
        .widget<RecipeEditorScreen>(find.byType(RecipeEditorScreen))
        .draft!;
    expect(
      draft.parsedIngredients.single.quantity!.amountIn(Units.gram),
      closeTo(100, 1e-9),
    );
    expect(await db.select(db.recipes).get(), hasLength(1));
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
