@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'meal-actions-phone'),
  Scene(name: 'meal-actions-dark', brightness: Brightness.dark),
  Scene(name: 'meal-actions-desktop', size: Size(1280, 900)),
  Scene(name: 'meal-actions-small-3x', size: Size(320, 568), textScale: 3),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final Scene scene in _devices) {
    for (final String state in <String>[
      'recipe',
      'food',
      'removed-serving',
      'missing',
    ]) {
      testWidgets('${scene.name}: $state open and return', (
        WidgetTester tester,
      ) async {
        final bool isRecipe = state == 'recipe';
        final Recipe recipe = aRecipe(
          id: 'dinner',
          title: 'Creamy oat and mushroom supper',
          servings: 4,
          ingredients: <RecipeIngredient>[
            anIngredient('Oats', amount: 400, unit: Units.gram),
          ],
          steps: <RecipeStep>[aStep('Stir gently and serve warm.')],
        );
        final Food food = aFood(
          'White bean soup',
          id: 'soup',
          servingOptions: <ServingOption>[
            ServingOption(
              id: 'bowl',
              label: '250 ml bowl',
              amount: Quantity.of(250, Units.millilitre),
              macros: const Macros(
                kcal: 210,
                proteinG: 12,
                carbG: 30,
                fatG: 5,
                sodiumMg: 0,
              ),
            ),
          ],
        );
        final HearthDatabase db = await pumpHearthApp(
          tester,
          size: scene.size,
          textScale: scene.textScale,
          brightness: scene.brightness,
          viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
          launchTarget: LaunchTarget.today,
          recipes: <Recipe>[recipe],
          foods: state == 'missing' ? <Food>[] : <Food>[food],
          entries: <MealPlanEntry>[
            MealPlanEntry(
              id: 'meal',
              dayId: 'day-1',
              slot: MealSlot.breakfast,
              refType: isRecipe ? PlanRefType.recipe : PlanRefType.food,
              refId: isRecipe ? 'dinner' : 'soup',
              servings: 0.5,
              servingOptionId: state == 'removed-serving' ? 'old-bowl' : null,
            ),
          ],
        );
        final SweepTools tools = SweepTools(tester);
        final Finder mealTitle = find.text(
          isRecipe
              ? recipe.title
              : state == 'missing'
              ? 'Removed food'
              : food.name,
        );
        await tools.bring(mealTitle);
        await writeScene(tester, Scene(name: '${scene.name}-$state-row'));
        await tools.reach(mealTitle);
        await pumpFrames(tester, frames: 15);
        expect(
          find.text(
            isRecipe
                ? recipe.title
                : state == 'missing'
                ? 'Food unavailable'
                : food.name,
          ),
          findsWidgets,
        );
        await writeScene(tester, Scene(name: '${scene.name}-$state-detail'));
        if (!isRecipe) {
          await tools.bring(find.text('Go back'));
          await writeScene(tester, Scene(name: '${scene.name}-$state-return'));
          await tools.reach(find.text('Go back'));
        } else {
          await tester.pageBack();
          await pumpFrames(tester, frames: 10);
          await tools.reach(
            find.byKey(const ValueKey<String>('meal-cook-meal')),
          );
          await writeScene(
            tester,
            Scene(name: '${scene.name}-full-recipe-cook'),
          );
          await tester.tap(find.byTooltip('Finish cooking'));
          await pumpFrames(tester, frames: 10);
        }
        final MealPlanEntryRow saved =
            (await db.select(db.mealPlanEntries).get()).single;
        expect(saved.servings, 0.5);
        expect(saved.isLogged, isFalse);
        expect(saved.macroSnapshot, isNull);
        expect(tester.takeException(), isNull);
      }, skip: !renderingGallery);
    }
  }
}
