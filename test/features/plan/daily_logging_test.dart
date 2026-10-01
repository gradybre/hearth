import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

const Macros _breakfast = Macros(
  kcal: 400,
  proteinG: 20,
  carbG: 50,
  fatG: 12,
  fiberG: 4,
);
Food _oats() => aFood(
  'Oats',
  id: 'oats',
  servingOptions: <ServingOption>[
    aServing(amount: 100, unit: Units.gram, macros: _breakfast),
  ],
);
MealPlanEntry _entry({bool logged = false}) {
  const MealPlanEntry entry = MealPlanEntry(
    id: 'entry-oats',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'oats',
    servings: 1,
  );
  return logged
      ? entry.log(
          liveMacros: _breakfast,
          at: DateTime.utc(2026, 9, 1),
          label: 'Oats',
          coverage: NutrientCoverage.ofOne(_breakfast),
        )
      : entry;
}

Future<void> _day(WidgetTester tester) async {
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester, frames: 12);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is Scrollable &&
                (widget.axisDirection == AxisDirection.down ||
                    widget.axisDirection == AxisDirection.up),
          )
          .last,
      maxScrolls: 50,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
  await pumpFrames(tester);
  await tester.tap(finder.hitTestable());
  await pumpFrames(tester, frames: 12);
}

void main() {
  for (final int offset in <int>[-1, 0, 1]) {
    testWidgets(
      'recent repeat on day $offset keeps its amount and destination',
      (WidgetTester tester) async {
        final HearthDatabase db = await pumpHearthApp(
          tester,
          selectedDate: addDays(dayKey(DateTime.now()), offset),
          foods: <Food>[_oats()],
          recentLogs: <RecentLog>[
            RecentLog(
              refType: PlanRefType.food,
              refId: 'oats',
              label: 'Oats',
              servings: 2,
              lastLoggedAt: DateTime(2026, 9, 1),
              timesLogged: 4,
              mealSlot: MealSlot.breakfast,
            ),
          ],
        );
        await _day(tester);
        await _tap(tester, find.byTooltip('Add to breakfast'));
        // One tap after opening the picker; the pencil is an independent path.
        await _tap(
          tester,
          find.textContaining(
            offset > 0 ? 'add to plan · 2 ×' : 'log again · 2 ×',
          ),
        );
        final MealPlanEntryRow row =
            (await db.select(db.mealPlanEntries).get()).single;
        expect(row.servings, 2);
        expect(row.isLogged, offset <= 0);
        expect(row.macroSnapshot == null, offset > 0);
        final MealPlanDayRow day =
            (await db.select(db.mealPlanDays).get()).single;
        expect(day.day, addDays(dayKey(DateTime.now()), offset));
      },
    );
  }

  testWidgets(
    'favorites precede recents and scope chips narrow search without another step',
    (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        foods: <Food>[_oats()],
        recipes: <Recipe>[aRecipe(title: 'Oat pancakes', id: 'pancakes')],
        favorites: <String>{'pancakes'},
        recentLogs: <RecentLog>[
          RecentLog(
            refType: PlanRefType.food,
            refId: 'oats',
            label: 'Oats',
            servings: 1,
            lastLoggedAt: DateTime(2026, 9, 1),
            timesLogged: 2,
          ),
        ],
      );
      await _day(tester);
      await _tap(tester, find.byTooltip('Add to breakfast'));
      expect(
        tester.getTopLeft(find.text('Favorites')).dy,
        lessThan(tester.getTopLeft(find.text('Breakfast first')).dy),
      );
      await tester.enterText(find.byType(TextField).last, 'oat');
      await pumpFrames(tester);
      expect(find.text('Oat pancakes'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Foods'));
      expect(find.text('Oat pancakes'), findsNothing);
      expect(find.text('Oats'), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Recipes'));
      expect(find.text('Oat pancakes'), findsOneWidget);
      expect(find.text('Oats'), findsNothing);
      expect(find.text('Elsewhere'), findsNothing);
    },
  );

  testWidgets(
    'All recents switches from meal-first ranking to chronological order',
    (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        foods: <Food>[
          _oats(),
          aFood('Salad', id: 'salad'),
        ],
        recentLogs: <RecentLog>[
          RecentLog(
            refType: PlanRefType.food,
            refId: 'salad',
            label: 'Salad',
            servings: 1,
            lastLoggedAt: DateTime(2026, 9, 2),
            timesLogged: 1,
            mealSlot: MealSlot.lunch,
          ),
          RecentLog(
            refType: PlanRefType.food,
            refId: 'oats',
            label: 'Oats',
            servings: 1,
            lastLoggedAt: DateTime(2026, 9, 1),
            timesLogged: 1,
            mealSlot: MealSlot.breakfast,
          ),
        ],
      );
      await _day(tester);
      await _tap(tester, find.byTooltip('Add to breakfast'));
      expect(
        tester.getTopLeft(find.text('Oats').first).dy,
        lessThan(tester.getTopLeft(find.text('Salad').first).dy),
      );
      await _tap(tester, find.text('All recents'));
      expect(
        tester.getTopLeft(find.text('Salad').first).dy,
        lessThan(tester.getTopLeft(find.text('Oats').first).dy),
      );
    },
  );

  testWidgets(
    'reviewing a recent portion opens its remembered amount without logging',
    (WidgetTester tester) async {
      final HearthDatabase db = await pumpHearthApp(
        tester,
        foods: <Food>[_oats()],
        recentLogs: <RecentLog>[
          RecentLog(
            refType: PlanRefType.food,
            refId: 'oats',
            label: 'Oats',
            servings: 2.5,
            lastLoggedAt: DateTime(2026, 9, 1),
            timesLogged: 1,
          ),
        ],
      );
      await _day(tester);
      await _tap(tester, find.byTooltip('Add to breakfast'));
      await _tap(tester, find.byTooltip('Review Oats portion'));
      expect(find.widgetWithText(TextField, '2 1/2'), findsOneWidget);
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      await _tap(tester, find.text('Log it'));
      expect((await db.select(db.mealPlanEntries).get()).single.servings, 2.5);
    },
  );

  testWidgets('zero macro goals show totals without a zero-budget judgment', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[_entry(logged: true)],
      targets: const MacroTargets(kcal: 0, proteinG: 50, carbG: 0, fatG: 0),
    );
    await _day(tester);
    expect(find.text('Protein 20/50g'), findsOneWidget);
    expect(find.text('Carbs 50g'), findsOneWidget);
    expect(find.text('Fat 12g'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
    expect(find.textContaining('over'), findsNothing);
    // A configured target set still gets the specified minor Daily Values.
    expect(find.text('Fibre 4/28g'), findsOneWidget);
    await _tap(tester, find.text('Details'));
    expect(find.text('of 0'), findsNothing);
    expect(find.text('of 50'), findsOneWidget);
  });

  for (final double scale in <double>[2, 3]) {
    testWidgets(
      'no-target details and picker actions remain reachable at ${scale}x',
      (WidgetTester tester) async {
        await pumpHearthApp(
          tester,
          size: const Size(320, 844),
          textScale: scale,
          foods: <Food>[_oats()],
          entries: <MealPlanEntry>[_entry(logged: true)],
        );
        await _day(tester);
        await _tap(tester, find.text('Details'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Less'));
        await _tap(tester, find.byTooltip('Add to breakfast'));
        await _tap(tester, find.widgetWithText(ChoiceChip, 'Foods'));
        await _tap(
          tester,
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text('Oats'),
          ),
        );
        await _tap(tester, find.text('Log it'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a changed planned meal keeps the typed portion for review', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[_entry()],
    );
    await _day(tester);
    await _tap(tester, find.byTooltip('Edit Oats'));
    await _tap(tester, find.text('Edit portion'));
    await _tap(tester, find.byTooltip('Larger portion'));
    // Simulates an incoming log while the planned editor is open.
    await PlanStore(db)
        .upsertEntry(_entry(logged: true), updatedAt: DateTime.now());
    await _tap(tester, find.text('Save planned portion'));
    expect(find.widgetWithText(TextField, '1 1/4'), findsOneWidget);
    expect(find.textContaining('logged or removed while'), findsOneWidget);
    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(row.servings, 1);
    expect(row.isLogged, isTrue);
  });

  testWidgets('empty and logged-zero days do not make the same claim', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[
        _entry().log(
          liveMacros: Macros.zero,
          at: DateTime(2026, 9, 1),
          label: 'Oats',
          coverage: const NutrientCoverage.notRecorded(),
        ),
      ],
    );
    await _day(tester);
    expect(find.text('Nothing logged yet'), findsNothing);
    expect(find.text('0 kcal'), findsNWidgets(2));
  });

  testWidgets('no-target partial totals stay qualified in both views', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[
        _entry(logged: true),
        const MealPlanEntry(
          id: 'unknown',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'oats',
          servings: 1,
        ).log(
          liveMacros: const Macros(kcal: 100),
          at: DateTime(2026, 9, 2),
          label: 'Oats',
          coverage: const NutrientCoverage.notRecorded(),
        ),
      ],
    );
    await _day(tester);
    expect(find.text('Fibre ≥4g'), findsOneWidget);
    await _tap(tester, find.text('Details'));
    expect(find.textContaining('1 of 2 did not say'), findsOneWidget);
    expect(find.textContaining('tracked how complete it was'), findsWidgets);
    expect(find.textContaining('of 28'), findsNothing);
  });

  testWidgets('consumed totals remain visible without targets', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[_entry(logged: true)],
    );
    await _day(tester);
    expect(find.text('400 kcal'), findsNWidgets(3));
    expect(find.text('Protein 20g'), findsOneWidget);
    expect(find.text('Fibre 4g'), findsOneWidget);
    expect(find.text('Sodium —'), findsOneWidget);
    expect(find.text('Set targets'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
    await _tap(tester, find.text('Details'));
    expect(find.text('of 0'), findsNothing);
    expect(find.text('4 g'), findsOneWidget);
  });
  testWidgets('tomorrow defaults to a plan without a snapshot', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      selectedDate: addDays(dayKey(DateTime.now()), 1),
    );
    await _day(tester);
    await _tap(tester, find.byTooltip('Add to breakfast'));
    await _tap(tester, find.text('Oats'));
    expect(find.widgetWithText(FilledButton, 'Add to plan'), findsOneWidget);
    expect(find.text('Log as eaten · Breakfast · Tomorrow'), findsOneWidget);
    await _tap(tester, find.text('Add to plan'));
    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(row.isLogged, isFalse);
    expect(row.servings, 1);
    expect(row.macroSnapshot, isNull);
  });
  testWidgets('future meals can still be explicitly logged as eaten', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      selectedDate: addDays(dayKey(DateTime.now()), 1),
    );
    await _day(tester);
    await _tap(tester, find.byTooltip('Add to breakfast'));
    await _tap(tester, find.text('Oats'));
    await _tap(tester, find.text('Log as eaten · Breakfast · Tomorrow'));
    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(row.isLogged, isTrue);
    expect(row.macroSnapshot, isNotNull);
  });

  testWidgets('editing a planned portion leaves it planned', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[_oats()],
      entries: <MealPlanEntry>[_entry()],
    );
    await _day(tester);
    await _tap(tester, find.byTooltip('Edit Oats'));
    await _tap(tester, find.text('Edit portion'));
    await _tap(tester, find.byTooltip('Larger portion'));
    expect(
      find.widgetWithText(FilledButton, 'Save planned portion'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Save planned portion'));
    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    expect(row.isLogged, isFalse);
    expect(row.servings, 1.25);
    expect(row.macroSnapshot, isNull);
  });
}
