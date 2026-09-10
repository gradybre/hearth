import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import '../../support/app_harness.dart';

/// Marking a line as one that will never have a food (spec §5.3).
///
/// A pinch of salt has nothing to match and never will, but it counted among
/// a recipe's unmatched ingredients all the same — and a warning that is
/// always on stops being read.
Future<void> openEditorWith(WidgetTester tester, String lines) async {
  await pumpHearthApp(tester);
  await addRecipeVia(tester, 'Write a recipe');
  await pumpFrames(tester);
  await tester.enterText(
    find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
    ),
    lines,
  );
  await pumpFrames(tester, frames: 12);
}

void main() {
  group('what Hearth already knows', () {
    testWidgets('salt is quiet the first time it is ever typed', (
      WidgetTester tester,
    ) async {
      // A *quantified* seasoning, which is the case that was broken. "Salt to
      // taste" was never the problem: the parser already reads "to taste" as
      // optional, so that line was excluded on the recipe's own say-so.
      await openEditorWith(tester, '2 lb ground beef\n1 tsp salt');

      expect(find.text('seasoning — no match needed'), findsOneWidget);
      // And the beef still asks, because it is a real ingredient.
      expect(find.text('tap to match a food'), findsOneWidget);
    });

    testWidgets('so is a spice, recognised through its modifiers', (
      WidgetTester tester,
    ) async {
      await openEditorWith(
        tester,
        '1 tsp smoked paprika\n1/2 tsp freshly ground black pepper',
      );

      expect(find.text('seasoning — no match needed'), findsNWidgets(2));
      expect(find.text('tap to match a food'), findsNothing);
    });

    testWidgets('but salt pork is a food and still asks', (
      WidgetTester tester,
    ) async {
      // The guard that matters. Dropping 8 oz of pork out of a recipe
      // silently would be far worse than one more question.
      await openEditorWith(tester, '8 oz salt pork');

      expect(find.text('tap to match a food'), findsOneWidget);
      expect(find.text('seasoning — no match needed'), findsNothing);
    });

    testWidgets('a seasoning is never called "optional"', (
      WidgetTester tester,
    ) async {
      // Salt in a bread recipe is not optional, and saying so to quiet a
      // warning would misreport the recipe.
      await openEditorWith(tester, '2 tsp kosher salt');

      expect(find.textContaining('optional'), findsNothing);
      expect(find.text('not counted'), findsNothing);
      expect(find.text('seasoning — no match needed'), findsOneWidget);
    });

    testWidgets('"to taste" is still the recipe\'s own word, untouched', (
      WidgetTester tester,
    ) async {
      // Unchanged behaviour, asserted so it stays that way: the parser reads
      // "to taste" as optional and that is what the recipe said.
      await openEditorWith(tester, 'salt to taste');
      expect(find.text('not counted'), findsOneWidget);
    });
  });

  group('marking one', () {
    testWidgets('from the row, and it sticks for the next recipe', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester);
      await tester.enterText(
        find.byWidgetPredicate(
          (Widget w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
        ),
        '1 tbsp fish sauce',
      );
      await pumpFrames(tester, frames: 12);

      expect(find.text('tap to match a food'), findsOneWidget);
      await tester.tap(find.byTooltip('Nothing to match — it is a seasoning'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('seasoning — no match needed'), findsOneWidget);

      // Remembered for the household, which is what makes the next recipe
      // start quiet — the whole of "and the same ability to default those".
      final List<IngredientMatchRow> rows = await db
          .select(db.ingredientMatches)
          .get();
      expect(rows.single.ingredientString, 'fish sauce');
      expect(rows.single.needsNoMatch, isTrue);
      expect(rows.single.foodId, isNull);
    });

    testWidgets('and taking it back off is recorded, not just forgotten', (
      WidgetTester tester,
    ) async {
      // A built-in would simply reapply itself if this only deleted the row.
      final HearthDatabase db = await pumpHearthApp(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester);
      await tester.enterText(
        find.byWidgetPredicate(
          (Widget w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
        ),
        '1 cup water',
      );
      await pumpFrames(tester, frames: 12);
      expect(find.text('seasoning — no match needed'), findsOneWidget);

      await tester.tap(find.byTooltip('This does need a food after all'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('tap to match a food'), findsOneWidget);
      final List<IngredientMatchRow> rows = await db
          .select(db.ingredientMatches)
          .get();
      expect(rows.single.ingredientString, 'water');
      expect(rows.single.needsNoMatch, isFalse);
      expect(rows.single.foodId, isNull);
    });

    testWidgets('from the picker, on a line that can take the mark', (
      WidgetTester tester,
    ) async {
      await openEditorWith(tester, '1 tbsp fish sauce');
      await tester.tap(find.text('tap to match a food'));
      await pumpFrames(tester, frames: 12);

      await tester.tap(find.text('Mark as a seasoning instead'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('seasoning — no match needed'), findsOneWidget);
    });

    testWidgets('but not offered where it could not possibly land', (
      WidgetTester tester,
    ) async {
      // "Salt to taste" is excluded already, on the recipe's own say-so, and
      // `MacroCalculator` resolves that before it looks at the seasoning mark
      // — so the status can never become "seasoning" however hard the button
      // is pressed. Offering it anyway was a control that wrote a remembered
      // row, changed nothing on screen, and read exactly like a bug.
      await openEditorWith(tester, 'salt to taste');
      expect(find.text('not counted'), findsOneWidget);

      await tester.tap(find.text('not counted'));
      await pumpFrames(tester, frames: 12);

      // The picker still opens: attaching a food to a "to taste" line is a
      // reasonable thing to want. It is only the seasoning offer that goes.
      expect(find.text('Search your foods'), findsOneWidget);
      expect(find.text('Mark as a seasoning instead'), findsNothing);
    });
  });

  group('the list of them', () {
    testWidgets('is reachable from Foods and shows what is known', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);

      // Maintenance moved into a labelled overflow menu (review §7.5): it
      // used to be an unexplained sprig of grass floating in the corner.
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester);
      await tester.tap(find.text('Seasonings that need no match'));
      await pumpFrames(tester);

      expect(find.text('Seasonings'), findsOneWidget);
      expect(find.text('Known to Hearth'), findsOneWidget);
      // The list is long and lazily built, so it is scrolled to rather than
      // assumed on screen.
      await tester.scrollUntilVisible(find.text('salt'), 300);
      expect(find.text('salt'), findsOneWidget);
    });

    testWidgets('turning a built-in off there is recorded', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester);
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      // Maintenance moved into a labelled overflow menu (review §7.5): it
      // used to be an unexplained sprig of grass floating in the corner.
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester);
      await tester.tap(find.text('Seasonings that need no match'));
      await pumpFrames(tester);

      await tester.scrollUntilVisible(find.text('water'), 300);
      await pumpFrames(tester);
      await tester.tap(find.text('water'));
      await pumpFrames(tester, frames: 12);

      final List<IngredientMatchRow> rows = await db
          .select(db.ingredientMatches)
          .get();
      expect(rows.single.ingredientString, 'water');
      expect(rows.single.needsNoMatch, isFalse);
    });
  });
}
