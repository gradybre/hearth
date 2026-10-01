import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

const String _recipeId = 'availability-supper';

Recipe _supper({bool deleted = false}) => aRecipe(
  id: _recipeId,
  title: 'White bean supper',
  isDeleted: deleted,
  ingredients: <RecipeIngredient>[
    anIngredient('white beans', amount: 2, unit: Units.can),
  ],
  steps: <RecipeStep>[aStep('Warm the beans.')],
);

Future<ProviderContainer> _openRecipe(
  WidgetTester tester, {
  required FutureOr<Recipe?> Function() load,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  await pumpHearthApp(
    tester,
    size: const Size(320, 568),
    textScale: textScale,
    brightness: brightness,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    recipes: <Recipe>[_supper()],
    extraOverrides: <Object>[
      recipeByIdProvider(_recipeId).overrideWith((Ref ref) async => load()),
    ],
  );
  await pumpFrames(tester);
  unawaited(
    GoRouter.of(tester.element(find.byType(RecipeLibraryScreen)))
        .push<void>('/recipe/$_recipeId'),
  );
  await pumpFrames(tester, frames: 12);
  return ProviderScope.containerOf(
    tester.element(find.byType(RecipeDetailScreen)),
  );
}

void _expectNoRecipeActions() {
  expect(find.byTooltip('Add to favourites'), findsNothing);
  expect(find.byTooltip('Remove from favourites'), findsNothing);
  expect(find.byTooltip('Cookbooks'), findsNothing);
  expect(find.byTooltip('Duplicate this recipe'), findsNothing);
  for (final String label in <String>['Edit', 'Cook', 'Plan', 'Shop']) {
    expect(
      find.text(label),
      findsNothing,
      reason: '$label needs a live recipe',
    );
  }
}

Future<void> _press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await pumpFrames(tester);
  await tester.tap(find.text(label).last);
  await pumpFrames(tester, frames: 12);
}

void main() {
  for (final bool deleted in <bool>[false, true]) {
    testWidgets('${deleted ? 'deleted' : 'missing'} recipe has no actions', (
      WidgetTester tester,
    ) async {
      await _openRecipe(
        tester,
        load: () => deleted ? _supper(deleted: true) : null,
      );
      _expectNoRecipeActions();
      expect(find.text('Recipe unavailable'), findsOneWidget);
      expect(find.text('Warm the beans.'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester, frames: 12);
      expect(find.byType(RecipeDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading does not offer actions before availability is known', (
    WidgetTester tester,
  ) async {
    final Completer<Recipe?> pending = Completer<Recipe?>();
    await _openRecipe(tester, load: () => pending.future);
    _expectNoRecipeActions();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(_supper());
    await pumpFrames(tester);
    expect(find.text('Plan'), findsOneWidget);
  });

  testWidgets(
    'failed lookup has a human-readable Retry and no recipe actions',
    (WidgetTester tester) async {
      bool fails = true;
      await _openRecipe(
        tester,
        load: () {
          if (fails) throw StateError('private transport detail');
          return _supper();
        },
      );
      _expectNoRecipeActions();
      expect(find.textContaining('private transport detail'), findsNothing);
      fails = false;
      await _press(tester, 'Retry');
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final String action in <String>['Plan', 'Shop']) {
    testWidgets(
      'deleting a recipe during $action review prevents a stale save',
      (WidgetTester tester) async {
        Recipe current = _supper();
        final ProviderContainer container = await _openRecipe(
          tester,
          load: () => current,
        );
        await _press(tester, action);
        current = _supper(deleted: true);
        container.invalidate(recipeByIdProvider(_recipeId));
        await pumpFrames(tester);
        await _press(
          tester,
          action == 'Plan' ? 'Add to my plan' : 'Add to the list',
        );

        final PlanRepository plans = container.read(planRepositoryProvider);
        final ShoppingRepository shopping = container.read(
          shoppingRepositoryProvider,
        );
        expect(await plans.entriesFor(DateTime.now()), isEmpty);
        expect((await shopping.current())?.lines ?? <Object>[], isEmpty);
        expect(
          find.text('This recipe is no longer available. Nothing was added.'),
          findsOneWidget,
        );
        _expectNoRecipeActions();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a held Cook callback cannot open a deleted recipe', (
    WidgetTester tester,
  ) async {
    Recipe current = _supper();
    final ProviderContainer container = await _openRecipe(
      tester,
      load: () => current,
    );
    final VoidCallback cook = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Cook'))
        .onPressed!;
    current = _supper(deleted: true);
    container.invalidate(recipeByIdProvider(_recipeId));
    await pumpFrames(tester);
    cook();
    await pumpFrames(tester, frames: 12);
    expect(find.byType(CookAlongScreen), findsNothing);
    expect(
      find.text('Recipe unavailable'),
      findsOneWidget,
      reason:
          '${container.read(recipeByIdProvider(_recipeId))}; '
          '${tester.widgetList<Text>(find.byType(Text)).map((Text text) => text.data).toList()}',
    );
    expect(tester.takeException(), isNull);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('unavailable recipe scrolls at 3x in ${brightness.name} mode', (
      WidgetTester tester,
    ) async {
      await _openRecipe(
        tester,
        load: () => _supper(deleted: true),
        textScale: 3,
        brightness: brightness,
      );
      _expectNoRecipeActions();
      expect(find.text('Recipe unavailable'), findsOneWidget);
      await _press(tester, 'Go back');
      expect(find.byType(RecipeDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
