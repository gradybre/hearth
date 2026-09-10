import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Getting through a long menu (spec §5.2, review §7.6).
///
/// The acceptance test the review sets is literal: "finding guacamole does
/// not require traversing 100 Chopt entries". On the fixture below guacamole
/// is item 43 of 44, which is about five screenfuls of thumb — and there was
/// nothing between the app bar and the first row to shorten it with.
void main() {
  Food item(
    String name, {
    String? section,
    int? order,
    Macros macros = const Macros(kcal: 180, proteinG: 12),
  }) => aFood(
    name,
    id: 'f-chopt-${name.toLowerCase().replaceAll(' ', '-')}',
    brand: 'Chopt',
    source: FoodSource.restaurant,
    menuGroup: section,
    menuOrder: order,
    servingOptions: <ServingOption>[
      aServing(amount: 4, unit: Units.ounce, macros: macros),
    ],
  );

  /// Six sections, forty-four rows, guacamole near the bottom.
  List<Food> longMenu() => <Food>[
    for (int i = 1; i <= 6; i++)
      item('Warm bowl $i', section: 'Warm bowls', order: i),
    for (int i = 7; i <= 14; i++)
      item('Chopped salad ${i - 6}', section: 'Chopped salads', order: i),
    for (int i = 15; i <= 20; i++)
      item('Green ${i - 14}', section: 'Greens', order: i),
    for (int i = 21; i <= 27; i++)
      item('Protein ${i - 20}', section: 'Proteins', order: i),
    for (int i = 28; i <= 34; i++)
      item('Dressing ${i - 27}', section: 'Dressings', order: i),
    for (int i = 35; i <= 42; i++)
      item('Topping ${i - 34}', section: 'Toppings', order: i),
    item('Guacamole', section: 'Toppings', order: 43),
    item('Tortilla chips', section: 'Toppings', order: 44),
  ];

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Eat out');
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Chopt'));
    await pumpFrames(tester, frames: 12);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await pumpFrames(tester, frames: 12);
  }

  /// The horizontal rail the section chips sit in.
  ///
  /// `.first` is the innermost: the rail scrolls inside the menu list now, so
  /// a chip has two scrollable ancestors and asking for "the" one is asking
  /// for two.
  Finder rail() => find
      .ancestor(
        of: find.byType(FilterChip).first,
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> reachChip(WidgetTester tester, String section) async {
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, section),
      120,
      scrollable: rail(),
      maxScrolls: 20,
    );
    await pumpFrames(tester, frames: 8);
  }

  Future<void> jumpTo(WidgetTester tester, String section) async {
    await reachChip(tester, section);
    await tester.tap(find.widgetWithText(FilterChip, section));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('guacamole is reachable without scrolling past forty rows', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);

    // Not on screen to begin with — five and a half screenfuls down.
    expect(find.text('Guacamole'), findsNothing);

    await search(tester, 'guac');

    expect(find.text('Guacamole'), findsOneWidget);
    expect(
      find.text('Warm bowl 1'),
      findsNothing,
      reason: 'searching narrowed nothing',
    );
  });

  testWidgets('and the search says how much it is searching', (
    WidgetTester tester,
  ) async {
    // The count is the fact that tells you the control is worth using: a
    // bare magnifier over a list you cannot see the end of says nothing.
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);

    expect(find.text('Search 44 items'), findsOneWidget);
  });

  testWidgets('a section that still matches keeps its heading', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);
    await search(tester, 'guac');

    // The heading is there because Toppings still has a match. "Warm bowls"
    // is still on screen too — as its jump chip, which is not a heading and
    // must not disappear, or you could not jump back to it.
    expect(find.text('Toppings'), findsWidgets);
    expect(
      find.text('Warm bowl 1'),
      findsNothing,
      reason: 'a section with no matches left its rows in the list',
    );
  });

  testWidgets('filtering never clears a pick', (WidgetTester tester) async {
    // The review makes this an acceptance criterion, and it is the one thing
    // here that could silently lose work. Picks are keyed by food id, so a
    // row leaving the filtered list is not a row leaving the meal.
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);

    await tester.tap(find.text('Warm bowl 1'));
    await pumpFrames(tester, frames: 12);

    await search(tester, 'guac');
    await tester.tap(find.text('Guacamole'));
    await pumpFrames(tester, frames: 12);

    await search(tester, '');

    // Both are still in it: the one picked before the filter and the one
    // picked during it.
    expect(
      find.textContaining('2 items ·'),
      findsOneWidget,
      reason: 'the meal did not survive being filtered',
    );
  });

  testWidgets('a nothing-matches search says so and offers a way back', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);
    await search(tester, 'zzzz');

    expect(find.textContaining('Nothing on this menu matches'), findsOneWidget);
  });

  group('section jump', () {
    // A filter rather than a scroll, and deliberately. Scrolling to a heading
    // means reaching a widget a lazy `ListView` has not built yet:
    // `ensureVisible` has no context for it, and the app carries no
    // scroll-to-index package to do it properly. A filter gets you to
    // Toppings exactly, keeps the source order and grouping inside it, and
    // composes with the search rather than fighting it.
    testWidgets('every section is offered', (WidgetTester tester) async {
      await pumpHearthApp(tester, foods: longMenu());
      await openMenu(tester);

      for (final String section in <String>[
        'Warm bowls',
        'Chopped salads',
        'Toppings',
      ]) {
        await reachChip(tester, section);
        expect(
          find.widgetWithText(FilterChip, section),
          findsOneWidget,
          reason: 'no jump to $section',
        );
      }
    });

    testWidgets('and choosing one brings that section into view', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: longMenu());
      await openMenu(tester);

      expect(find.text('Topping 1'), findsNothing);

      await jumpTo(tester, 'Toppings');

      expect(find.text('Topping 1'), findsOneWidget);
      expect(
        find.text('Warm bowl 1'),
        findsNothing,
        reason: 'the other sections were left in the way',
      );
    });

    testWidgets('choosing it again puts the whole menu back', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: longMenu());
      await openMenu(tester);

      await jumpTo(tester, 'Toppings');
      await jumpTo(tester, 'Toppings');

      expect(find.text('Warm bowl 1'), findsOneWidget);
    });
  });

  testWidgets('the section rail grows with the text rather than squashing', (
    WidgetTester tester,
  ) async {
    // The rail was a fixed 60pt box with the chips centred in it, so at 3x
    // the chip did not overflow — it was *constrained*, which is quieter and
    // no better: it wants 78 points and was given 56, the same 56 it got at
    // 2x and eight more than at ordinary text. Dynamic type is honoured, not
    // capped (spec §6.3).
    //
    // One pump, and the two facts that settle it: the chip is past the old
    // ceiling, and the rail is at least as tall as the chip it holds. A
    // second `pumpHearthApp` in the same test would leave the first app's
    // widgets standing for the finder to read.
    await pumpHearthApp(tester, foods: longMenu(), textScale: 3);
    await openMenu(tester);

    final double chip = tester.getSize(find.byType(FilterChip).first).height;
    final double around = tester.getSize(rail()).height;

    expect(
      chip,
      greaterThan(60),
      reason: 'the chip is $chip points at 3x — still squashed',
    );
    expect(
      around,
      greaterThanOrEqualTo(chip),
      reason: 'the rail is $around points around a $chip point chip',
    );
  });

  testWidgets('a search inside a section says which section it searched', (
    WidgetTester tester,
  ) async {
    // Filter to Dressings, search for guacamole, and "Nothing on this menu
    // matches" is simply false: guacamole is on this menu, one section over.
    // The sentence has to name the narrowing that produced it, or it sends
    // somebody off to add a food they already have.
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);
    await jumpTo(tester, 'Dressings');
    await search(tester, 'guac');

    expect(find.textContaining('Nothing in Dressings'), findsOneWidget);
    expect(
      find.textContaining('Nothing on this menu matches'),
      findsNothing,
      reason: 'it said the menu had no guacamole, and the menu does',
    );
  });

  testWidgets('and searching the whole menu from there finds it', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: longMenu());
    await openMenu(tester);
    await jumpTo(tester, 'Dressings');
    await search(tester, 'guac');

    await tester.tap(find.text('Search the whole menu'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Guacamole'), findsOneWidget);
  });

  // The take-out control's move off the rows is asserted where the rest of
  // the deduction behaviour lives, in eat_out_builder_test.dart — beside the
  // rule it changed rather than in a second place that would drift from it.

  testWidgets('the builder is named for what you are about to do', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: longMenu());
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Eat out');
    await pumpFrames(tester, frames: 12);

    expect(find.text('Eat out'), findsWidgets);
    expect(find.text('Ate out'), findsNothing);
    // It has taken PDFs and photographs since #52; paste is one of three
    // ways in, and naming the least of them was never right.
    expect(find.text('Add restaurant'), findsOneWidget);
    expect(find.text('Paste another menu'), findsNothing);
  });

  testWidgets('a countable serving is not written with a trailing space', (
    WidgetTester tester,
  ) async {
    // Not a defect in this screen, in the end. A rendered frame read
    // "1  · 690 kcal" and looked like one — but `QuantityFormat.format`
    // gives production a plain "1", and the gap came from the *fixture*,
    // whose default label pasted an empty unit onto the amount. Kept as a
    // test because a fixture that renders wrong is how a screenshot argues
    // for a change nothing needed.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Harvest Bowl',
          id: 'f-chopt-harvest',
          brand: 'Chopt',
          source: FoodSource.restaurant,
          menuGroup: 'Warm bowls',
          menuOrder: 1,
          servingOptions: <ServingOption>[
            aServing(
              amount: 1,
              unit: Units.item,
              macros: const Macros(kcal: 690),
            ),
          ],
        ),
      ],
    );
    await openMenu(tester);

    expect(find.text('1 · 690 kcal'), findsOneWidget);
  });
}
