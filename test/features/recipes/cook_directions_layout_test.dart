import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';
import 'cook_ingredients_layout_test.dart'
    show pumpCookAlong, simpleRecipe, eightIngredientRecipe;

/// UI regression tests for P-HEARTH-COOK-002 (loop/cook-directions-v1).
///
/// Deliberately imports only the existing `CookAlongScreen`, the existing
/// `test/support/fixtures.dart` builders, and (via a `show` import that
/// excludes `main`) the existing `pumpCookAlong` pump helper and recipe
/// fixtures already used by `cook_ingredients_layout_test.dart`. It does
/// **not** import the new `cookInstructionBlocks` formatter, and it does
/// not modify `cook_along_screen.dart`: this file is meant to run as-is
/// against the pre-change baseline first (where the layout assertions
/// below are expected to fail) and again once the design lands.

const String _chiliSentence1 =
    'Heat 1 tbsp neutral oil in a large skillet over medium-high heat.';
const String _chiliSentence2 =
    'Add 2 lb 96:4 ground beef and cook, breaking it into crumbles, until '
    'no longer pink, about 6-8 minutes.';
const String _chiliSentence3 =
    "There's very little fat to render from 96:4, so this step is really "
    'about browning for flavor rather than rendering fat.';

Recipe chiliRecipe() => aRecipe(
  title: 'Weeknight chili',
  ingredients: <RecipeIngredient>[
    anIngredient('neutral oil', amount: 1, unit: Units.tbsp),
    anIngredient('ground beef', amount: 2, unit: Units.pound),
  ],
  steps: <RecipeStep>[
    aStep(
      '$_chiliSentence1 $_chiliSentence2 $_chiliSentence3',
      stepNumber: 1,
      timerSeconds: 360,
    ),
    aStep('Serve hot.', stepNumber: 2),
  ],
);

void main() {
  testWidgets(
    'completed-step control fits the scroll viewport at 3x with a timer',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpCookAlong(tester, recipe: chiliRecipe(), textScale: 3);
      await tester.ensureVisible(find.text('Start 6 min timer'));
      await tester.tap(find.text('Start 6 min timer'));
      await tester.pump();
      await tester.ensureVisible(find.text('Mark done'));
      await tester.pump();
      final Rect viewport = tester.getRect(find.byType(SingleChildScrollView));
      final Rect label = tester.getRect(find.text('Mark done'));
      expect(label.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(label.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(tester.takeException(), isNull);
    },
  );

  group('reading blocks (R2/R3)', () {
    testWidgets(
      'chili step renders as three separate left-aligned reading blocks',
      (WidgetTester tester) async {
        await pumpCookAlong(tester, recipe: chiliRecipe());

        for (final String sentence in <String>[
          _chiliSentence1,
          _chiliSentence2,
          _chiliSentence3,
        ]) {
          final Finder finder = find.text(sentence);
          expect(
            finder,
            findsOneWidget,
            reason: '"$sentence" should render as its own paragraph',
          );
          final Text widget = tester.widget<Text>(finder);
          expect(
            widget.textAlign,
            TextAlign.left,
            reason: 'reading blocks must be left-aligned, not centered',
          );
          final double? size = widget.style?.fontSize;
          expect(size, isNotNull);
          expect(size, inInclusiveRange(24, 26));
        }
      },
    );

    testWidgets('the oversized duplicate step numeral is removed', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: chiliRecipe());

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text && w.data == '1' && (w.style?.fontSize ?? 0) > 30,
        ),
        findsNothing,
        reason:
            'R2: no oversized duplicate step numeral above the reading '
            'column',
      );
    });

    testWidgets('progress label keeps the existing Step X of Y string', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: chiliRecipe());
      expect(find.text('Step 1 of 2'), findsOneWidget);
    });

    testWidgets(
      'ingredient panel presentation is unchanged by the new layout',
      (WidgetTester tester) async {
        await pumpCookAlong(tester, recipe: eightIngredientRecipe());
        expect(find.text('For this step'), findsOneWidget);
      },
    );
  });

  group('reading column alignment (R1)', () {
    testWidgets(
      'desktop: progress label and reading column share a left edge within '
      'a 560pt column',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpCookAlong(tester, recipe: chiliRecipe());

        final double progressLeft = tester
            .getTopLeft(find.text('Step 1 of 2'))
            .dx;
        final double bodyLeft = tester
            .getTopLeft(find.text(_chiliSentence1))
            .dx;
        expect(
          (progressLeft - bodyLeft).abs(),
          lessThan(1.0),
          reason:
              'R1: progress label and directions must align to the '
              'same left edge',
        );

        final double bodyRight = tester
            .getTopRight(find.text(_chiliSentence1))
            .dx;
        expect(
          bodyRight - bodyLeft,
          lessThanOrEqualTo(560.0),
          reason:
              'R1: the reading column must not exceed 560 logical '
              'pixels',
        );
      },
    );

    testWidgets('a short instruction is anchored to the top of its area', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: simpleRecipe());

      final double top = tester
          .getTopLeft(find.text('Season the ribs with olive oil'))
          .dy;
      final double screenHeight = tester.getSize(find.byType(Scaffold)).height;
      expect(
        top,
        lessThan(screenHeight * 0.4),
        reason:
            'R1: short content must anchor near the top, not the '
            'vertical centre',
      );
    });
  });

  group('preserved behaviour (R5/R6)', () {
    testWidgets('screen readers get the full original instruction once, with '
        'tap-to-advance and Mark done', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpCookAlong(tester, recipe: chiliRecipe());

      final String fullText =
          '$_chiliSentence1 $_chiliSentence2 $_chiliSentence3';
      final SemanticsNode instruction = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Tap to go on.')),
      );
      expect(
        instruction.label.contains(fullText),
        isTrue,
        reason:
            'R6: the screen reader must still get the full original '
            'text once',
      );

      expect(
        () => tester.getSemantics(find.text('Mark done')),
        returnsNormally,
      );

      handle.dispose();
    });

    testWidgets('tapping the instruction still advances with the new layout', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: chiliRecipe());
      await tester.tap(find.text(_chiliSentence1));
      await tester.pump();
      expect(find.text('Step 2 of 2'), findsOneWidget);
    });

    testWidgets('advancing to a new step resets scroll to the top', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpCookAlong(tester, recipe: chiliRecipe(), textScale: 2);

      final Finder scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pump();
      final ScrollableState before = tester.state<ScrollableState>(scrollable);
      expect(before.position.pixels, greaterThan(0));

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Step 2 of 2'), findsOneWidget);

      final Finder scrollableAfter = find.byType(Scrollable).first;
      final ScrollableState after = tester.state<ScrollableState>(
        scrollableAfter,
      );
      expect(
        after.position.pixels,
        0,
        reason: 'R6: a new step must start at its own top',
      );
    });
  });

  group('size and scale matrix with a running timer (A1/R5)', () {
    const List<Size> sizes = <Size>[Size(320, 568)];
    const List<double> scales = <double>[1, 2, 3];

    for (final Size size in sizes) {
      for (final double scale in scales) {
        testWidgets(
          'chili step scrolls to its last paragraph without overflow at '
          '${size.width.toInt()}x${size.height.toInt()} @ ${scale}x text',
          (WidgetTester tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await pumpCookAlong(
              tester,
              recipe: chiliRecipe(),
              textScale: scale,
            );

            final Finder startTimer = find.text('Start 6 min timer');
            expect(startTimer, findsOneWidget);
            {
              await tester.ensureVisible(startTimer);
              await tester.pump();
              await tester.tap(startTimer);
              await tester.pump();
            }

            await tester.ensureVisible(find.text(_chiliSentence3));
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(find.text(_chiliSentence3), findsOneWidget);
          },
        );
      }
    }
  });
}
