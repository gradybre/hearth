import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';
import 'package:hearth/features/recipes/scale_control.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Recipe dinnerRecipe({double servings = 4}) => aRecipe(
  id: 'recipe-dinner',
  title: 'White bean supper',
  servings: servings,
  ingredients: <RecipeIngredient>[
    anIngredient('white beans', amount: 2, unit: Units.can),
  ],
  steps: <RecipeStep>[aStep('Warm the white beans.')],
);

Future<HearthDatabase> openDinner(
  WidgetTester tester, {
  Recipe? recipe,
  List<Object> extraOverrides = const <Object>[],
}) async {
  final Recipe chosen = recipe ?? dinnerRecipe();
  final HearthDatabase db = await pumpHearthApp(
    tester,
    recipes: <Recipe>[chosen],
    extraOverrides: extraOverrides,
  );
  await pumpFrames(tester);
  await tester.tap(find.text(chosen.title));
  await pumpFrames(tester, frames: 12);
  return db;
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RecipeDetailScreen)));

Future<void> press(WidgetTester tester, String label) async {
  final Finder button = find.text(label).last;
  await tester.ensureVisible(button);
  await pumpFrames(tester);
  await tester.tap(button);
  await pumpFrames(tester, frames: 12);
}

void main() {
  for (final String stage in <String>['Undo', 'Retry']) {
    testWidgets('screen-reader $stage keeps the identity expiry explanation', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures.allOn;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      String userId = 'local-user';
      final RecordingPlans plans = RecordingPlans()
        ..failures = stage == 'Retry' ? 1 : 0;
      await openDinner(
        tester,
        extraOverrides: <Object>[
          currentUserIdProvider.overrideWith((Ref ref) => userId),
          planRepositoryProvider.overrideWithValue(plans),
        ],
      );
      final ProviderContainer container = containerOf(tester);
      await press(tester, 'Plan');
      await press(tester, 'Add to my plan');
      userId = 'different-user';
      container.invalidate(currentUserIdProvider);
      await pumpFrames(tester);
      await press(tester, stage);

      expect(plans.additions, hasLength(1));
      expect(plans.removed, isEmpty);
      expect(
        find.textContaining('account or household changed').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final String stage in <String>['review', 'Undo', 'Retry']) {
    testWidgets('Plan $stage expires when identity changes', (
      WidgetTester tester,
    ) async {
      String userId = 'local-user';
      final RecordingPlans plans = RecordingPlans()
        ..failures = stage == 'Retry' ? 1 : 0;
      await openDinner(
        tester,
        extraOverrides: <Object>[
          currentUserIdProvider.overrideWith((Ref ref) => userId),
          planRepositoryProvider.overrideWithValue(plans),
        ],
      );
      final ProviderContainer container = containerOf(tester);
      await press(tester, 'Plan');
      if (stage != 'review') await press(tester, 'Add to my plan');
      userId = 'different-user';
      container.invalidate(currentUserIdProvider);
      await pumpFrames(tester);
      await press(tester, stage == 'review' ? 'Add to my plan' : stage);
      expect(plans.additions, hasLength(stage == 'review' ? 0 : 1));
      expect(plans.removed, isEmpty);
      expect(
        find.textContaining('account or household changed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final String stage in <String>['review', 'Retry']) {
    testWidgets('Shop $stage expires when identity changes', (
      WidgetTester tester,
    ) async {
      String householdId = 'local-household';
      late FailingShopping shopping;
      await openDinner(
        tester,
        extraOverrides: <Object>[
          currentHouseholdIdProvider.overrideWith((Ref ref) => householdId),
          shoppingRepositoryProvider.overrideWith((Ref ref) {
            shopping = FailingShopping(ref.read(databaseProvider));
            return shopping;
          }),
        ],
      );
      final ProviderContainer container = containerOf(tester);
      await press(tester, 'Shop');
      if (stage == 'Retry') await press(tester, 'Add to the list');
      householdId = 'different-household';
      container.invalidate(currentHouseholdIdProvider);
      await pumpFrames(tester);
      await press(tester, stage == 'review' ? 'Add to the list' : 'Retry');
      expect(shopping.attempts, hasLength(stage == 'review' ? 0 : 1));
      expect(
        find.textContaining('account or household changed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recipe detail offers Cook, Plan and Shop', (
    WidgetTester tester,
  ) async {
    await openDinner(tester);
    expect(find.text('Cook'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('wholly unknown nutrition is not an exact zero', (
    WidgetTester tester,
  ) async {
    await openDinner(tester);
    expect(find.text('Nutrition not available yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('not matched to a food'), findsOneWidget);
  });

  testWidgets('Plan defaults to one personal serving, planned and private', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openDinner(tester);
    await press(tester, '2×');
    await press(tester, 'Plan');
    expect(find.text('My plan'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dinner'))
          .selected,
      isTrue,
    );
    expect(find.textContaining('Today'), findsOneWidget);
    await press(tester, 'Add to my plan');

    final PlanRepository plans = containerOf(tester)
        .read(planRepositoryProvider);
    final List<MealPlanEntry> entries = await plans.entriesFor(DateTime.now());
    expect(entries, hasLength(1));
    expect(entries.single.refType, PlanRefType.recipe);
    expect(entries.single.refId, 'recipe-dinner');
    expect(entries.single.slot, MealSlot.dinner);
    expect(entries.single.servings, 1);
    expect(entries.single.isLogged, isFalse);
    expect(entries.single.macroSnapshot, isNull);
    final List<MealPlanDayRow> days = await db.select(db.mealPlanDays).get();
    expect(days.single.userId, 'local-user');
  });

  testWidgets('Plan commits edited date, meal and unsubmitted portion', (
    WidgetTester tester,
  ) async {
    await openDinner(tester);
    await press(tester, 'Plan');
    await tester.tap(find.byKey(const ValueKey<String>('recipe-plan-date')));
    await pumpFrames(tester, frames: 12);
    final DateTime selected = dayKey(DateTime.now())
        .add(const Duration(days: 5));
    await tester.enterText(
      find.byKey(const ValueKey<String>('recipe-plan-date-input')),
      '${selected.month}/${selected.day}/${selected.year}',
    );
    await press(tester, 'Use date');
    await press(tester, 'Lunch');
    await tester.enterText(find.byType(TextField), '1 1/2');
    await press(tester, 'Add to my plan');
    final PlanRepository plans = containerOf(tester)
        .read(planRepositoryProvider);
    final List<MealPlanEntry> entries = await plans.entriesFor(selected);
    expect(entries.single.servings, 1.5);
    expect(entries.single.slot, MealSlot.lunch);
    expect(entries.single.isLogged, isFalse);
    expect(await plans.entriesFor(DateTime.now()), isEmpty);
  });

  testWidgets('cancelled Plan and Shop reviews write nothing', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openDinner(tester);
    await press(tester, 'Plan');
    await tester.enterText(find.byType(TextField), '2');
    await press(tester, 'Cancel');
    await press(tester, 'Shop');
    expect(find.text('Add ingredients'), findsOneWidget);
    await press(tester, 'Cancel');
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(await db.select(db.shoppingListItems).get(), isEmpty);
    expect(await db.select(db.pendingWrites).get(), isEmpty);
  });

  testWidgets('Undo removes only the exact new plan entry', (
    WidgetTester tester,
  ) async {
    await openDinner(tester);
    final PlanRepository plans = containerOf(tester)
        .read(planRepositoryProvider);
    final MealPlanEntry prior = await plans.add(
      date: DateTime.now(),
      slot: MealSlot.dinner,
      refType: PlanRefType.recipe,
      refId: 'recipe-dinner',
      servings: 2,
    );
    await press(tester, 'Plan');
    await press(tester, 'Add to my plan');
    expect((await plans.entriesFor(DateTime.now())).length, 2);
    await press(tester, 'Undo');
    final List<MealPlanEntry> entries = await plans.entriesFor(DateTime.now());
    expect(entries.single.id, prior.id);
    expect(entries.single.servings, 2);
  });

  testWidgets('Plan Undo still removes its entry after leaving recipe detail', (
    WidgetTester tester,
  ) async {
    await openDinner(tester);
    final PlanRepository plans = containerOf(tester)
        .read(planRepositoryProvider);
    await press(tester, 'Plan');
    await press(tester, 'Add to my plan');
    await tester.tap(find.byTooltip('Back'));
    await pumpFrames(tester, frames: 12);
    expect(find.byType(RecipeDetailScreen), findsNothing);
    await press(tester, 'Undo');
    expect(await plans.entriesFor(DateTime.now()), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan Retry still saves reviewed choices after leaving detail', (
    WidgetTester tester,
  ) async {
    final RecordingPlans plans = RecordingPlans()..failures = 1;
    await openDinner(
      tester,
      extraOverrides: [planRepositoryProvider.overrideWithValue(plans)],
    );
    await press(tester, 'Plan');
    await press(tester, 'Lunch');
    await tester.enterText(find.byType(TextField), '2.5');
    await press(tester, 'Add to my plan');
    await tester.tap(find.byTooltip('Back'));
    await pumpFrames(tester, frames: 12);
    await press(tester, 'Retry');
    expect(plans.additions, hasLength(2));
    expect(plans.additions.first, plans.additions.last);
    expect(find.textContaining('Added to My plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shop Retry still saves reviewed amount after leaving detail', (
    WidgetTester tester,
  ) async {
    late FailingShopping shopping;
    await openDinner(
      tester,
      extraOverrides: [
        shoppingRepositoryProvider.overrideWith((Ref ref) {
          shopping = FailingShopping(ref.read(databaseProvider));
          return shopping;
        }),
      ],
    );
    await press(tester, '2×');
    await press(tester, 'Shop');
    await press(tester, 'Add to the list');
    await tester.tap(find.byTooltip('Back'));
    await pumpFrames(tester, frames: 12);
    await press(tester, 'Retry');
    expect(shopping.attempts, hasLength(2));
    expect(shopping.attempts.last.servings, 8);
    expect(
      (await shopping.current())!.lines.single.planned.single.canonicalAmount,
      4,
    );
    expect(find.text('View list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeat taps cannot open or save two plans', (
    WidgetTester tester,
  ) async {
    final RecordingPlans plans = RecordingPlans()..waiting = Completer<void>();
    await openDinner(
      tester,
      extraOverrides: [planRepositoryProvider.overrideWithValue(plans)],
    );
    await tester.tap(find.text('Plan'));
    await tester.tap(find.text('Plan'), warnIfMissed: false);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.ensureVisible(find.text('Add to my plan'));
    await tester.tap(find.text('Add to my plan'));
    await tester.tap(find.text('Add to my plan'), warnIfMissed: false);
    await pumpFrames(tester, frames: 12);
    expect(plans.additions, hasLength(1));
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Plan'))
          .onPressed,
      isNull,
    );
    plans.waiting!.complete();
    await pumpFrames(tester, frames: 12);
    expect(find.textContaining('Added to My plan'), findsOneWidget);
  });

  testWidgets(
    'plan Retry keeps reviewed portion and destination without logging',
    (WidgetTester tester) async {
      final RecordingPlans plans = RecordingPlans()..failures = 1;
      await openDinner(
        tester,
        extraOverrides: [planRepositoryProvider.overrideWithValue(plans)],
      );
      await press(tester, 'Plan');
      await press(tester, 'Breakfast');
      await tester.enterText(find.byType(TextField), '2.25');
      await press(tester, 'Add to my plan');
      expect(
        find.textContaining('Your choices are kept for retry'),
        findsOneWidget,
      );
      await press(tester, 'Retry');
      expect(plans.additions, hasLength(2));
      expect(plans.additions.last, plans.additions.first);
      expect(plans.additions.last.servings, 2.25);
      expect(plans.additions.last.slot, MealSlot.breakfast);
      expect(plans.additions.last.loggedMacros, isNull);
      expect(find.textContaining('Added to My plan'), findsOneWidget);
    },
  );

  testWidgets(
    'Shop seeds the scaled yield and keeps previous additions additive',
    (WidgetTester tester) async {
      await openDinner(tester);
      final container = containerOf(tester);
      final shopping = container.read(shoppingRepositoryProvider);
      await shopping.addRecipe(
        recipe: dinnerRecipe(),
        servings: 4,
        foods: const <String, Food>{},
      );
      await press(tester, '2×');
      await press(tester, 'Shop');
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('8 servings'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await press(tester, 'Add to the list');
      final lines = (await shopping.current())!.lines;
      expect(lines.single.planned.single.canonicalAmount, 6);
      expect(lines.single.contributions.single.servings, 12);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('View list'), findsOneWidget);
      await press(tester, 'View list');
      expect(find.byType(RecipeDetailScreen), findsNothing);
      expect(find.text('white beans'), findsOneWidget);
    },
  );

  testWidgets(
    'repeated Shop confirmation saves once and keeps the recipe open',
    (WidgetTester tester) async {
      await openDinner(tester);
      final shopping = containerOf(tester).read(shoppingRepositoryProvider);
      await press(tester, 'Shop');
      await tester.ensureVisible(find.text('Add to the list'));
      await tester.tap(find.text('Add to the list'));
      await tester.tap(find.text('Add to the list'), warnIfMissed: false);
      await pumpFrames(tester, frames: 20);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(
        (await shopping.current())!.lines.single.contributions.single.servings,
        4,
      );
      expect(find.text('View list'), findsOneWidget);
    },
  );

  testWidgets(
    'shopping Retry retains the original recipe and reviewed scaled yield',
    (WidgetTester tester) async {
      late FailingShopping shopping;
      await openDinner(
        tester,
        extraOverrides: [
          shoppingRepositoryProvider.overrideWith((Ref ref) {
            shopping = FailingShopping(ref.read(databaseProvider));
            return shopping;
          }),
        ],
      );
      await press(tester, '2×');
      await press(tester, 'Shop');
      await tester.tap(find.byTooltip('More'));
      await pumpFrames(tester);
      await press(tester, 'Add to the list');
      expect(
        find.textContaining('Your amount is kept for retry'),
        findsOneWidget,
      );
      expect(await shopping.current(), isNull);
      await press(tester, 'Retry');
      expect(shopping.attempts, hasLength(2));
      expect(
        identical(
          shopping.attempts.first.recipe,
          shopping.attempts.last.recipe,
        ),
        isTrue,
      );
      expect(shopping.attempts.last.recipe.servings, 4);
      expect(shopping.attempts.last.servings, 8.5);
      expect(
        (await shopping.current())!.lines.single.planned.single.canonicalAmount,
        4.25,
      );
      expect(find.text('View list'), findsOneWidget);
    },
  );

  testWidgets('an eaten-out recipe can only be planned and stays uneaten', (
    WidgetTester tester,
  ) async {
    final Recipe restaurant = aRecipe(
      id: 'restaurant',
      title: 'Restaurant bowl',
      servings: 1,
      kind: RecipeKind.eatenOut,
      ingredients: <RecipeIngredient>[
        anIngredient('rice', amount: 1, unit: Units.cup),
      ],
      steps: <RecipeStep>[aStep('A note, not cooking directions.')],
    );
    await openDinner(tester, recipe: restaurant);
    expect(find.text('Cook'), findsNothing);
    expect(find.text('Shop'), findsNothing);
    expect(find.byType(ScaleControl), findsNothing);
    await press(tester, 'Plan');
    await press(tester, 'Add to my plan');
    final entries = await containerOf(tester)
        .read(planRepositoryProvider)
        .entriesFor(DateTime.now());
    expect(entries.single.refId, restaurant.id);
    expect(entries.single.servings, 1);
    expect(entries.single.isLogged, isFalse);
  });

  for (final Recipe recipe in <Recipe>[
    dinnerRecipe(servings: 0),
    aRecipe(id: 'empty', title: 'Empty recipe'),
    aRecipe(
      id: 'optional',
      title: 'Optional recipe',
      ingredients: <RecipeIngredient>[
        anIngredient('parsley', amount: 1, unit: Units.tbsp, optional: true),
      ],
    ),
  ]) {
    testWidgets(
      'Shop explains why ${recipe.title} cannot contribute at yield ${recipe.servings}',
      (WidgetTester tester) async {
        final HearthDatabase db = await openDinner(tester, recipe: recipe);
        await press(tester, 'Shop');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add to the list'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining(
            recipe.servings <= 0
                ? 'positive recipe yield'
                : 'no ingredients to add',
          ),
          findsOneWidget,
        );
        expect(await db.select(db.shoppingListItems).get(), isEmpty);
      },
    );
  }
}

typedef PlannedAddition = ({
  DateTime date,
  MealSlot slot,
  PlanRefType refType,
  String refId,
  double servings,
  Macros? loggedMacros,
});

class RecordingPlans extends Mock implements PlanRepository {
  final List<PlannedAddition> additions = <PlannedAddition>[];
  final List<String> removed = <String>[];
  int failures = 0;
  Completer<void>? waiting;

  @override
  Future<MealPlanEntry> add({
    required DateTime date,
    required MealSlot slot,
    required PlanRefType refType,
    required String refId,
    required double servings,
    String? servingOptionId,
    Macros? loggedMacros,
    NutrientCoverage? loggedCoverage,
    LoggedPortion? loggedPortion,
    bool usesApproximatePackage = false,
    String? label,
  }) async {
    additions.add((
      date: date,
      slot: slot,
      refType: refType,
      refId: refId,
      servings: servings,
      loggedMacros: loggedMacros,
    ));
    if (failures > 0) {
      failures--;
      throw StateError('save failed');
    }
    await waiting?.future;
    return MealPlanEntry(
      id: 'entry-${additions.length}',
      dayId: 'day',
      slot: slot,
      refType: refType,
      refId: refId,
      servings: servings,
    );
  }

  @override
  Future<void> removeEntry(String entryId) async {
    removed.add(entryId);
  }
}

class FailingShopping extends ShoppingRepository {
  FailingShopping(HearthDatabase db)
    : super(
        database: db,
        store: ShoppingStore(db),
        queue: PendingWriteStore(db),
        householdId: 'local-household',
      );

  final List<({Recipe recipe, double servings})> attempts =
      <({Recipe recipe, double servings})>[];

  @override
  Future<List<ShoppingLine>> addRecipe({
    required Recipe recipe,
    required double servings,
    required Map<String, Food> foods,
  }) async {
    attempts.add((recipe: recipe, servings: servings));
    if (attempts.length == 1) throw StateError('Save failed');
    return super.addRecipe(recipe: recipe, servings: servings, foods: foods);
  }
}
