@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'logged-details-phone'),
  Scene(name: 'logged-details-dark', brightness: Brightness.dark),
  Scene(name: 'logged-details-desktop', size: Size(1280, 900)),
  Scene(name: 'logged-details-small-3x', size: Size(320, 568), textScale: 3),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final Scene scene in _devices) {
    for (final bool legacy in <bool>[false, true]) {
      testWidgets(
        '${scene.name}: ${legacy ? 'legacy' : 'saved amount'} receipt',
        (WidgetTester tester) async {
          final ServingOption serving = ServingOption(
            id: 'pot',
            label: '170 g pot',
            amount: Quantity.of(170, Units.gram),
            macros: const Macros(
              kcal: 170,
              proteinG: 17,
              carbG: 13,
              fatG: 4,
              fiberG: 2,
              sodiumMg: 0,
            ),
          );
          final MealPlanEntry entry =
              const MealPlanEntry(
                id: 'meal',
                dayId: 'day-1',
                slot: MealSlot.breakfast,
                refType: PlanRefType.food,
                refId: 'yoghurt',
                servings: 125 / 170,
              ).log(
                liveMacros: serving.macros,
                at: DateTime(2026, 9, 28, 8, 30),
                label: 'Yoghurt with oats',
                coverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
                  MinorNutrient.fiber: MinorCoverage.partial,
                  MinorNutrient.sodium: MinorCoverage.complete,
                  MinorNutrient.cholesterol: MinorCoverage.unknown,
                }),
                usesApproximatePackage: true,
                loggedPortion: legacy
                    ? null
                    : LoggedPortion.tryCapture(
                        amount: 125,
                        unit: const PortionUnit.raw(Units.gram),
                        servings: 125 / 170,
                        standard: serving,
                      ),
              );
          final db = await pumpHearthApp(
            tester,
            launchTarget: LaunchTarget.today,
            size: scene.size,
            textScale: scene.textScale,
            brightness: scene.brightness,
            entries: <MealPlanEntry>[entry],
            foods: <Food>[
              if (!legacy)
                Food(
                  id: 'yoghurt',
                  name: 'Yoghurt as it is today',
                  source: FoodSource.manual,
                  servingOptions: <ServingOption>[
                    ServingOption(
                      id: 'pot',
                      label: '200 g pot',
                      amount: Quantity.of(200, Units.gram),
                      macros: const Macros(kcal: 200),
                    ),
                  ],
                ),
            ],
            viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
          );
          final String name = '${scene.name}-${legacy ? 'legacy' : 'exact'}';
          final SweepTools tools = SweepTools(tester);
          await tools.bring(
            find.byKey(const ValueKey<String>('meal-open-meal')),
          );
          await writeScene(tester, Scene(name: '$name-row'));
          await tools.reach(find.byTooltip('Edit Yoghurt with oats'));
          await writeScene(tester, Scene(name: '$name-menu'));
          await tools.reach(find.text('View logged details'));
          expect(find.text('Logged details'), findsOneWidget);
          await writeScene(tester, Scene(name: '$name-start'));
          await tools.bring(find.textContaining('Calories:'));
          await writeScene(tester, Scene(name: '$name-nutrition'));
          await tools.bring(find.text('Close'));
          await writeScene(tester, Scene(name: '$name-actions'));
          await tools.reach(find.text('Close'));
          expect(find.text('Logged details'), findsNothing);
          expect(
            (await db.select(db.mealPlanEntries).get()).single.servings,
            entry.servings,
          );
          expect(tester.takeException(), isNull);
        },
        skip: !renderingGallery,
      );
    }
  }
}
