@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../support/fake_kitchen.dart';
import '../support/fixtures.dart';
import 'gallery.dart';

// Synthetic fixture using the instruction wording supplied for this UI review.
const String chiliDirections =
    'Heat 1 tbsp neutral oil in a large skillet over medium-high heat. '
    'Add 2 lb 96:4 ground beef and cook, breaking it into crumbles, until no '
    'longer pink, about 6-8 minutes. '
    "There's very little fat to render from 96:4, so this step is really "
    'about browning for flavor rather than rendering fat.';

Recipe directionsPreviewRecipe(String scene) => aRecipe(
  title: 'Big-Batch Slow Cooker Chili',
  ingredients: <RecipeIngredient>[
    anIngredient('96:4 ground beef', amount: 2, unit: Units.pound),
    anIngredient('neutral oil', amount: 1, unit: Units.tbsp),
    if (scene == 'directions-eight')
      for (final String name in <String>[
        'garlic',
        'onion',
        'carrot',
        'celery',
        'tomato',
        'beef broth',
      ])
        anIngredient(name, amount: 1, unit: Units.cup),
  ],
  steps: <RecipeStep>[
    aStep(
      switch (scene) {
        'directions-short' => 'Warm the neutral oil.',
        'directions-unpunctuated' =>
          'Add the 96:4 ground beef to the neutral oil and stir gently while '
              'breaking it into small crumbles until evenly browned and then '
              'transfer to a large bowl while keeping the skillet over medium '
              'heat so the next batch cooks at the same steady temperature',
        'directions-eight' =>
          '$chiliDirections Add garlic, onion, carrot, '
              'celery, tomato and beef broth. Cover and simmer.',
        _ => chiliDirections,
      },
      stepNumber: 1,
      timerSeconds: 360,
    ),
    aStep('Stir well. Cover and cook until tender.', stepNumber: 2),
  ],
);

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  const List<Scene> captures = <Scene>[
    Scene(name: 'directions-phone-light'),
    Scene(name: 'directions-phone-dark', brightness: Brightness.dark),
    Scene(name: 'directions-small', size: Size(320, 568)),
    Scene(name: 'directions-small-2x', size: Size(320, 568), textScale: 2),
    Scene(name: 'directions-small-3x', size: Size(320, 568), textScale: 3),
    Scene(name: 'directions-desktop', size: Size(1280, 800)),
    Scene(name: 'directions-short'),
    Scene(name: 'directions-unpunctuated'),
    Scene(name: 'directions-eight'),
  ];
  for (final Scene scene in captures) {
    testWidgets('directions render: ${scene.name}', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scene.size;
      addTearDown(tester.view.reset);
      final Recipe recipe = directionsPreviewRecipe(scene.name);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
            timerAlertsProvider.overrideWithValue(FakeTimerAlerts()),
            cookTimersProvider.overrideWith(FakeCookTimers.new),
            cookSessionStoreProvider.overrideWithValue(FakeCookSessionStore()),
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
      await writeScene(tester, scene);
      if (scene.name != 'directions-short') {
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
        await tester.ensureVisible(find.text('Start 6 min timer'));
        await tester.tap(find.text('Start 6 min timer'));
        await tester.pump();
        await tester.ensureVisible(find.text('Mark done'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-timer'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: !renderingGallery);
  }
}
