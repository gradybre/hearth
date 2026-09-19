import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../../support/fake_kitchen.dart';
import '../../support/fixtures.dart';

/// Focused-card ingredient readability (loop/cook-ingredients-v1).
///
/// Deliberately does **not** import `cook_along_test.dart` — pulling in a
/// second `main()` from a sibling test file is how two test runs collide.
/// Everything here is built from the public fixtures/fakes in
/// `test/support/`, plus a small pump helper local to this file so it can be
/// run as-is against both the pre-change baseline (where it is expected to
/// fail — there is no "For this step" panel yet) and this candidate (where it
/// is expected to pass).
///
/// Nothing here names a `forCooking` constructor parameter directly: it only
/// asserts on what a cook actually sees and hears, which is what makes it a
/// fair regression check against the old production code too.

/// A step whose direction text literally contains every one of eight
/// ingredient names, so `StepIngredients.forStep`'s word-matching finds all
/// eight without relying on any fuzzy behaviour this test does not own.
Recipe eightIngredientRecipe() => aRecipe(
  title: 'Long braise',
  ingredients: <RecipeIngredient>[
    anIngredient('olive oil', amount: 2, unit: Units.tbsp),
    anIngredient('kosher salt', amount: 5, unit: Units.gram),
    anIngredient('black pepper', amount: 3, unit: Units.gram),
    anIngredient('garlic', amount: 20, unit: Units.gram),
    anIngredient('onion', amount: 150, unit: Units.gram),
    anIngredient('carrot', amount: 100, unit: Units.gram),
    anIngredient('celery', amount: 80, unit: Units.gram),
    anIngredient('beef broth', amount: 16, unit: Units.ounce),
  ],
  steps: <RecipeStep>[
    aStep(
      'Combine the olive oil, kosher salt, black pepper, garlic, onion, '
      'carrot, celery and beef broth in the pot, then cover and simmer.',
      stepNumber: 1,
      timerSeconds: 600,
    ),
  ],
);

/// A step whose direction text names nothing in its own ingredient list, for
/// the empty-panel case.
Recipe noMatchRecipe() => aRecipe(
  title: 'Nothing to show',
  ingredients: <RecipeIngredient>[
    anIngredient('olive oil', amount: 2, unit: Units.tbsp),
  ],
  steps: <RecipeStep>[aStep('Preheat the oven.', stepNumber: 1)],
);

Recipe simpleRecipe() => aRecipe(
  title: 'Braised short ribs',
  ingredients: <RecipeIngredient>[
    anIngredient('olive oil', amount: 2, unit: Units.tbsp),
  ],
  steps: <RecipeStep>[
    aStep('Season the ribs with olive oil', stepNumber: 1),
    aStep('Sear until browned', stepNumber: 2, timerSeconds: 600),
  ],
);

Future<void> pumpCookAlong(
  WidgetTester tester, {
  required Recipe recipe,
  bool showAllSteps = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
        timerAlertsProvider.overrideWithValue(FakeTimerAlerts()),
        cookTimersProvider.overrideWith(FakeCookTimers.new),
        cookSessionStoreProvider.overrideWithValue(FakeCookSessionStore()),
        cookShowAllStepsProvider.overrideWith(
          () => FakeCookStepView(showAllSteps),
        ),
      ],
      child: MaterialApp(
        theme: HearthTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: child!,
        ),
        home: CookAlongScreen(recipe: recipe),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('quantities: every matched ingredient shows once, quantity first', () {
    testWidgets('renders all eight matched rows in the candidate size band', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: eightIngredientRecipe());

      expect(find.text('For this step'), findsOneWidget);

      const List<String> names = <String>[
        'olive oil',
        'kosher salt',
        'black pepper',
        'garlic',
        'onion',
        'carrot',
        'celery',
        'beef broth',
      ];
      for (final String name in names) {
        final Finder finder = find.byWidgetPredicate(
          (Widget w) => w is Text && (w.data ?? '').endsWith(' $name'),
        );
        expect(finder, findsOneWidget, reason: '$name should appear once');

        final Text widget = tester.widget<Text>(finder);
        final double? size = widget.style?.fontSize;
        expect(size, isNotNull);
        // D7: 22 is the initial candidate; Astra may move it within 20–24
        // after visual review. This test only pins the approved range, not
        // the exact value, so that review does not have to touch this file.
        expect(
          size,
          inInclusiveRange(20, 24),
          reason: '$name row should be in the approved 20–24pt band',
        );
        expect(widget.style?.height, closeTo(1.4, 0.05));
      }
    });
  });

  group('empty panel', () {
    testWidgets('no heading and no panel for zero matched ingredients', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: noMatchRecipe());

      expect(find.text('For this step'), findsNothing);
    });
  });

  group('compact presentation is unchanged', () {
    testWidgets('All steps keeps the old ruler-icon metadata line', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: simpleRecipe(), showAllSteps: true);

      expect(find.byIcon(Icons.straighten), findsWidgets);
      expect(
        find.text('For this step'),
        findsNothing,
        reason: 'the compact view never gets the focused-card heading',
      );
    });
  });

  group('semantics: independent controls, no duplicate announcement', () {
    testWidgets(
      'the instruction node does not also carry the ingredient panel text',
      (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await pumpCookAlong(tester, recipe: simpleRecipe());

        final SemanticsNode instruction = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Tap to go on.')),
        );
        expect(
          instruction.label.contains('For this step'),
          isFalse,
          reason:
              'the ingredient panel must not be folded into the '
              'instruction\'s single tap-to-advance announcement',
        );

        handle.dispose();
      },
    );

    testWidgets('Mark done remains an independently reachable control', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpCookAlong(tester, recipe: simpleRecipe());

      // Reachable at all without throwing is the assertion: under the old
      // whole-card `excludeSemantics: true`, this control had no semantics
      // of its own to find.
      expect(
        () => tester.getSemantics(find.text('Mark done')),
        returnsNormally,
      );

      handle.dispose();
    });

    testWidgets('an ingredient line is independently reachable', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpCookAlong(tester, recipe: simpleRecipe());

      expect(
        () => tester.getSemantics(find.text('2 tbsp olive oil')),
        returnsNormally,
      );

      handle.dispose();
    });
  });

  group('scroll and gesture behaviour is preserved', () {
    testWidgets('tapping the instruction still advances', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: simpleRecipe());

      await tester.tap(find.text('Season the ribs with olive oil'));
      await tester.pump();

      expect(find.text('Step 2 of 2'), findsOneWidget);
    });

    testWidgets('Mark done ticks the step rather than only advancing', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: simpleRecipe());

      await tester.tap(find.text('Mark done'));
      await tester.pump();

      expect(find.text('Step 2 of 2  ·  1 done'), findsOneWidget);
    });

    testWidgets(
      'a long recipe with a full panel still scrolls, not overflows',
      (WidgetTester tester) async {
        await pumpCookAlong(tester, recipe: eightIngredientRecipe());

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(find.text('Start 10 min timer'), findsOneWidget);
      },
    );
  });

  testWidgets('navigation labels stay whole at 3x on a small phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpCookAlong(tester, recipe: simpleRecipe(), textScale: 3);
    for (final String label in <String>['Back', 'Next']) {
      expect(
        tester.getSize(find.text(label)).height,
        lessThan(70),
        reason: 'a short navigation word must not split across lines',
      );
    }
  });

  testWidgets('timer and done actions never skip the next ingredient step', (
    WidgetTester tester,
  ) async {
    await pumpCookAlong(
      tester,
      recipe: aRecipe(
        ingredients: <RecipeIngredient>[
          anIngredient('olive oil', amount: 2, unit: Units.tbsp),
          anIngredient('garlic', amount: 1, unit: Units.tsp),
        ],
        steps: <RecipeStep>[
          aStep('Heat the olive oil.', stepNumber: 1, timerSeconds: 600),
          aStep('Stir in the garlic.', stepNumber: 2, timerSeconds: 120),
          aStep('Serve.', stepNumber: 3),
        ],
      ),
    );
    await tester.ensureVisible(find.text('Start 10 min timer'));
    await tester.tap(find.text('Start 10 min timer'));
    await tester.pump();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.ensureVisible(find.text('Mark done'));
    await tester.tap(find.text('Mark done'));
    await tester.pump();
    expect(find.text('Step 2 of 3  ·  1 done'), findsOneWidget);
    expect(find.text('1 tsp garlic'), findsOneWidget);
    expect(find.text('Start 2 min timer'), findsOneWidget);
    expect(find.text('Serve.'), findsNothing);
  });

  group('size and text-scale matrix', () {
    const List<Size> sizes = <Size>[
      Size(320, 568),
      Size(390, 844),
      Size(1280, 800),
    ];
    const List<double> scales = <double>[1, 2, 3];

    for (final Size size in sizes) {
      for (final double scale in scales) {
        testWidgets('long recipe, eight ingredients and a timer at '
            '${size.width.toInt()}x${size.height.toInt()} @ ${scale}x text', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await pumpCookAlong(
            tester,
            recipe: eightIngredientRecipe(),
            textScale: scale,
          );

          expect(tester.takeException(), isNull);

          // All content and actions stay reachable: scroll to the bottom
          // and confirm Mark done can still be found and tapped, and the
          // ingredient panel is present somewhere in the tree.
          await tester.ensureVisible(find.text('Mark done'));
          await tester.pump();
          expect(find.text('Mark done'), findsOneWidget);
          expect(find.text('For this step'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
