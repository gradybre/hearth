@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/week_view_preference.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'week-meals-phone'),
  Scene(name: 'week-meals-phone-dark', brightness: Brightness.dark),
  Scene(name: 'week-meals-desktop', size: Size(1280, 800)),
  Scene(
    name: 'week-meals-desktop-dark',
    size: Size(1280, 800),
    brightness: Brightness.dark,
  ),
  Scene(name: 'week-meals-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'week-meals-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets(
      '${scene.name}: dinner names, other meals and retained Nutrition',
      (WidgetTester tester) async {
        final DateTime monday = DateTime(2026, 9, 28);
        final List<String> titles = <String>[
          'Lemon chicken',
          'Roasted squash with lentils and a warm tahini dressing',
          'Vegetable soup',
          'Salmon and rice',
          'Friday pizza',
          'Tomato pasta',
          'Sunday roast',
        ];
        final Food oats = aFood(
          'Porridge oats',
          id: 'oats',
          servingOptions: <ServingOption>[
            aServing(
              id: 'oats-serving',
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 370, proteinG: 12, carbG: 59, fatG: 7),
            ),
          ],
        );
        final List<Recipe> recipes = <Recipe>[
          for (int i = 0; i < 7; i++)
            aRecipe(
              id: 'recipe-$i',
              title: titles[i],
              servings: 4,
              ingredients: <RecipeIngredient>[
                anIngredient(
                  'Oats',
                  amount: 100,
                  unit: Units.gram,
                  foodId: oats.id,
                ),
              ],
              steps: <RecipeStep>[
                aStep('Cook gently, stirring from time to time.'),
              ],
            ),
        ];
        final Map<DateTime, List<MealPlanEntry>> week =
            <DateTime, List<MealPlanEntry>>{
              for (int i = 0; i < 7; i++)
                addDays(monday, i): <MealPlanEntry>[
                  MealPlanEntry(
                    id: 'dinner-$i',
                    dayId: 'day-$i',
                    slot: MealSlot.dinner,
                    refType: PlanRefType.recipe,
                    refId: 'recipe-$i',
                    servings: 1,
                  ),
                  if (i == 0)
                    MealPlanEntry(
                      id: 'breakfast',
                      dayId: 'day-$i',
                      slot: MealSlot.breakfast,
                      refType: PlanRefType.food,
                      refId: oats.id,
                      servings: 1,
                    ).log(
                      liveMacros: const Macros(
                        kcal: 1840,
                        proteinG: 100,
                        carbG: 180,
                        fatG: 70,
                      ),
                      coverage: const NutrientCoverage.notRecorded(),
                      at: monday,
                      label: 'Porridge with fruit',
                    ),
                ],
            };
        await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          selectedDate: monday,
          recipes: recipes,
          foods: <Food>[oats],
          weekEntries: week,
          targets: galleryTargets,
          size: scene.size,
          brightness: scene.brightness,
          textScale: scene.textScale,
          viewPadding: scene.size.width >= 840
              ? const EdgeInsets.only(top: 24)
              : const EdgeInsets.only(top: 24, bottom: 34),
        );
        final SweepTools tools = SweepTools(tester);
        await tools.planView('Week');
        expect(find.text('Lemon chicken'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-initial'));

        await tools.reach(
          find.byKey(const ValueKey<String>('week-other-meals-2026-09-28')),
        );
        await tools.bring(find.text('Porridge with fruit'));
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-other-meals'));

        await tools.bring(find.text('Sunday roast'));
        await tools.bring(
          find.byKey(const ValueKey<String>('week-add-2026-10-04-dinner')),
        );
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-sunday'));

        final Finder control = find.byKey(
          const ValueKey<String>('week-content-control'),
        );
        if (control.evaluate().isEmpty) {
          await tester.dragUntilVisible(
            control,
            SweepTools.verticalScroller,
            const Offset(0, 500),
            maxIteration: 100,
          );
          await pumpFrames(tester);
        }
        await tools.bring(control);
        if (tester.widget(control) is PopupMenuButton<WeekContentView> ||
            tester.widget(control) is Semantics) {
          await tools.reach(control);
        }
        await tools.reach(
          find.byKey(const ValueKey<String>('week-content-nutrition')),
        );
        expect(find.textContaining('1840'), findsWidgets);
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-nutrition'));
      },
      skip: !renderingGallery,
    );
  }
}
