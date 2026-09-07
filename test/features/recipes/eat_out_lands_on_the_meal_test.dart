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

/// A meal built from a menu lands on the meal it was built for (U04).
///
/// The builder starts on the day screen — a particular day, a particular slot
/// — and ends three screens later in the recipe editor. The editor knew only
/// that a recipe had been written, so it saved it and stopped: the meal
/// somebody was in the middle of logging was never logged, and they had to go
/// back and find it. Anything that recovered the day at the far end would
/// have recovered *today's*, so a dinner built for last Tuesday would have
/// become tonight's.
void main() {
  Food burger() => aFood(
    'Steakburger',
    id: 'f-burger',
    brand: "Freddy's",
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'one',
        label: '1 burger',
        amount: Quantity.of(1, Units.item),
        macros: const Macros(kcal: 460, proteinG: 26, carbG: 32, fatG: 24),
      ),
    ],
  );

  testWidgets('the day screen offers the builder from the meal you are in', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: <Food>[burger()]);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.byTooltip('Add to dinner').first);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Ate out — build it from a menu'), findsOneWidget);
  });

  testWidgets('and the build ends on a button naming that meal', (
    WidgetTester tester,
  ) async {
    // The whole journey: the day screen, the log sheet, the restaurant
    // builder, and the editor at the end of it. What the button says is the
    // visible proof that the meal travelled — "Save" would mean it had not.
    await pumpHearthApp(tester, foods: <Food>[burger()]);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.byTooltip('Add to dinner').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Ate out — build it from a menu'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text("Freddy's").last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Steakburger').last);
    await pumpFrames(tester, frames: 12);

    // The builder's own button, which counts what you have picked.
    await tester.tap(find.textContaining('Build ('));
    await pumpFrames(tester, frames: 16);

    expect(
      find.text('Save and log dinner'),
      findsOneWidget,
      reason: 'the meal did not travel through the builder',
    );
  });

  testWidgets('and saving logs it, on that day and in that slot', (
    WidgetTester tester,
  ) async {
    // The point of the whole exercise. Before this the editor saved the
    // recipe and stopped, so the meal was never logged at all.
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[burger()],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    // A day that is not today, so "it went somewhere" and "it went to the
    // right place" cannot be confused.
    await tester.tap(find.byTooltip('Previous day'));
    await pumpFrames(tester, frames: 12);
    final DateTime built = DateTime.now().subtract(const Duration(days: 1));

    await tester.tap(find.byTooltip('Add to dinner').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Ate out — build it from a menu'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text("Freddy's").last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Steakburger').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.textContaining('Build ('));
    await pumpFrames(tester, frames: 16);

    // The editor is a review step, and a recipe needs a name — the builder
    // deliberately does not invent one from the menu items.
    await tester.enterText(find.byType(TextField).first, 'Freddy\'s dinner');
    await pumpFrames(tester, frames: 8);

    await tester.tap(find.text('Save and log dinner'));
    await pumpFrames(tester, frames: 24);

    final List<MealPlanEntryRow> entries = await db
        .select(db.mealPlanEntries)
        .get();
    expect(entries, hasLength(1), reason: 'the meal was not logged at all');

    final MealPlanDayRow day = (await db.select(db.mealPlanDays).get()).single;
    expect(
      dayKey(day.day),
      dayKey(built),
      reason: 'the meal was logged on today instead of the day it was for',
    );
    expect(entries.single.mealSlot, 'dinner');
    expect(
      entries.single.isLogged,
      isTrue,
      reason: 'it was built because it had been eaten',
    );
    expect(
      entries.single.macroSnapshot,
      isNotNull,
      reason: 'the reviewed nutrition was not frozen',
    );
  });
}
