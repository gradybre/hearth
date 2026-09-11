import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Using the food you already have, from the duplicate warning (review N05).
///
/// The warning has always been able to say "this looks like something you
/// already have" and then offer exactly two ways out: go back, or make a
/// second copy. §7.5 asks for the third and most obvious one first — *use
/// that one* — and is explicit that it comes before any attempt at a real
/// merge, because it writes nothing at all.
///
/// That matters most where the editor was opened to answer a question: a
/// scan started from a recipe ingredient hands back the id of the food it
/// settled on, and the food it should settle on is the one already there.
void main() {
  Food yogurt() => aFood(
    'Greek yogurt',
    id: 'food-yogurt',
    brand: 'Fage',
    servingOptions: <ServingOption>[
      aServing(
        id: 's1',
        amount: 170,
        unit: Units.gram,
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  Future<HearthDatabase> openNewFood(
    WidgetTester tester, {
    List<Food> foods = const <Food>[],
  }) async {
    final HearthDatabase db = await pumpHearthApp(tester, foods: foods);
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Enter it by hand'));
    await pumpFrames(tester);
    return db;
  }

  /// Types a name that collides with [yogurt] and presses Save.
  Future<void> saveAs(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField).first, name);
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);
  }

  group('the warning offers the food you already have', () {
    testWidgets('as a choice, not only as a list item', (
      WidgetTester tester,
    ) async {
      await openNewFood(tester, foods: <Food>[yogurt()]);
      await saveAs(tester, 'Greek yogurt');

      expect(find.text('Already in your library?'), findsOneWidget);
      expect(find.text('Use this one'), findsOneWidget);
    });

    testWidgets('with enough of it to tell them apart', (
      WidgetTester tester,
    ) async {
      // N05's safety note: "two foods with similar names may have different
      // servings or macros", and the whole decision is whether this really is
      // the same thing. A name and a brand cannot answer that.
      await openNewFood(tester, foods: <Food>[yogurt()]);
      await saveAs(tester, 'Greek yogurt');

      expect(find.textContaining('Fage'), findsOneWidget);
      // The serving as this app writes servings — `ServingFormat` turns a
      // metric-only 170 g into 6 oz for a US kitchen, deliberately — and what
      // it comes to.
      expect(find.textContaining('6 oz'), findsOneWidget);
      expect(find.textContaining('100 kcal'), findsOneWidget);
    });

    testWidgets('and says when it is not showing all of them', (
      WidgetTester tester,
    ) async {
      // The list is capped at three for length. That was a display choice
      // when every row was a bullet; now that a row is a *choice* it would be
      // hiding candidates without admitting to it, and the one you wanted
      // could be the fourth.
      await openNewFood(
        tester,
        foods: <Food>[
          yogurt(),
          aFood('Greek yogurt', id: 'f-2', brand: 'Chobani'),
          aFood('Greek yogurt', id: 'f-3', brand: 'Skyr'),
          aFood('Greek yogurt', id: 'f-4', brand: 'Siggi'),
        ],
      );
      await saveAs(tester, 'Greek yogurt');

      expect(find.text('Use this one'), findsNWidgets(3));
      expect(find.textContaining('1 more like it'), findsOneWidget);
    });

    testWidgets('and the other two ways out are still there', (
      WidgetTester tester,
    ) async {
      await openNewFood(tester, foods: <Food>[yogurt()]);
      await saveAs(tester, 'Greek yogurt');

      expect(find.text('Go back'), findsOneWidget);
      expect(find.text('Save anyway'), findsOneWidget);
    });
  });

  group('choosing it', () {
    testWidgets('writes nothing at all', (WidgetTester tester) async {
      // The reason this half comes first (§7.5): no merge, no remap, no
      // soft-delete. One food before, one food after.
      final HearthDatabase db = await openNewFood(
        tester,
        foods: <Food>[yogurt()],
      );
      await saveAs(tester, 'Greek yogurt');

      await tester.tap(find.text('Use this one'));
      await pumpFrames(tester, frames: 20);

      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'food-yogurt');
    });

    testWidgets('and leaves the editor', (WidgetTester tester) async {
      await openNewFood(tester, foods: <Food>[yogurt()]);
      await saveAs(tester, 'Greek yogurt');

      await tester.tap(find.text('Use this one'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('New food'), findsNothing);
    });

    testWidgets('and does not leave the draft behind to be restored', (
      WidgetTester tester,
    ) async {
      // Drafts exist for interruption (#51). Choosing the food you already
      // have is a decision, not an interruption — restoring it on the next
      // visit would be the app arguing with a choice somebody made.
      await openNewFood(tester, foods: <Food>[yogurt()]);
      await saveAs(tester, 'Greek yogurt');
      await tester.tap(find.text('Use this one'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Add food'));
      await pumpFrames(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('Restore'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        isEmpty,
      );
    });
  });

  group('the other two still do what they did', () {
    testWidgets('save anyway makes the second copy', (
      WidgetTester tester,
    ) async {
      // Two things genuinely can share a name, and §5.5 is explicit that the
      // warning is soft.
      final HearthDatabase db = await openNewFood(
        tester,
        foods: <Food>[yogurt()],
      );
      await saveAs(tester, 'Greek yogurt');

      await tester.tap(find.text('Save anyway'));
      await pumpFrames(tester, frames: 20);

      expect(await db.select(db.foods).get(), hasLength(2));
    });

    testWidgets('go back writes nothing and stays in the editor', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openNewFood(
        tester,
        foods: <Food>[yogurt()],
      );
      await saveAs(tester, 'Greek yogurt');

      await tester.tap(find.text('Go back'));
      await pumpFrames(tester, frames: 20);

      expect(await db.select(db.foods).get(), hasLength(1));
      expect(find.text('New food'), findsOneWidget);
    });
  });

  testWidgets('the warning survives a small phone at three times the text', (
    WidgetTester tester,
  ) async {
    // Walked here rather than by the flow sweep, and deliberately said out
    // loud in `swept_surfaces.dart`: the surface guard is per *file*, and
    // this file already had an entry for its discard dialog — so a second
    // dialog in it would have shipped with nothing walking it.
    //
    // Three duplicates, each with a name, a brand, a serving and a calorie
    // figure, is taller than a 320-point phone at 3x, which is why the
    // content scrolls.
    await pumpHearthApp(
      tester,
      size: const Size(320, 568),
      textScale: 3,
      foods: <Food>[
        yogurt(),
        aFood('Greek yogurt', id: 'f-2', brand: 'Chobani'),
        aFood('Greek yogurt', id: 'f-3', brand: 'Skyr'),
      ],
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Enter it by hand'));
    await pumpFrames(tester);
    await saveAs(tester, 'Greek yogurt');

    expect(find.text('Already in your library?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a food is never offered somebody else\'s', (
    WidgetTester tester,
  ) async {
    // The editor hands back the id of the food it settled on. On an edit,
    // that id is the one the caller asked to edit — handing back a different
    // food would answer a question nobody asked, and the edit would be lost
    // with it.
    // The other one is spelled differently and normalises the same, so the
    // warning still fires and the row that is tapped is unambiguous.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        yogurt(),
        aFood(
          'greek  yogurt',
          id: 'food-other',
          servingOptions: <ServingOption>[
            aServing(
              id: 's2',
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 60, proteinG: 10),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    // The card runs name and brand together, so the brand is what picks the
    // valid one out of two rows that would otherwise read the same.
    await tester.tap(find.textContaining('Fage'));
    await pumpFrames(tester, frames: 20);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Already in your library?'), findsOneWidget);
    expect(find.text('Use this one'), findsNothing);
  });
}
