@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'log-undo-phone'),
  Scene(name: 'log-undo-dark', brightness: Brightness.dark),
  Scene(name: 'log-undo-desktop', size: Size(1280, 900)),
  Scene(name: 'log-undo-small-3x', size: Size(320, 568), textScale: 3),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    for (final bool logged in <bool>[false, true]) {
      testWidgets('${scene.name}: ${logged ? 'Unlog' : 'Log'} and Undo', (
        WidgetTester tester,
      ) async {
        const MealPlanEntry planned = MealPlanEntry(
          id: 'undo-meal',
          dayId: 'undo-day',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'yogurt',
          servings: 1.5,
        );
        final MealPlanEntry entry = logged
            ? planned.log(
                liveMacros: const Macros(kcal: 170, proteinG: 17),
                at: DateTime(2026, 6, 2, 8, 15),
                label: 'Yogurt as eaten',
                coverage: const NutrientCoverage.notRecorded(),
              )
            : planned;
        final db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          size: scene.size,
          textScale: scene.textScale,
          brightness: scene.brightness,
          viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
          entries: <MealPlanEntry>[entry],
          readPlanEntriesFromStore: true,
          foods: <Food>[
            aFood(
              'Current yogurt',
              id: 'yogurt',
              servingOptions: <ServingOption>[
                aServing(
                  id: 'pot',
                  label: '170 g pot',
                  amount: 170,
                  unit: Units.gram,
                  macros: const Macros(kcal: 200, proteinG: 20),
                ),
              ],
            ),
          ],
        );
        final before = (await db.select(db.mealPlanEntries).get()).single;
        final SweepTools tools = SweepTools(tester);
        await tools.reach(
          find.byKey(const ValueKey<String>('meal-log-undo-meal')),
        );
        expect(
          find.text(logged ? 'Meal unlogged.' : 'Meal logged.'),
          findsOneWidget,
        );
        expect(find.text('Undo').hitTestable(), findsOneWidget);
        expect(
          (await db.select(db.mealPlanEntries).get()).single.isLogged,
          !logged,
        );
        expect(tester.takeException(), isNull);
        final String name = '${scene.name}-${logged ? 'unlog' : 'log'}';
        await writeScene(tester, Scene(name: '$name-offer'));

        await tools.reach(find.text('Undo'));
        expect(find.text('Change undone.'), findsOneWidget);
        final after = (await db.select(db.mealPlanEntries).get()).single;
        expect(after.isLogged, before.isLogged);
        expect(after.macroSnapshot, before.macroSnapshot);
        expect(after.loggedAt, before.loggedAt);
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '$name-restored'));
      }, skip: !renderingGallery);
    }
  }
}
