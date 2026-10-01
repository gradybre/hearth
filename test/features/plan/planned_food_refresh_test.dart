import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

Food _food({bool updated = false}) => aFood(
  updated ? 'Updated yoghurt' : 'Yoghurt',
  id: 'yoghurt',
  servingOptions: <ServingOption>[
    ServingOption(
      id: 'pot',
      label: updated ? '200 g pot' : '170 g pot',
      amount: Quantity.of(updated ? 200 : 170, Units.gram),
      macros: updated
          ? const Macros(kcal: 400, proteinG: 40, fiberG: 8)
          : const Macros(kcal: 170, proteinG: 17),
    ),
  ],
);

void main() {
  for (final String inputState in <String>['done', 'pending', 'continued']) {
    final bool doneBeforeUpdate = inputState == 'done';
    testWidgets(
      'a removed amount unit asks for a new portion before saving ($inputState)',
      (WidgetTester tester) async {
        final StreamController<List<Food>> library =
            StreamController<List<Food>>();
        addTearDown(library.close);
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          foodStream: library.stream,
          entries: const <MealPlanEntry>[
            MealPlanEntry(
              id: 'planned-yoghurt',
              dayId: 'day-1',
              slot: MealSlot.breakfast,
              refType: PlanRefType.food,
              refId: 'yoghurt',
              servings: 1,
            ),
          ],
        );
        library.add(<Food>[_food()]);
        await pumpFrames(tester, frames: 15);
        final SweepTools sweep = SweepTools(tester);
        await sweep.reach(find.byTooltip('Edit Yoghurt'));
        await sweep.reach(find.text('Edit portion'));
        await sweep.reach(find.widgetWithText(ChoiceChip, 'g'));
        await tester.enterText(
          find.byType(TextField).last,
          inputState == 'continued' ? '12' : '125',
        );
        if (doneBeforeUpdate) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await pumpFrames(tester, frames: 8);
        library.add(<Food>[
          aFood(
            'Yoghurt',
            id: 'yoghurt',
            servingOptions: <ServingOption>[
              ServingOption(
                id: 'pot',
                label: 'pot',
                amount: Quantity.of(1, Units.piece),
                macros: const Macros(kcal: 400),
              ),
            ],
          ),
        ]);
        await pumpFrames(tester, frames: 15);
        if (inputState == 'continued') {
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '125',
              selection: TextSelection.collapsed(offset: 3),
            ),
          );
          await pumpFrames(tester, frames: 4);
        }
        await sweep.bring(find.textContaining('Log as eaten ·'));
        final Finder logAction = find.ancestor(
          of: find.textContaining('Log as eaten ·'),
          matching: find.byType(TextButton),
        );
        if (!doneBeforeUpdate) {
          await tester.tap(logAction.hitTestable());
          await pumpFrames(tester, frames: 12);
          expect(
            (await db.select(db.mealPlanEntries).get()).single.isLogged,
            isFalse,
          );
        }
        expect(tester.widget<TextButton>(logAction).onPressed, isNull);
        expect(
          find.textContaining(
            'Choose a current unit and enter the amount again',
          ),
          findsOneWidget,
        );
        expect(
          (await db.select(db.mealPlanEntries).get()).single.isLogged,
          isFalse,
        );
        await sweep.bring(find.byType(TextField).last);
        await tester.enterText(find.byType(TextField).last, '2');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpFrames(tester, frames: 8);
        await sweep.reach(find.textContaining('Log as eaten ·'));
        await pumpFrames(tester, frames: 20);
        final MacroSnapshot snapshot = PlanMapper.snapshotFromJson(
          (await db.select(db.mealPlanEntries).get()).single.macroSnapshot,
        )!;
        expect(snapshot.macros.kcal, 800);
        expect(snapshot.usableLoggedPortion!.enteredAmount, 2);
        expect(snapshot.usableLoggedPortion!.enteredUnit.label, 'pot');
      },
    );
  }

  for (final bool removeServing in <bool>[false, true]) {
    testWidgets(
      'an open planned editor cannot log a removed ${removeServing ? 'serving' : 'food'}',
      (WidgetTester tester) async {
        final StreamController<List<Food>> library =
            StreamController<List<Food>>();
        addTearDown(library.close);
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          foodStream: library.stream,
          entries: const <MealPlanEntry>[
            MealPlanEntry(
              id: 'planned-yoghurt',
              dayId: 'day-1',
              slot: MealSlot.breakfast,
              refType: PlanRefType.food,
              refId: 'yoghurt',
              servingOptionId: 'pot',
              servings: 1,
            ),
          ],
        );
        library.add(<Food>[_food()]);
        await pumpFrames(tester, frames: 15);
        final SweepTools sweep = SweepTools(tester);
        await sweep.reach(find.byTooltip('Edit Yoghurt'));
        await sweep.reach(find.text('Edit portion'));
        library.add(<Food>[if (removeServing) aFood('Yoghurt', id: 'yoghurt')]);
        await pumpFrames(tester, frames: 15);
        await sweep.bring(find.textContaining('Log as eaten ·'));
        final Finder logAction = find.ancestor(
          of: find.textContaining('Log as eaten ·'),
          matching: find.byType(TextButton),
        );
        expect(tester.widget<TextButton>(logAction).onPressed, isNull);
        expect(
          (await db.select(db.mealPlanEntries).get()).single.isLogged,
          isFalse,
        );
        expect(
          find.text(
            'This food or serving is no longer available. Close and choose a current food.',
          ),
          findsOneWidget,
        );
      },
    );
  }

  for (final bool typedBeforeUpdate in <bool>[false, true]) {
    testWidgets(
      'planned food refresh ${typedBeforeUpdate ? 'after' : 'before'} typing keeps amount, nutrition and receipt consistent',
      (WidgetTester tester) async {
        final StreamController<List<Food>> library =
            StreamController<List<Food>>();
        addTearDown(library.close);
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          foodStream: library.stream,
          entries: const <MealPlanEntry>[
            MealPlanEntry(
              id: 'planned-yoghurt',
              dayId: 'day-1',
              slot: MealSlot.breakfast,
              refType: PlanRefType.food,
              refId: 'yoghurt',
              servings: 1,
            ),
          ],
        );
        library.add(<Food>[_food()]);
        await pumpFrames(tester, frames: 15);
        final SweepTools sweep = SweepTools(tester);
        await sweep.reach(find.byTooltip('Edit Yoghurt'));
        await sweep.reach(find.text('Edit portion'));
        await sweep.reach(find.widgetWithText(ChoiceChip, 'g'));
        final double amount = typedBeforeUpdate ? 125 : 100;
        if (typedBeforeUpdate) {
          await tester.enterText(find.byType(TextField).last, '$amount');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await pumpFrames(tester, frames: 8);
        }
        library.add(<Food>[_food(updated: true)]);
        await pumpFrames(tester, frames: 15);
        if (!typedBeforeUpdate) {
          await tester.enterText(find.byType(TextField).last, '$amount');
        }
        await sweep.reach(find.textContaining('Log as eaten ·'));
        await pumpFrames(tester, frames: 20);
        final MealPlanEntry saved = PlanMapper.entryToDomain(
          (await db.select(db.mealPlanEntries).get()).single,
        );
        final MacroSnapshot snapshot = saved.macroSnapshot!;
        expect(snapshot.macros.kcal, amount * 2);
        expect(snapshot.macros.proteinG, closeTo(amount / 5, 1e-9));
        expect(snapshot.macros.fiberG, closeTo(amount / 25, 1e-9));
        expect(
          snapshot.coverage,
          NutrientCoverage.ofOne(_food(updated: true).defaultServing!.macros),
        );
        expect(snapshot.label, 'Updated yoghurt');
        expect(snapshot.servings, amount / 200);
        expect(snapshot.usableLoggedPortion, isNotNull);
        expect(snapshot.usableLoggedPortion!.enteredAmount, amount);
        expect(snapshot.usableLoggedPortion!.enteredUnit.label, 'g');
        expect(
          snapshot.usableLoggedPortion!.nutritionServing.label,
          '200 g pot',
        );
        expect(
          snapshot.usableLoggedPortion!.nutritionServing.amount.canonicalAmount,
          200,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
