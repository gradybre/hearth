import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/local/cook_session_store.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../../support/fake_kitchen.dart';
import '../../support/fixtures.dart';

Recipe checklistRecipe() => aRecipe(
  title: 'Garlic bread',
  ingredients: <RecipeIngredient>[
    anIngredient('olive oil', id: 'oil', amount: 2, unit: Units.tbsp),
    anIngredient('garlic', id: 'garlic', amount: 3, unit: Units.item),
  ],
  steps: <RecipeStep>[
    aStep('Warm the oven.', stepNumber: 1, timerSeconds: 600),
    aStep('Bake until golden.', stepNumber: 2),
  ],
);

Future<FakeTimerAlerts> pumpChecklist(
  WidgetTester tester, {
  Recipe? recipe,
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<CookTimer> timers = const <CookTimer>[],
  CookSessionStore? sessions,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final FakeTimerAlerts alerts = FakeTimerAlerts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
        timerAlertsProvider.overrideWithValue(alerts),
        cookTimersProvider.overrideWith(() => FakeCookTimers(timers)),
        cookSessionStoreProvider.overrideWithValue(
          sessions ?? FakeCookSessionStore(),
        ),
        cookShowAllStepsProvider.overrideWith(() => FakeCookStepView()),
        foodLibraryProvider.overrideWith(
          (ref) => Stream<List<Food>>.value(const <Food>[]),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? HearthTheme.dark()
            : HearthTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CookAlongScreen(recipe: recipe ?? checklistRecipe()),
      ),
    ),
  );
  await tester.pump();
  return alerts;
}

Future<void> openIngredients(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ingredients'));
  await tester.pumpAndSettle();
}

Finder ingredientRow(String id) =>
    find.byKey(ValueKey<String>('cook-ingredient-$id'));

bool isChecked(WidgetTester tester, String id) =>
    tester
        .getSemantics(ingredientRow(id))
        .getSemanticsData()
        .flagsCollection
        .isChecked ==
    CheckedState.isTrue;

/// The first read has captured an old row but has not delivered it yet.
/// Later reads observe writes normally, as reopening cook mode would.
class DelayedCookSessionStore extends FakeCookSessionStore {
  DelayedCookSessionStore(super.saved);

  final Completer<StoredCookProgress?> restored =
      Completer<StoredCookProgress?>();
  bool _firstRead = true;
  int reads = 0;

  @override
  Future<StoredCookProgress?> read(String recipeId, {required DateTime now}) {
    reads++;
    if (_firstRead) {
      _firstRead = false;
      return restored.future;
    }
    return super.read(recipeId, now: now);
  }
}

class DelayedReadAndSaveCookSessionStore extends DelayedCookSessionStore {
  DelayedReadAndSaveCookSessionStore(super.saved);

  final Completer<void> firstSave = Completer<void>();
  int saveCalls = 0;

  @override
  Future<void> save({
    required String recipeId,
    required int currentStep,
    required Set<String> checkedStepIds,
    required DateTime now,
    Set<String> checkedIngredientIds = const <String>{},
  }) async {
    if (saveCalls++ == 0) await firstSave.future;
    await super.save(
      recipeId: recipeId,
      currentStep: currentStep,
      checkedStepIds: checkedStepIds,
      checkedIngredientIds: checkedIngredientIds,
      now: now,
    );
  }
}

class FailingClearCookSessionStore extends FakeCookSessionStore {
  FailingClearCookSessionStore(super.saved);

  int clearCalls = 0;

  @override
  Future<void> clear(String recipeId) async {
    if (clearCalls++ == 0) throw StateError('test cook clear failure');
    await super.clear(recipeId);
  }
}

class FailingCookSessionStore extends FakeCookSessionStore {
  FailingCookSessionStore(super.saved, {this.failures = 1, this.retryResult});

  final int failures;
  final Completer<StoredCookProgress?>? retryResult;
  int reads = 0;

  @override
  Future<StoredCookProgress?> read(
    String recipeId, {
    required DateTime now,
  }) async {
    reads++;
    if (reads <= failures) throw StateError('test cook progress read failure');
    if (reads == failures + 1 && retryResult != null) {
      return retryResult!.future;
    }
    return super.read(recipeId, now: now);
  }
}

Finder checklistRetry() => find.descendant(
  of: find.byKey(const ValueKey<String>('cook-ingredient-checklist')),
  matching: find.text('Retry saved progress'),
);

Future<void> closeIngredients(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Back to cooking'));
  await tester.tap(find.text('Back to cooking'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tap marks an ingredient and tap again undoes it', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpChecklist(tester);
    await openIngredients(tester);

    // This is intentionally a real tap on the ingredient text: the old
    // ingredient sheet displayed the row, but the tap did nothing.
    await tester.tap(find.text('olive oil'));
    await tester.pump();

    expect(find.text('Prepared / added'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('1 of 2 checked'), findsOneWidget);
    expect(find.text('olive oil'), findsOneWidget);
    expect(find.text('2 tbsp'), findsOneWidget);
    expect(isChecked(tester, 'oil'), isTrue);
    expect(isChecked(tester, 'garlic'), isFalse);
    expect(
      tester.widget<Text>(find.text('2 tbsp')).style?.decoration,
      isNot(TextDecoration.lineThrough),
    );

    await tester.tap(find.text('olive oil'));
    await tester.pump();
    expect(find.text('Prepared / added'), findsNothing);
    expect(find.text('0 of 2 checked'), findsOneWidget);
    expect(isChecked(tester, 'oil'), isFalse);
    semantics.dispose();
  });

  testWidgets('check state remains when the ingredient sheet is reopened', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpChecklist(tester);
    await openIngredients(tester);
    await tester.tap(find.text('olive oil'));
    await tester.pump();
    await tester.ensureVisible(find.text('Back to cooking'));
    await tester.tap(find.text('Back to cooking'));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 2'), findsOneWidget);
    await openIngredients(tester);
    expect(isChecked(tester, 'oil'), isTrue);
    expect(find.text('1 of 2 checked'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('matching foods in different sections have independent checks', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final Recipe recipe = aRecipe(
      sections: <RecipeSection>[
        aSection(
          id: 'sauce',
          name: 'Sauce',
          ingredients: <RecipeIngredient>[
            anIngredient(
              'olive oil',
              id: 'sauce-oil',
              sectionId: 'sauce',
              foodId: 'same-food',
              amount: 1,
              unit: Units.tbsp,
            ),
          ],
          steps: <RecipeStep>[aStep('Mix.', sectionId: 'sauce')],
        ),
        aSection(
          id: 'bread',
          name: 'Bread',
          sortOrder: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'olive oil',
              id: 'bread-oil',
              sectionId: 'bread',
              foodId: 'same-food',
              amount: 2,
              unit: Units.tbsp,
            ),
          ],
        ),
      ],
    );
    await pumpChecklist(tester, recipe: recipe);
    await openIngredients(tester);
    expect(find.text('Sauce'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);

    await tester.tap(ingredientRow('sauce-oil'));
    await tester.pump();
    expect(isChecked(tester, 'sauce-oil'), isTrue);
    expect(isChecked(tester, 'bread-oil'), isFalse);
    expect(find.text('1 tbsp'), findsOneWidget);
    expect(find.text('2 tbsp'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Reset ingredients keeps the directions and timer running', (
    WidgetTester tester,
  ) async {
    final FakeTimerAlerts alerts = await pumpChecklist(tester);
    await tester.tap(find.text('Start 10 min timer'));
    await tester.pump();
    await tester.tap(find.text('Mark done'));
    await tester.pump();
    expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
    await openIngredients(tester);
    await tester.tap(find.text('olive oil'));
    await tester.pump();
    await tester.tap(find.text('garlic'));
    await tester.pump();
    await tester.ensureVisible(find.text('Reset ingredients'));
    await tester.tap(find.text('Reset ingredients'));
    await tester.pump();

    expect(find.text('0 of 2 checked'), findsOneWidget);
    expect(find.text('Prepared / added'), findsNothing);
    expect(alerts.cancelAlls, 0);
    expect(alerts.cancelled, isEmpty);

    await tester.ensureVisible(find.text('Back to cooking'));
    await tester.tap(find.text('Back to cooking'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
    expect(find.byTooltip('Pause timer'), findsOneWidget);
  });

  testWidgets('rows announce quantity and check state with a kitchen target', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpChecklist(tester);
    await openIngredients(tester);
    final SemanticsNode row = tester.getSemantics(ingredientRow('oil'));
    expect(row.label, contains('2 tbsp olive oil'));
    expect(
      row.getSemanticsData().flagsCollection.isChecked,
      CheckedState.isFalse,
    );
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester.getSize(ingredientRow('oil')).height,
      greaterThanOrEqualTo(HearthTouch.kitchenTarget),
    );
    semantics.dispose();
  });

  testWidgets('Start over is available for ingredient-only progress', (
    WidgetTester tester,
  ) async {
    await pumpChecklist(tester);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.restart_alt),
          )
          .onPressed,
      isNull,
    );
    await openIngredients(tester);
    await tester.tap(find.text('olive oil'));
    await tester.pump();
    await tester.ensureVisible(find.text('Back to cooking'));
    await tester.tap(find.text('Back to cooking'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Start over'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
    await tester.pumpAndSettle();
    await openIngredients(tester);
    expect(find.text('0 of 2 checked'), findsOneWidget);
    expect(find.text('Prepared / added'), findsNothing);
  });

  testWidgets('an empty ingredient list explains itself without a reset', (
    WidgetTester tester,
  ) async {
    await pumpChecklist(tester, recipe: aRecipe());
    await openIngredients(tester);
    expect(find.text('This recipe has no ingredients listed.'), findsOneWidget);
    expect(find.text('Reset ingredients'), findsNothing);
    await tester.tap(find.text('Back to cooking'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ingredients'), findsOneWidget);
  });

  group('saved checklist', () {
    testWidgets('reopening cook mode restores ingredient checks', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final FakeCookSessionStore sessions = FakeCookSessionStore();
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(find.text('Prepared / added'), findsOneWidget);
    });

    testWidgets('restored checks for removed ingredients are dropped', (
      WidgetTester tester,
    ) async {
      final FakeCookSessionStore sessions = FakeCookSessionStore(
        const StoredCookProgress(
          currentStep: 0,
          checkedStepIds: <String>{},
          checkedIngredientIds: <String>{'oil', 'removed'},
        ),
      );
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      expect(find.text('1 of 2 checked'), findsOneWidget);
      await tester.tap(find.text('garlic'));
      await tester.pump();
      final StoredCookProgress saved = (await sessions.read(
        'unused-by-fake',
        now: DateTime.now(),
      ))!;
      expect(saved.checkedIngredientIds, <String>{'oil', 'garlic'});
    });
  });

  group('late restoration', () {
    const StoredCookProgress saved = StoredCookProgress(
      currentStep: 0,
      checkedStepIds: <String>{},
      checkedIngredientIds: <String>{'garlic'},
    );

    testWidgets('an already-open checklist reflects the restored state', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      expect(find.text('0 of 2 checked'), findsOneWidget);

      sessions.restored.complete(saved);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(find.text('Prepared / added'), findsOneWidget);
    });

    testWidgets('fresh taps and untouched saved checks are both retained', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();

      sessions.restored.complete(saved);
      await tester.pump();
      await closeIngredients(tester);
      await openIngredients(tester);
      expect(find.text('2 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
    });

    testWidgets('reset ingredients cannot resurrect saved checks', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final StoredCookProgress savedWithStep = StoredCookProgress(
        currentStep: 1,
        checkedStepIds: <String>{recipe.allSteps.first.id},
        checkedIngredientIds: saved.checkedIngredientIds,
      );
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(
        savedWithStep,
      );
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.ensureVisible(find.text('Reset ingredients'));
      await tester.tap(find.text('Reset ingredients'));
      await tester.pump();

      sessions.restored.complete(savedWithStep);
      await tester.pump();
      await closeIngredients(tester);
      expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
      await openIngredients(tester);
      expect(find.text('0 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        isEmpty,
      );
    });

    testWidgets('checking after reset retains only the fresh ingredient', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.ensureVisible(find.text('Reset ingredients'));
      await tester.tap(find.text('Reset ingredients'));
      await tester.pump();
      await tester.ensureVisible(find.text('olive oil'));
      await tester.tap(find.text('olive oil'));
      await tester.pump();

      sessions.restored.complete(saved);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil'},
      );
    });

    testWidgets('fresh direction progress keeps untouched saved ingredients', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await tester.tap(find.text('Mark done'));
      await tester.pump();

      sessions.restored.complete(saved);
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
      await openIngredients(tester);
      expect(find.text('1 of 2 checked'), findsOneWidget);
      final StoredCookProgress restored = (await sessions.read(
        recipe.id,
        now: DateTime.now(),
      ))!;
      expect(restored.checkedStepIds, <String>{recipe.allSteps.first.id});
      expect(restored.currentStep, 1);
      expect(restored.checkedIngredientIds, <String>{'garlic'});
    });

    testWidgets('a delayed empty read still saves new progress', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(null);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();

      sessions.restored.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil'},
      );
    });

    testWidgets('leaving during restoration still saves the fresh check', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      sessions.restored.complete(saved);
      await tester.pump();
      expect(
        (await sessions.read(
          recipe.id,
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second tap before restore keeps that ingredient unchecked', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('garlic'));
      await tester.pump();
      await tester.tap(find.text('garlic'));
      await tester.pump();

      sessions.restored.complete(saved);
      await tester.pump();
      await closeIngredients(tester);
      await openIngredients(tester);
      expect(find.text('0 of 2 checked'), findsOneWidget);
    });

    testWidgets('Start over wins over a delayed saved session', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await tester.tap(find.text('Mark done'));
      await tester.pump();
      await tester.tap(find.byTooltip('Start over'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
      await tester.pumpAndSettle();

      sessions.restored.complete(saved);
      await tester.pump();
      await openIngredients(tester);
      expect(find.text('0 of 2 checked'), findsOneWidget);
      expect(
        await sessions.read('unused-by-fake', now: DateTime.now()),
        isNull,
      );
    });
  });

  group('overlapping visits', () {
    const StoredCookProgress saved = StoredCookProgress(
      currentStep: 0,
      checkedStepIds: <String>{},
    );

    testWidgets(
      'reopening before the old read returns keeps both visits checks',
      (WidgetTester tester) async {
        final Recipe recipe = checklistRecipe();
        final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
        await pumpChecklist(tester, recipe: recipe, sessions: sessions);
        await openIngredients(tester);
        await tester.tap(find.text('olive oil'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // B opens while A still has its old SELECT and unsaved oil check.
        await pumpChecklist(tester, recipe: recipe, sessions: sessions);
        await openIngredients(tester);
        sessions.restored.complete(saved);
        await tester.pumpAndSettle();

        // A's UPSERT is now complete. B must not replace it with its older row.
        await tester.tap(find.text('garlic'));
        await tester.pump();
        expect(
          (await sessions.read(
            recipe.id,
            now: DateTime.now(),
          ))!.checkedIngredientIds,
          <String>{'oil', 'garlic'},
        );
        expect(find.text('2 of 2 checked'), findsOneWidget);
      },
    );

    testWidgets('a reopened visit also waits for the old buffered save', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final DelayedReadAndSaveCookSessionStore sessions =
          DelayedReadAndSaveCookSessionStore(saved);
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      sessions.restored.complete(saved);
      await tester.pumpAndSettle();
      expect(sessions.saveCalls, 1);
      expect(sessions.reads, 1, reason: 'B cannot read ahead of A’s UPSERT');

      // B stays usable while A flushes; its own fresh check will be merged.
      await tester.tap(find.text('garlic'));
      await tester.pump();
      sessions.firstSave.complete();
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          recipe.id,
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
    });

    testWidgets('taps during a buffered save are flushed before reopening', (
      WidgetTester tester,
    ) async {
      final Recipe recipe = checklistRecipe();
      final DelayedReadAndSaveCookSessionStore sessions =
          DelayedReadAndSaveCookSessionStore(saved);
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      sessions.restored.complete(saved);
      await tester.pumpAndSettle();
      expect(sessions.saveCalls, 1);

      // A can keep cooking while its first merged save is still pending.
      await tester.tap(find.text('garlic'));
      await tester.pump();
      expect(find.text('2 of 2 checked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      sessions.firstSave.complete();
      await tester.pumpAndSettle();

      expect(
        (await sessions.read(
          recipe.id,
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
      expect(find.text('2 of 2 checked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final bool checkAfterReset in <bool>[false, true]) {
      testWidgets(
        'Start over during a buffered save keeps ${checkAfterReset ? 'fresh checks' : 'the reset'}',
        (WidgetTester tester) async {
          final Recipe recipe = checklistRecipe();
          final DelayedReadAndSaveCookSessionStore sessions =
              DelayedReadAndSaveCookSessionStore(saved);
          final FakeTimerAlerts alerts = await pumpChecklist(
            tester,
            recipe: recipe,
            sessions: sessions,
          );
          await tester.tap(find.text('Start 10 min timer'));
          await tester.pump();
          await openIngredients(tester);
          await tester.tap(find.text('olive oil'));
          await tester.pump();
          sessions.restored.complete(saved);
          await tester.pumpAndSettle();
          expect(sessions.saveCalls, 1);

          await closeIngredients(tester);
          await tester.tap(find.byTooltip('Start over'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
          await tester.pumpAndSettle();
          expect(sessions.clears, 0, reason: 'the old save is still pending');
          expect(
            alerts.cancelAlls,
            1,
            reason: 'timers stop before storage waits',
          );
          expect(find.byTooltip('Pause timer'), findsNothing);
          await openIngredients(tester);
          expect(find.text('0 of 2 checked'), findsOneWidget);
          if (checkAfterReset) {
            await tester.tap(find.text('garlic'));
            await tester.pump();
          }

          // The reset and any fresh choices also finish after this visit leaves.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await pumpChecklist(tester, recipe: recipe, sessions: sessions);
          await openIngredients(tester);
          sessions.firstSave.complete();
          await tester.pumpAndSettle();
          final StoredCookProgress? result = await sessions.read(
            recipe.id,
            now: DateTime.now(),
          );
          if (checkAfterReset) {
            expect(result!.checkedIngredientIds, <String>{'garlic'});
            expect(find.text('1 of 2 checked'), findsOneWidget);
          } else {
            expect(result, isNull);
            expect(find.text('0 of 2 checked'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a failed old read releases a reopened visit', (
      WidgetTester tester,
    ) async {
      const StoredCookProgress existing = StoredCookProgress(
        currentStep: 0,
        checkedStepIds: <String>{},
        checkedIngredientIds: <String>{'oil'},
      );
      final Recipe recipe = checklistRecipe();
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(
        existing,
      );
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpChecklist(tester, recipe: recipe, sessions: sessions);
      await openIngredients(tester);
      sessions.restored.completeError(StateError('test cook read failure'));
      await tester.pumpAndSettle();

      expect(sessions.reads, 2);
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(checklistRetry(), findsNothing);
      await tester.tap(find.text('garlic'));
      await tester.pump();
      expect(
        (await sessions.read(
          recipe.id,
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('failed restoration', () {
    const StoredCookProgress saved = StoredCookProgress(
      currentStep: 0,
      checkedStepIds: <String>{},
      checkedIngredientIds: <String>{'garlic'},
    );

    testWidgets('a failed Start over retries without losing fresh choices', (
      WidgetTester tester,
    ) async {
      final FailingClearCookSessionStore sessions =
          FailingClearCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await tester.tap(find.byTooltip('Start over'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
      await tester.pumpAndSettle();
      await openIngredients(tester);
      expect(find.text('0 of 2 checked'), findsOneWidget);
      final Finder retry = find.descendant(
        of: find.byKey(const ValueKey<String>('cook-ingredient-checklist')),
        matching: find.widgetWithText(OutlinedButton, 'Retry Start over'),
      );
      expect(retry, findsOneWidget);

      await tester.tap(find.text('olive oil'));
      await tester.pump();
      expect(sessions.saves, 0);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'garlic'},
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(sessions.clearCalls, 2);
      expect(sessions.saves, 1);
      expect(retry, findsNothing);
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil'},
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a one-shot read failure can retry and save fresh checks', (
      WidgetTester tester,
    ) async {
      final FailingCookSessionStore sessions = FailingCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      expect(find.text('1 of 2 checked'), findsOneWidget);
      expect(
        sessions.saves,
        0,
        reason: 'unseen saved checks must not be replaced',
      );

      await tester.ensureVisible(checklistRetry());
      await tester.tap(checklistRetry());
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 checked'), findsOneWidget);
      expect(sessions.saves, 1);
      expect(checklistRetry(), findsNothing);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('olive oil'));
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      expect(
        sessions.saves,
        2,
        reason: 'later taps must resume saving normally',
      );
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'garlic'},
      );
    });

    testWidgets('an open checklist shows a late failure and can retry', (
      WidgetTester tester,
    ) async {
      final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      sessions.restored.completeError(StateError('test cook read failure'));
      await tester.pumpAndSettle();

      expect(checklistRetry(), findsOneWidget);
      expect(sessions.saves, 0);
      await tester.ensureVisible(checklistRetry());
      await tester.tap(checklistRetry());
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 checked'), findsOneWidget);
      expect(sessions.saves, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeated failure retains reset intent until retry succeeds', (
      WidgetTester tester,
    ) async {
      final FailingCookSessionStore sessions = FailingCookSessionStore(
        saved,
        failures: 2,
      );
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.ensureVisible(find.text('olive oil'));
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.ensureVisible(find.text('Reset ingredients'));
      await tester.tap(find.text('Reset ingredients'));
      await tester.pump();

      await tester.ensureVisible(checklistRetry());
      await tester.tap(checklistRetry());
      await tester.pumpAndSettle();
      expect(checklistRetry(), findsOneWidget);
      expect(find.text('0 of 2 checked'), findsOneWidget);
      expect(sessions.saves, 0);

      await tester.tap(checklistRetry());
      await tester.pumpAndSettle();
      expect(checklistRetry(), findsNothing);
      expect(find.text('0 of 2 checked'), findsOneWidget);
      expect(sessions.saves, 1);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a retry completed after leaving still merges fresh choices', (
      WidgetTester tester,
    ) async {
      final Completer<StoredCookProgress?> retry =
          Completer<StoredCookProgress?>();
      final FailingCookSessionStore sessions = FailingCookSessionStore(
        saved,
        retryResult: retry,
      );
      await pumpChecklist(tester, sessions: sessions);
      await openIngredients(tester);
      await tester.ensureVisible(find.text('olive oil'));
      await tester.tap(find.text('olive oil'));
      await tester.pump();
      await tester.ensureVisible(checklistRetry());
      await tester.tap(checklistRetry());
      await tester.pump();
      expect(sessions.reads, 2);
      final Finder retrying = find.descendant(
        of: find.byKey(const ValueKey<String>('cook-ingredient-checklist')),
        matching: find.widgetWithText(OutlinedButton, 'Retrying…'),
      );
      expect(tester.widget<OutlinedButton>(retrying).onPressed, isNull);
      expect(sessions.saves, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      retry.complete(saved);
      await tester.pump();
      expect(sessions.saves, 1);
      expect(
        (await sessions.read(
          'unused-by-fake',
          now: DateTime.now(),
        ))!.checkedIngredientIds,
        <String>{'oil', 'garlic'},
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'failure after leaving neither writes nor updates disposed UI',
      (WidgetTester tester) async {
        final DelayedCookSessionStore sessions = DelayedCookSessionStore(saved);
        await pumpChecklist(tester, sessions: sessions);
        await openIngredients(tester);
        await tester.tap(find.text('olive oil'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        sessions.restored.completeError(StateError('test cook read failure'));
        await tester.pump();
        expect(sessions.saves, 0);
        expect(
          (await sessions.read(
            'unused-by-fake',
            now: DateTime.now(),
          ))!.checkedIngredientIds,
          <String>{'garlic'},
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a recipe with no directions can retry from the screen', (
      WidgetTester tester,
    ) async {
      final FailingCookSessionStore sessions = FailingCookSessionStore(null);
      await pumpChecklist(tester, recipe: aRecipe(), sessions: sessions);
      await tester.tap(find.text('Retry saved progress'));
      await tester.pumpAndSettle();
      expect(find.text('Retry saved progress'), findsNothing);
      expect(
        find.text('This recipe has no steps to cook along with.'),
        findsOneWidget,
      );
      expect(sessions.reads, 2);
      expect(tester.takeException(), isNull);
    });

    for (final Brightness brightness in Brightness.values) {
      testWidgets('failure feedback scrolls at 320px and 3x in '
          '${brightness.name}', (WidgetTester tester) async {
        final FailingCookSessionStore sessions = FailingCookSessionStore(saved);
        await pumpChecklist(
          tester,
          sessions: sessions,
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Mark done'));
        await tester.tap(find.text('Mark done'));
        await tester.pump();
        expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);

        await tester.tap(find.byTooltip('All steps'));
        await tester.pump();
        await tester.ensureVisible(find.text('Retry saved progress'));
        expect(tester.takeException(), isNull);

        await openIngredients(tester);
        await tester.ensureVisible(find.text('olive oil'));
        await tester.tap(find.text('olive oil'));
        await tester.pump();
        await tester.ensureVisible(checklistRetry());
        await tester.tap(checklistRetry());
        await tester.pumpAndSettle();
        expect(find.text('2 of 2 checked'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeIngredients(tester);
        expect(find.text('Retry saved progress'), findsNothing);
        expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('all-steps timer control fits at 320px and 3x', (
    WidgetTester tester,
  ) async {
    await pumpChecklist(tester, size: const Size(320, 568), textScale: 3);
    await tester.tap(find.byTooltip('All steps'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('320px at 3x: rows, reset and exit are reachable in '
        '${brightness.name}', (WidgetTester tester) async {
      final Recipe recipe = aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient(
            'extra virgin olive oil for brushing the bread',
            id: 'long-oil',
            amount: 2,
            unit: Units.tbsp,
          ),
          anIngredient('garlic', id: 'garlic', amount: 3, unit: Units.item),
          anIngredient('salt to taste', id: 'salt', optional: true),
        ],
        steps: <RecipeStep>[aStep('Bake until golden.')],
      );
      await pumpChecklist(
        tester,
        recipe: recipe,
        size: const Size(320, 568),
        textScale: 3,
        brightness: brightness,
      );
      await openIngredients(tester);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('garlic'));
      await tester.tap(find.text('garlic'));
      await tester.pump();
      expect(find.text('Prepared / added'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Reset ingredients'));
      await tester.tap(find.text('Reset ingredients'));
      await tester.pump();
      expect(find.text('Prepared / added'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Back to cooking'));
      await tester.tap(find.text('Back to cooking'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ingredients'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
