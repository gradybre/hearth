import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

void main() {
  testWidgets(
    'a future restaurant build saves the intended plan without logging',
    (WidgetTester tester) async {
      final DateTime tomorrow = addDays(dayKey(DateTime.now()), 1);
      final HearthDatabase db = await pumpHearthApp(
        tester,
        selectedDate: tomorrow,
        foods: <Food>[
          aFood(
            'Steakburger',
            id: 'burger',
            brand: "Freddy's",
            source: FoodSource.restaurant,
            servingOptions: <ServingOption>[
              ServingOption(
                id: 'one',
                label: '1 burger',
                amount: Quantity.of(1, Units.item),
                macros: const Macros(
                  kcal: 460,
                  proteinG: 26,
                  carbG: 32,
                  fatG: 24,
                ),
              ),
            ],
          ),
        ],
      );
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Add to dinner'));
      await pumpFrames(tester);
      await tester.tap(find.text('Plan a restaurant meal'));
      await pumpFrames(tester);
      await tester.tap(find.text("Freddy's").last);
      await pumpFrames(tester);
      await tester.tap(find.text('Steakburger').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Review meal'));
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField).first, "Friday's burger");
      await tester.tap(find.text('Save and add to dinner'));
      await pumpFrames(tester, frames: 24);
      final MealPlanEntryRow entry =
          (await db.select(db.mealPlanEntries).get()).single;
      expect(entry.isLogged, isFalse);
      expect(entry.macroSnapshot, isNull);
      expect(entry.mealSlot, 'dinner');
      expect((await db.select(db.mealPlanDays).get()).single.day, tomorrow);
    },
  );
}
