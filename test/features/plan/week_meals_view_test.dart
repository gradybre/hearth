import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';
import 'package:hearth/features/plan/week_meals_view.dart';
import 'package:hearth/features/plan/week_screen.dart';
import 'package:hearth/features/plan/week_view_preference.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

final DateTime _monday = DateTime(2026, 9, 28);

MealPlanEntry _entry(
  String id,
  String ref, {
  MealSlot slot = MealSlot.dinner,
}) => MealPlanEntry(
  id: id,
  dayId: 'day-$id',
  slot: slot,
  refType: PlanRefType.recipe,
  refId: ref,
  servings: 0.5,
);

List<Recipe> _recipes() => <Recipe>[
  for (int i = 0; i < 7; i++)
    aRecipe(
      id: 'r-$i',
      title: 'Dinner number ${i + 1}',
      servings: 6,
      steps: <RecipeStep>[aStep('Simmer gently for five minutes.')],
    ),
  aRecipe(id: 'breakfast', title: 'Morning oats'),
  aRecipe(id: 'lunch', title: 'Midday soup'),
];

Map<DateTime, List<MealPlanEntry>> _week() => <DateTime, List<MealPlanEntry>>{
  for (int i = 0; i < 7; i++)
    addDays(_monday, i): <MealPlanEntry>[
      // Input order is deliberately not dinner-first.
      if (i == 0) _entry('breakfast', 'breakfast', slot: MealSlot.breakfast),
      _entry('e-$i', 'r-$i'),
      if (i == 0) _entry('lunch', 'lunch', slot: MealSlot.lunch),
    ],
};

Future<HearthDatabase> _open(
  WidgetTester tester, {
  DateTime? selected,
  List<Recipe>? recipes,
  List<Food> foods = const <Food>[],
  List<MealPlanEntry> entries = const <MealPlanEntry>[],
  Map<DateTime, List<MealPlanEntry>>? week,
  Stream<List<Recipe>>? recipeStream,
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    launchTarget: LaunchTarget.today,
    selectedDate: selected ?? _monday,
    recipes: recipes ?? _recipes(),
    recipeStream: recipeStream,
    foods: foods,
    entries: entries,
    weekEntries: week ?? _week(),
    size: size,
    textScale: scale,
    brightness: brightness,
    viewPadding: size.width < 840
        ? const EdgeInsets.only(top: 24, bottom: 34)
        : const EdgeInsets.only(top: 24),
  );
  await SweepTools(tester).planView('Week');
  return db;
}

Future<void> _choose(WidgetTester tester, WeekContentView value) async {
  final SweepTools tools = SweepTools(tester);
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
  await tools.reach(find.byKey(ValueKey<String>('week-content-${value.name}')));
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WeekMealsView)));

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('Week starts with dinner names across seven dated cards', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(
      find.byKey(const ValueKey<String>('week-content-control')),
      findsOneWidget,
    );
    for (int i = 0; i < 7; i++) {
      await SweepTools(tester).bring(find.text('Dinner number ${i + 1}'));
      expect(find.text('Dinner number ${i + 1}').hitTestable(), findsOneWidget);
    }
    expect(find.text('Morning oats'), findsNothing);
    expect(find.text('Midday soup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other meal counts expand names and open their source', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(find.text('Breakfast 1'), findsOneWidget);
    expect(find.text('Lunch 1'), findsOneWidget);
    await SweepTools(tester).reach(_key('week-other-meals-2026-09-28'));
    final Finder dinner = find.text('Dinner number 1');
    final Finder breakfast = find.text('Morning oats');
    expect(
      tester.getTopLeft(dinner).dy,
      lessThan(tester.getTopLeft(breakfast).dy),
    );
    await SweepTools(tester).reach(breakfast);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    await tester.pageBack();
    await pumpFrames(tester);
    expect(find.text('Morning oats'), findsOneWidget);
    await SweepTools(tester).reach(_key('week-other-meals-2026-09-28'));
    expect(find.text('Morning oats'), findsNothing);
  });

  testWidgets(
    'opening and cooking use the full saved recipe without editing the plan',
    (WidgetTester tester) async {
      final Recipe recipe = _recipes().first;
      final MealPlanEntry entry = _entry('dinner', recipe.id);
      final HearthDatabase db = await _open(
        tester,
        recipes: <Recipe>[recipe],
        entries: <MealPlanEntry>[entry],
        week: <DateTime, List<MealPlanEntry>>{
          _monday: <MealPlanEntry>[entry],
        },
      );
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      await SweepTools(tester).reach(_key('week-meal-open-dinner'));
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await tester.pageBack();
      await pumpFrames(tester);
      expect(await db.select(db.mealPlanEntries).get(), before);
      await SweepTools(tester).reach(_key('week-meal-cook-dinner'));
      final CookAlongScreen cook = tester.widget<CookAlongScreen>(
        find.byType(CookAlongScreen),
      );
      expect(cook.recipe, same(recipe));
      expect(cook.recipe.servings, 6);
      expect(before.single.servings, 0.5);
      await SweepTools(tester).reach(find.byTooltip('Finish cooking'));
      expect(await db.select(db.mealPlanEntries).get(), before);
    },
  );

  testWidgets(
    'logged names stay frozen while food opens current facts and its selected serving',
    (WidgetTester tester) async {
      final Food food = aFood(
        'Current yoghurt',
        id: 'yoghurt',
        servingOptions: <ServingOption>[
          aServing(
            id: 'pot',
            label: 'one pot',
            amount: 150,
            unit: Units.gram,
            macros: const Macros(kcal: 150),
          ),
        ],
      );
      final MealPlanEntry entry =
          MealPlanEntry(
            id: 'yoghurt',
            dayId: 'day-yoghurt',
            slot: MealSlot.dinner,
            refType: PlanRefType.food,
            refId: food.id,
            servings: 2,
            servingOptionId: 'removed-pot',
          ).log(
            liveMacros: const Macros(kcal: 100),
            coverage: const NutrientCoverage.notRecorded(),
            at: _monday,
            label: 'Yoghurt as eaten',
          );
      final HearthDatabase db = await _open(
        tester,
        foods: <Food>[food],
        entries: <MealPlanEntry>[entry],
        week: <DateTime, List<MealPlanEntry>>{
          _monday: <MealPlanEntry>[entry],
        },
      );
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      expect(find.text('Yoghurt as eaten'), findsOneWidget);
      expect(
        find.textContaining('selected serving is no longer available'),
        findsOneWidget,
      );
      expect(_key('week-meal-cook-yoghurt'), findsNothing);
      await SweepTools(tester).reach(_key('week-meal-open-yoghurt'));
      final FoodDetailScreen detail = tester.widget<FoodDetailScreen>(
        find.byType(FoodDetailScreen),
      );
      expect(detail.foodId, food.id);
      expect(detail.servingOptionId, 'removed-pot');
      expect(find.text('Current yoghurt'), findsOneWidget);
      expect(
        find.textContaining('serving selected in your plan is no longer'),
        findsOneWidget,
      );
      await tester.pageBack();
      await pumpFrames(tester);
      expect(await db.select(db.mealPlanEntries).get(), before);
    },
  );

  testWidgets('restaurant, logged, and missing sources do not offer Cook', (
    WidgetTester tester,
  ) async {
    final Recipe restaurant = aRecipe(
      id: 'restaurant',
      title: 'Restaurant dinner',
      kind: RecipeKind.eatenOut,
    );
    final List<MealPlanEntry> entries = <MealPlanEntry>[
      _entry('restaurant', restaurant.id),
      _entry('logged', 'r-0').log(
        liveMacros: const Macros(kcal: 500),
        coverage: const NutrientCoverage.notRecorded(),
        at: _monday,
        label: 'Yesterday dinner',
      ),
      _entry('missing', 'removed'),
      const MealPlanEntry(
        id: 'missing-food',
        dayId: 'd',
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'gone',
        servings: 1,
      ),
    ];
    await _open(
      tester,
      recipes: <Recipe>[restaurant, ..._recipes()],
      week: <DateTime, List<MealPlanEntry>>{_monday: entries},
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('week-meal-cook-'),
      ),
      findsNothing,
    );
    expect(
      find.text('Recipe no longer available in the library.'),
      findsOneWidget,
    );
    expect(
      find.text('Food no longer available in the library.'),
      findsOneWidget,
    );
    expect(
      tester.widget<InkWell>(_key('week-meal-open-missing')).onTap,
      isNull,
    );
  });

  testWidgets('a held Cook callback checks the current recipe library', (
    WidgetTester tester,
  ) async {
    final StreamController<List<Recipe>> library =
        StreamController<List<Recipe>>();
    addTearDown(library.close);
    final Recipe recipe = _recipes().first;
    await _open(tester, recipeStream: library.stream);
    library.add(<Recipe>[recipe]);
    await pumpFrames(tester);
    final VoidCallback cook = tester
        .widget<TextButton>(_key('week-meal-cook-e-0'))
        .onPressed!;
    library.add(<Recipe>[]);
    await pumpFrames(tester);
    cook();
    await pumpFrames(tester);
    expect(find.byType(CookAlongScreen), findsNothing);
    expect(
      find.text('This recipe is no longer in your library.'),
      findsOneWidget,
    );
  });

  for (final MealSlot slot in <MealSlot>[MealSlot.dinner, MealSlot.lunch]) {
    testWidgets(
      'Add ${slot.name} keeps its card date through a later date change',
      (WidgetTester tester) async {
        final DateTime date = addDays(startOfWeek(DateTime.now()), 16);
        await _open(
          tester,
          selected: date,
          week: const <DateTime, List<MealPlanEntry>>{},
        );
        final ProviderContainer container = _container(tester);
        final String dateId =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (slot != MealSlot.dinner) {
          await SweepTools(tester).reach(_key('week-other-meals-$dateId'));
        }
        await SweepTools(tester).reach(_key('week-add-$dateId-${slot.name}'));
        container.read(selectedDateProvider.notifier).shiftDays(7);
        await pumpFrames(tester);
        await SweepTools(tester).reach(find.text('Dinner number 1').last);
        expect(find.text('Add to plan'), findsOneWidget);
        await SweepTools(tester).reach(find.text('Add to plan'));
        final List<MealPlanEntry> saved = await container
            .read(planRepositoryProvider)
            .entriesFor(date);
        expect(saved, hasLength(1));
        expect(saved.single.slot, slot);
        expect(saved.single.isLogged, isFalse);
        expect(saved.single.macroSnapshot, isNull);
        expect(
          await container
              .read(planRepositoryProvider)
              .entriesFor(addDays(date, 7)),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opening a day preserves the exact date across a year boundary', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      selected: DateTime(2027, 1, 1),
      week: const <DateTime, List<MealPlanEntry>>{},
    );
    final ProviderContainer container = _container(tester);
    final Finder date = _key('week-open-day-2026-12-31');
    await SweepTools(tester).reach(date);
    expect(container.read(selectedDateProvider), DateTime(2026, 12, 31));
    expect(container.read(planViewProvider), PlanView.day);
    expect(find.byTooltip('Previous day'), findsOneWidget);
    await SweepTools(tester).planView('Week');
    expect(find.byType(WeekMealsView), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open Thursday, December 31, 2026'),
      findsOneWidget,
    );
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'Meals shows its first short dinner name before scrolling at 3× ${brightness.name}',
      (WidgetTester tester) async {
        await _open(
          tester,
          recipes: <Recipe>[aRecipe(id: 'r-0', title: 'Stew')],
          size: const Size(320, 568),
          scale: 3,
          brightness: brightness,
        );
        final Rect viewport = tester.getRect(
          find
              .descendant(
                of: find.byType(WeekScreen),
                matching: find.byType(ListView),
              )
              .first,
        );
        final Rect name = tester.getRect(find.text('Stew'));
        expect(name.top, greaterThanOrEqualTo(viewport.top));
        expect(
          name.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason:
              'the first card should show the dinner itself, not only headings',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Nutrition keeps its first complete fact in the small 3× viewport ${brightness.name}',
      (WidgetTester tester) async {
        final MealPlanEntry entry = _entry('logged-first', 'r-0')
            .copyWith(servings: 1)
            .log(
              liveMacros: const Macros(kcal: 1840),
              coverage: const NutrientCoverage.notRecorded(),
              at: _monday,
              label: 'Monday dinner',
            );
        await _open(
          tester,
          size: const Size(320, 568),
          scale: 3,
          brightness: brightness,
          week: <DateTime, List<MealPlanEntry>>{
            _monday: <MealPlanEntry>[entry],
          },
        );
        await _choose(tester, WeekContentView.nutrition);
        final Rect viewport = tester.getRect(
          find
              .descendant(
                of: find.byType(WeekScreen),
                matching: find.byType(ListView),
              )
              .first,
        );
        final Rect fact = tester.getRect(find.text('1840 kcal'));
        final Rect day = tester.getRect(find.text('Mon 28'));
        expect(
          fact.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason:
              'the complete amount and unit must stay above the initial fold',
        );
        expect(day.top, greaterThanOrEqualTo(viewport.top));
        expect(day.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Meals and Nutrition controls and the last day are reachable at 320×568/3× ${brightness.name}',
      (WidgetTester tester) async {
        await _open(
          tester,
          size: const Size(320, 568),
          scale: 3,
          brightness: brightness,
        );
        final SweepTools tools = SweepTools(tester);
        final Finder selector = _key('week-content-control');
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
        expect(MediaQuery.textScalerOf(tester.element(selector)).scale(16), 48);
        await tools.reach(_key('week-other-meals-2026-10-04'));
        for (final String key in <String>[
          'week-add-2026-10-04-dinner',
          'week-add-2026-10-04-snack',
          'week-open-day-2026-10-04',
        ]) {
          final Finder control = _key(key);
          await tools.bring(control);
          expect(control.hitTestable(), findsOneWidget);
          expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
          expect(tester.getRect(control).left, greaterThanOrEqualTo(16));
          expect(tester.getRect(control).right, lessThanOrEqualTo(304));
        }
        await _choose(tester, WeekContentView.nutrition);
        expect(find.byType(WeekMealsView), findsNothing);
        await _choose(tester, WeekContentView.meals);
        expect(find.byType(WeekMealsView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Week selection survives Day navigation without changing the primary Day destination',
    (WidgetTester tester) async {
      await _open(tester);
      await _choose(tester, WeekContentView.nutrition);
      await SweepTools(tester).planView('Day');
      expect(find.byTooltip('Previous day'), findsOneWidget);
      await SweepTools(tester).planView('Week');
      expect(find.byType(WeekMealsView), findsNothing);
      expect(_key('week-content-nutrition'), findsOneWidget);
    },
  );

  testWidgets('keyboard reaches Open and Cook as separate actions', (
    WidgetTester tester,
  ) async {
    await _open(tester, size: const Size(1280, 800));
    Future<void> tabTo(Finder target) async {
      await SweepTools(tester).bring(target);
      bool focused() {
        final BuildContext? focus = FocusManager.instance.primaryFocus?.context;
        if (focus == null) return false;
        final Element element = tester.element(target);
        bool found = focus == element;
        (focus as Element).visitAncestorElements((Element ancestor) {
          found = found || ancestor == element;
          return !found;
        });
        return found;
      }

      for (int i = 0; i < 60 && !focused(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused(), isTrue);
    }

    await tabTo(_key('week-meal-open-e-0'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    await tester.pageBack();
    await pumpFrames(tester);
    await tabTo(_key('week-meal-cook-e-0'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);
    expect(find.byType(CookAlongScreen), findsOneWidget);
  });
}
