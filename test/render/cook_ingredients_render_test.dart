@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/local/cook_session_store.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../support/fake_kitchen.dart';
import '../support/fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

class _UnreadCookProgress extends FakeCookSessionStore {
  @override
  Future<StoredCookProgress?> read(
    String recipeId, {
    required DateTime now,
  }) async => throw StateError('Synthetic interrupted local read');
}

class _UnclearedCookProgress extends FakeCookSessionStore {
  _UnclearedCookProgress()
    : super(
        const StoredCookProgress(currentStep: 1, checkedStepIds: <String>{}),
      );

  bool _failNextClear = true;

  @override
  Future<void> clear(String recipeId) async {
    if (_failNextClear) {
      _failNextClear = false;
      throw StateError('Synthetic interrupted local reset');
    }
    await super.clear(recipeId);
  }
}

// Synthetic food only. Captures the actual Flutter screen with bundled fonts.
Recipe cookPreviewRecipe({bool long = false}) => aRecipe(
  title: 'Lemon herb chicken',
  ingredients: <RecipeIngredient>[
    anIngredient('chicken breast', amount: 1, unit: Units.pound),
    anIngredient('olive oil', amount: 2, unit: Units.tbsp),
    anIngredient('lemon juice', amount: 1, unit: Units.tbsp),
    if (long) ...<RecipeIngredient>[
      anIngredient('freshly minced garlic', amount: 2, unit: Units.tsp),
      anIngredient('smoked paprika', amount: 1, unit: Units.tsp),
      anIngredient('dried oregano', amount: 1, unit: Units.tsp),
      anIngredient('freshly ground black pepper', amount: 1, unit: Units.tsp),
      anIngredient(
        'finely chopped flat-leaf parsley',
        amount: 2,
        unit: Units.tbsp,
      ),
    ],
  ],
  steps: <RecipeStep>[
    aStep(
      long
          ? 'Coat the chicken breast with olive oil, lemon juice, freshly '
                'minced garlic, smoked paprika, dried oregano, freshly ground '
                'black pepper and finely chopped flat-leaf parsley. Turn each '
                'piece until evenly covered, then rest before cooking.'
          : 'Coat the chicken breast with olive oil and lemon juice.',
      stepNumber: 1,
      timerSeconds: 600,
    ),
    aStep('Sear until golden, then finish cooking.', stepNumber: 2),
  ],
);

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  const List<Scene> captures = <Scene>[
    Scene(name: 'cook-phone-light'),
    Scene(name: 'cook-phone-dark', brightness: Brightness.dark),
    Scene(name: 'cook-small', size: Size(320, 568)),
    Scene(name: 'cook-small-2x', size: Size(320, 568), textScale: 2),
    Scene(name: 'cook-small-3x', size: Size(320, 568), textScale: 3),
    Scene(name: 'cook-desktop', size: Size(1280, 800)),
    Scene(name: 'cook-long'),
    Scene(name: 'cook-retry-small-3x', size: Size(320, 568), textScale: 3),
    Scene(name: 'cook-retry-dark', brightness: Brightness.dark),
    Scene(
      name: 'cook-reset-retry-small-3x',
      size: Size(320, 568),
      textScale: 3,
    ),
    Scene(name: 'cook-reset-retry-dark', brightness: Brightness.dark),
  ];
  for (final Scene scene in captures) {
    testWidgets('cook render: ${scene.name}', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scene.size;
      addTearDown(tester.view.reset);
      final Recipe recipe = cookPreviewRecipe(long: scene.name == 'cook-long');
      final bool resetRetry = scene.name.contains('reset-retry');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
            timerAlertsProvider.overrideWithValue(FakeTimerAlerts()),
            cookTimersProvider.overrideWith(FakeCookTimers.new),
            cookSessionStoreProvider.overrideWithValue(
              resetRetry
                  ? _UnclearedCookProgress()
                  : scene.name.contains('retry')
                  ? _UnreadCookProgress()
                  : FakeCookSessionStore(),
            ),
            cookShowAllStepsProvider.overrideWith(
              () => FakeCookStepView(false),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: HearthTheme.light(),
            darkTheme: HearthTheme.dark(),
            themeMode: scene.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scene.textScale),
                padding: scene.size.width < 600
                    ? const EdgeInsets.only(top: 44, bottom: 34)
                    : EdgeInsets.zero,
              ),
              child: child!,
            ),
            home: CookAlongScreen(recipe: recipe),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final SweepTools tools = SweepTools(tester);
      if (resetRetry) {
        await tools.reach(find.byTooltip('Start over'));
        await tools.reach(find.widgetWithText(FilledButton, 'Start over'));
        expect(tester.takeException(), isNull);
      }
      await writeScene(tester, scene);
      if (scene.textScale > 1 || scene.name == 'cook-long') {
        final Finder scroll = find.byType(SingleChildScrollView).first;
        await tester.drag(scroll, const Offset(0, -800));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('For this step'));
        await tester.pump();
        await writeScene(tester, Scene(name: '${scene.name}-ingredients'));
        await tester.ensureVisible(find.text('Mark done'));
        await tester.pump();
        await writeScene(tester, Scene(name: '${scene.name}-scrolled'));
      }
      await tester.tap(find.byTooltip('Ingredients'));
      await tester.pump(const Duration(milliseconds: 400));
      final Finder retry = find.text(
        resetRetry ? 'Retry Start over' : 'Retry saved progress',
      );
      if (scene.name.contains('retry')) {
        await tools.bring(retry);
        await writeScene(tester, Scene(name: '${scene.name}-checklist-retry'));
      }
      final Finder firstIngredient = find.byKey(
        ValueKey<String>('cook-ingredient-${recipe.allIngredients.first.id}'),
      );
      await tools.reach(firstIngredient);
      expect(find.text('Prepared / added'), findsOneWidget);
      await writeScene(tester, Scene(name: '${scene.name}-checklist-checked'));
      await tools.bring(find.text('Reset ingredients'));
      await writeScene(tester, Scene(name: '${scene.name}-checklist-controls'));
      await tools.reach(find.text('Reset ingredients'));
      expect(
        find.text('0 of ${recipe.allIngredients.length} checked'),
        findsOneWidget,
      );
      if (resetRetry) {
        await tools.reach(retry);
        expect(retry, findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: !renderingGallery);
  }
}
