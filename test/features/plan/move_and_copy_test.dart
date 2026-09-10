import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Moving one meal, and planning it again (review N02).
///
/// The journey, not the repository: the two operations are only worth having
/// if they are reachable from the meal itself, and the correction they exist
/// to replace — delete it, log it again on the right day — is exactly the one
/// that rewrites what was eaten.
void main() {
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

  MealPlanEntry lunch() =>
      const MealPlanEntry(
        id: 'entry-1',
        dayId: 'day-1',
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-yogurt',
        servings: 2,
      ).log(
        liveMacros: const Macros(kcal: 100, proteinG: 17),
        at: DateTime.utc(2026, 8, 31, 9),
        label: 'Greek yogurt',
        coverage: const NutrientCoverage.notRecorded(),
      );

  Future<HearthDatabase> openDay(WidgetTester tester) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[yogurt()],
      entries: <MealPlanEntry>[lunch()],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    return db;
  }

  Future<void> openOptions(WidgetTester tester) async {
    await tester.longPress(find.text('Greek yogurt'));
    await pumpFrames(tester, frames: 12);
  }

  /// Reaches a day in the destination list and chooses it.
  ///
  /// Scrolled to, because the list is lazy and now starts a week behind the
  /// one on screen — so the day after today is genuinely below the fold and
  /// not merely off it: no finder can see a row a `ListView` has not built.
  Future<void> chooseDay(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.textContaining(label),
      120,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
    await pumpFrames(tester, frames: 8);
    await tester.tap(find.textContaining(label));
    await pumpFrames(tester, frames: 8);
  }

  testWidgets('a meal offers to move and to be planned again', (
    WidgetTester tester,
  ) async {
    await openDay(tester);
    await openOptions(tester);

    expect(find.text('Move to another day or meal…'), findsOneWidget);
    expect(find.text('Plan this again…'), findsOneWidget);
    // Both said in words on the sheet, because the difference between them is
    // the whole of the decision and neither name carries it alone.
    expect(
      find.text('Keeps what it was worth when you ate it'),
      findsOneWidget,
    );
    expect(
      find.text("Uses the food's nutrition as it stands then"),
      findsOneWidget,
    );
  });

  testWidgets('the day it was really eaten on can be behind you', (
    WidgetTester tester,
  ) async {
    // The correction this exists for is noticing a mis-filed meal a day or
    // two later, and that direction is backwards. The picker offered this
    // week and the next — forward-looking, which is right for meal-prep
    // assignment and wrong here: open the app on a Monday and *yesterday* is
    // in the week before, so the commonest correction of all could not be
    // made at all.
    final DateTime monday = startOfWeek(DateTime.now());
    _FixedDate.date = monday;
    await pumpHearthApp(
      tester,
      foods: <Food>[yogurt()],
      entries: <MealPlanEntry>[lunch()],
      extraOverrides: <Object>[
        selectedDateProvider.overrideWith(_FixedDate.new),
      ],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    await openOptions(tester);
    await tester.tap(find.text('Move to another day or meal…'));
    await pumpFrames(tester, frames: 12);

    final DateTime yesterday = addDays(monday, -1);
    expect(
      find.textContaining(shortDate(yesterday)),
      findsOneWidget,
      reason: 'the day before the week started was not offered',
    );
  });

  testWidgets('moving it keeps the frozen snapshot and the same record', (
    WidgetTester tester,
  ) async {
    // The reason this exists. Delete-and-relog would re-cost the meal from
    // the food as it stands now, which is how correcting a date came to
    // rewrite nutrition (non-negotiable 3).
    final HearthDatabase db = await openDay(tester);
    final MealPlanEntryRow before =
        (await db.select(db.mealPlanEntries).get()).single;

    await openOptions(tester);
    await tester.tap(find.text('Move to another day or meal…'));
    await pumpFrames(tester, frames: 12);

    // Any day the picker offers that is not the one it is already on.
    await chooseDay(tester, 'tomorrow');
    // The chip, not the day screen's own "Dinner" heading behind the sheet.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dinner'));
    await pumpFrames(tester, frames: 8);
    await tester.tap(find.text('Move it'));
    await pumpFrames(tester, frames: 20);

    final MealPlanEntryRow after =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(after.id, before.id, reason: 'a move is not a new record');
    expect(after.macroSnapshot, before.macroSnapshot);
    expect(after.servings, 2);
    expect(after.mealSlot, MealSlot.dinner.name);
    expect(after.dayId, isNot(before.dayId));

    // And it says where it went. Both of these put their result on another
    // day, so the screen left behind is either unchanged or has quietly lost
    // a row — with nothing said, there is no way to tell it worked.
    expect(find.textContaining('Moved to dinner on'), findsOneWidget);
  });

  testWidgets('and planning it again leaves the original alone', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openDay(tester);

    await openOptions(tester);
    await tester.tap(find.text('Plan this again…'));
    await pumpFrames(tester, frames: 12);

    await chooseDay(tester, 'tomorrow');
    await tester.tap(find.text('Plan it'));
    await pumpFrames(tester, frames: 20);

    final List<MealPlanEntryRow> rows = await db
        .select(db.mealPlanEntries)
        .get();
    expect(rows, hasLength(2), reason: 'the copy replaced rather than added');

    final MealPlanEntryRow original = rows.firstWhere(
      (MealPlanEntryRow r) => r.id == 'entry-1',
    );
    final MealPlanEntryRow copy = rows.firstWhere(
      (MealPlanEntryRow r) => r.id != 'entry-1',
    );

    expect(original.isLogged, isTrue);
    expect(
      kcal(original.macroSnapshot),
      100 * 2,
      reason: 'the meal that was eaten is untouched',
    );

    // A copy is a meal nobody has eaten, so it has nothing frozen: the
    // snapshot is taken when it is logged, from the food as it stands then.
    expect(copy.isPlanned, isTrue);
    expect(copy.isLogged, isFalse);
    expect(copy.macroSnapshot, isNull);
    expect(copy.servings, 2);

    // The copy is on a day nobody is looking at, so this is the only
    // evidence on screen that anything happened at all.
    expect(find.textContaining('Planned for breakfast on'), findsOneWidget);
  });
}

double kcal(String? snapshot) =>
    ((jsonDecode(snapshot!) as Map<String, Object?>)['kcal']! as num)
        .toDouble();

/// A [SelectedDate] the test puts where it needs it.
class _FixedDate extends SelectedDate {
  static DateTime date = dayKey(DateTime.now());

  @override
  DateTime build() => date;
}
