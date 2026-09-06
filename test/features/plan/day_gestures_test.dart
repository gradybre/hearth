import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The three gestures on a day's entries (spec §5.6).
///
/// Confirming a meal is the thing you do most, so it is the plainest gesture
/// there is. Editing the portion used to be what a tap did, which put the
/// commonest action behind a sheet and a second tap.
Food yogurt() => aFood(
  'Greek yogurt',
  id: 'food-yogurt',
  servingOptions: <ServingOption>[
    aServing(
      amount: 170,
      unit: Units.gram,
      macros: const Macros(kcal: 100, proteinG: 17),
    ),
  ],
);

MealPlanEntry planned({bool logged = false}) {
  const MealPlanEntry base = MealPlanEntry(
    id: 'entry-1',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'food-yogurt',
    servings: 1,
  );
  if (!logged) return base;
  return base.log(
    liveMacros: const Macros(kcal: 100, proteinG: 17),
    at: DateTime.utc(2026, 8, 31, 9),
    label: 'Greek yogurt',
  );
}

Future<HearthDatabase> openDay(
  WidgetTester tester, {
  bool logged = false,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    foods: <Food>[yogurt()],
    entries: <MealPlanEntry>[planned(logged: logged)],
  );
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester);
  return db;
}

Future<MealPlanEntryRow?> entryRow(HearthDatabase db) async {
  final List<MealPlanEntryRow> rows = await db.select(db.mealPlanEntries).get();
  return rows.isEmpty ? null : rows.single;
}

void main() {
  group('tap', () {
    testWidgets('logs a planned entry', (WidgetTester tester) async {
      final HearthDatabase db = await openDay(tester);
      expect(find.textContaining('tap to log'), findsOneWidget);

      await tester.tap(find.text('Greek yogurt'));
      await pumpFrames(tester, frames: 12);

      final MealPlanEntryRow row = (await entryRow(db))!;
      expect(row.isLogged, isTrue);
      // The snapshot is taken now, from the library as it stands (§4).
      expect(row.macroSnapshot, contains('100'));
    });

    testWidgets('and takes the log back, for the same one tap', (
      WidgetTester tester,
    ) async {
      // A meal confirmed by mistake should cost exactly what confirming it
      // cost.
      final HearthDatabase db = await openDay(tester, logged: true);
      expect(find.textContaining('tap to undo'), findsOneWidget);

      await tester.tap(find.text('Greek yogurt'));
      await pumpFrames(tester, frames: 12);

      final MealPlanEntryRow row = (await entryRow(db))!;
      expect(row.isLogged, isFalse);
      expect(row.macroSnapshot, isNull);
      expect(row.isPlanned, isTrue, reason: 'it is still on the day');
    });

    testWidgets('no longer opens the portion sheet', (
      WidgetTester tester,
    ) async {
      await openDay(tester);
      await tester.tap(find.text('Greek yogurt'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Portion'), findsNothing);
    });
  });

  group('long press', () {
    testWidgets('offers the portion and a way to remove', (
      WidgetTester tester,
    ) async {
      await openDay(tester);
      await tester.longPress(find.text('Greek yogurt'));
      await tester.pumpAndSettle();

      expect(find.text('Edit portion'), findsOneWidget);
      expect(find.text('Remove from this day'), findsOneWidget);
    });

    testWidgets('editing the portion opens the sheet that has it', (
      WidgetTester tester,
    ) async {
      await openDay(tester);
      await tester.longPress(find.text('Greek yogurt'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit portion'));
      await tester.pumpAndSettle();

      expect(find.text('Portion'), findsOneWidget);
    });

    testWidgets('removing takes it off the day', (WidgetTester tester) async {
      final HearthDatabase db = await openDay(tester);
      await tester.longPress(find.text('Greek yogurt'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from this day'));
      await pumpFrames(tester, frames: 12);

      expect(await entryRow(db), isNull);
    });
  });

  group('swipe', () {
    /// Swiping *reveals* the delete rather than doing it — the same two-step
    /// every other list in the app uses, so a sleeve brushing the screen
    /// cannot lose a meal.
    Future<void> swipeOpen(WidgetTester tester) async {
      await tester.drag(find.text('Greek yogurt'), const Offset(-400, 0));
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('opens a delete rather than deleting outright', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openDay(tester);
      await swipeOpen(tester);

      expect(find.text('Delete'), findsOneWidget);
      expect(await entryRow(db), isNotNull, reason: 'not yet');
    });

    testWidgets('and the delete removes it, with the usual undo', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openDay(tester);
      await swipeOpen(tester);

      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, frames: 12);

      expect(await entryRow(db), isNull);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('and the undo gives back a logged meal as logged', (
      WidgetTester tester,
    ) async {
      // Undo has to give back what was there, not a fresh planned copy: the
      // frozen numbers are the whole record of what was eaten.
      final HearthDatabase db = await openDay(tester, logged: true);

      await swipeOpen(tester);
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 15);

      final MealPlanEntryRow row = (await entryRow(db))!;
      expect(row.isLogged, isTrue);
      expect(row.servings, 1);
    });
  });

  testWidgets('the undo puts back the meal that was eaten, not double it', (
    WidgetTester tester,
  ) async {
    // R01 through the gesture rather than the repository: two servings at 100
    // kcal each is a 200 kcal dinner, and swiping it away and changing your
    // mind must leave the day exactly where it started.
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Guard stew',
          id: 'food-stew',
          servingOptions: <ServingOption>[
            aServing(
              amount: 1,
              unit: Units.item,
              macros: const Macros(kcal: 100, proteinG: 8),
            ),
          ],
        ),
      ],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'entry-stew',
          dayId: 'day-1',
          slot: MealSlot.dinner,
          refType: PlanRefType.food,
          refId: 'food-stew',
          servings: 2,
        ).log(
          liveMacros: const Macros(kcal: 100, proteinG: 8),
          at: DateTime.utc(2026, 8, 31, 19),
          label: 'Guard stew',
        ),
      ],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    await tester.drag(find.text('Guard stew'), const Offset(-400, 0));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Undo'));
    await pumpFrames(tester, frames: 20);

    final List<MealPlanEntryRow> rows = await db
        .select(db.mealPlanEntries)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.macroSnapshot, contains('"kcal":200.0'));
  });
}
