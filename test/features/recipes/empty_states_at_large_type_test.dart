import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Empty states at accessibility text sizes (spec §6.3).
///
/// The rule is that the layout gives way around the words, never that the
/// words are capped. An empty state is where that is hardest and where it
/// matters most: there is nothing else on the screen, so a clipped sentence
/// is the entire screen being wrong — and it is the first thing somebody sees
/// when they open the app for the first time, which is exactly when the
/// sentence explaining the way in has to be readable.
///
/// A `RenderFlex` overflow throws in a test, so rendering at all is most of
/// the assertion. The text is checked as well, so a layout that "fits" by
/// dropping the sentence fails here rather than passing quietly.
void main() {
  // The smallest phone the app supports, where the sentence wraps hardest;
  // a large one; and a desktop window, which is not a nicety — macOS and
  // Windows are shipping targets. The window is where this last broke: a
  // centred message is capped at 380 points wide however much room there is,
  // so on a wide window the width it is *measured* at and the width it is
  // *drawn* at are different numbers, and the sliver that sizes itself from
  // the measurement came up 318 points short at 3x.
  for (final (String, Size) surface in const <(String, Size)>[
    ('a small phone', Size(320, 568)),
    ('a large phone', Size(430, 932)),
    ('a desktop window', Size(1000, 600)),
  ]) {
    final (String name, Size size) = surface;
    for (final double scale in <double>[1.0, 2.0, 3.0]) {
      testWidgets('the empty library reads on $name at text scale $scale', (
        WidgetTester tester,
      ) async {
        await pumpHearthApp(tester, size: size, textScale: scale);
        await tester.tap(find.text('Recipes').last);
        await pumpFrames(tester);

        expect(find.text('Your library is empty'), findsOneWidget);
        expect(
          find.textContaining('Add recipe offers four ways in'),
          findsOneWidget,
          reason: 'the way in is the whole point of this screen',
        );
      });

      testWidgets('the empty food library reads on $name at scale $scale', (
        WidgetTester tester,
      ) async {
        // The other library, and the other half of CentredMessage: this one
        // scrolls rather than being measured by a sliver, so it takes a
        // different path through the same widget. Both are worth holding.
        await pumpHearthApp(tester, size: size, textScale: scale);
        await tester.tap(find.text('Foods').last);
        await pumpFrames(tester);

        expect(find.text('No foods yet'), findsOneWidget);
        expect(find.textContaining('Scan a packet'), findsOneWidget);
      });

      testWidgets('and so does no-matches on $name at text scale $scale', (
        WidgetTester tester,
      ) async {
        // A library with something in it, filtered down to nothing — the
        // longer of the two messages, and the one that has to name the way
        // back out.
        await pumpHearthApp(
          tester,
          size: size,
          textScale: scale,
          recipes: <Recipe>[aRecipe(id: 'r1', title: 'Short ribs')],
        );
        await tester.tap(find.text('Recipes').last);
        await pumpFrames(tester);

        await tester.enterText(
          find.byType(TextField).first,
          'nothing matches this',
        );
        await pumpFrames(tester);

        // Scrolled to rather than expected in place. At 3x on the small phone
        // the filter chips alone are taller than the viewport, so the answer
        // sits below them — which is the layout giving way, exactly as it is
        // supposed to, and not the message being clipped. Dragging to it is
        // what proves it is whole: a message clipped by its own container
        // would still be missing at the bottom of the scroll.
        await tester.scrollUntilVisible(
          find.text('No recipes match'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await pumpFrames(tester);

        expect(find.text('No recipes match'), findsOneWidget);
        expect(
          find.textContaining('Nothing matches'),
          findsOneWidget,
          reason: 'the reason has to survive too, not just the heading',
        );
      });

      testWidgets('including its longest form on $name at scale $scale', (
        WidgetTester tester,
      ) async {
        // Three paragraphs rather than two: a lit calorie or protein chip
        // adds the sentence explaining that recipes with unmatched
        // ingredients are left out of those filters. It is the most prose the
        // app ever centres on an empty screen, so it is the one with the most
        // to lose — and it is a variant the shorter case cannot stand in for.
        await pumpHearthApp(
          tester,
          size: size,
          textScale: scale,
          recipes: <Recipe>[aRecipe(id: 'r1', title: 'Short ribs')],
        );
        await tester.tap(find.text('Recipes').last);
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField).first, 'zzz');
        await pumpFrames(tester);

        // The chips scroll sideways, and at these sizes the calorie one
        // starts well off the right-hand edge.
        await tester.dragUntilVisible(
          find.text('Under 600 kcal'),
          find.byType(Scrollable).at(1),
          const Offset(-300, 0),
        );
        await pumpFrames(tester);
        await tester.tap(find.text('Under 600 kcal'));
        await pumpFrames(tester);

        await tester.scrollUntilVisible(
          find.text('No recipes match'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await pumpFrames(tester);

        expect(
          find.textContaining('no nutrition to filter on'),
          findsOneWidget,
          reason: 'an empty screen without this sentence reads as a bug',
        );
      });
    }
  }
}
