import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';

/// The shopping task, before the setup for it (review §6.2.5, §7.7).
///
/// "Shopping's large date/setup card and Build button precede the actual
/// shopping task." Measured rather than judged: on a 390x844 phone the card
/// is 244 points of a 605-point viewport and the first line starts at y=419.
/// At twice the text on a small phone it is 398 points of a 401-point
/// viewport — no list line is on screen at all, and the first one is not even
/// built into the tree.
///
/// The range is a fact you check once to be sure you are looking at the right
/// list. The list is the reason the screen exists.
void main() {
  int order = 0;
  ShoppingLine line(
    String name, {
    String? store,
    bool ticked = false,
    bool manual = false,
  }) => ShoppingLine(
    key: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    planned: <Quantity>[Quantity.of(2, Units.pound)],
    checked: ticked,
    storeTag: store,
    isManual: manual,
    sortOrder: order++,
  );

  List<ShoppingLine> aList() => <ShoppingLine>[
    line('Ground beef', store: 'Costco'),
    line('Chicken breast', store: 'Costco', ticked: true),
    line('Rolled oats', store: 'Costco'),
    line('Greek yogurt', store: "Trader Joe's"),
    line('Whole milk'),
    line('Coffee beans'),
  ];

  Future<void> openShopping(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    List<ShoppingLine>? lines,
  }) async {
    await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      shoppingLines: lines ?? aList(),
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester, frames: 12);
  }

  /// Where the tab bar starts, which is where the screen stops.
  ///
  /// `findsOneWidget` is not "on screen": a `ListView` builds a little past
  /// its viewport, so both of these passed while the first line sat 160
  /// points below the fold. Position is the only honest question here.
  double foldAt(WidgetTester tester) {
    // The action bar, when there is one: it sits *above* the tab bar, so
    // measuring against the tabs called a row visible that the bar was
    // covering. The list ends where the bar begins.
    final Finder bar = find.text('Nothing leaves the app until you tap that.');
    if (bar.evaluate().isNotEmpty) return tester.getTopLeft(bar).dy;
    return tester.getTopLeft(find.text('Recipes').last).dy;
  }

  testWidgets('the first thing to buy is above the fold', (
    WidgetTester tester,
  ) async {
    await openShopping(tester);

    final double first = tester.getTopLeft(find.text('Ground beef')).dy;
    final double fold = foldAt(tester);

    expect(
      first,
      lessThan(fold),
      reason: 'the first line starts $first points down, the fold is $fold',
    );
    // And not merely on screen by a hair: the setup above it was 244 points
    // of a 605-point viewport, which is the complaint.
    expect(first, lessThan(fold * 0.45));
  });

  testWidgets('and still is at twice the text on a small phone', (
    WidgetTester tester,
  ) async {
    // The strongest case, and the one that was hopeless: 398 points of setup
    // in a 401-point viewport. Dynamic type is honoured, not capped
    // (spec §6.3), so what has to give is the setup's claim to the screen.
    await openShopping(tester, size: const Size(320, 640), scale: 2);

    final double first = tester.getTopLeft(find.text('Ground beef')).dy;

    expect(
      first,
      lessThan(foldAt(tester)),
      reason: 'not one line of the list is on screen',
    );
  });

  testWidgets('the range is stated, quietly, with what is left', (
    WidgetTester tester,
  ) async {
    // Still said — you have to be able to tell you are looking at the right
    // list — but as a line rather than as the largest thing on the screen.
    await openShopping(tester);

    expect(find.textContaining('9/'), findsWidgets);
    expect(
      find.textContaining('6 items'),
      findsOneWidget,
      reason: 'the count of what is left is the fact a shop wants',
    );
  });

  group('setup moves behind Manage list', () {
    testWidgets('the seasonings switch and rebuild leave the list screen', (
      WidgetTester tester,
    ) async {
      await openShopping(tester);

      expect(find.text('Include seasonings'), findsNothing);
      expect(find.text('Build from the plan'), findsNothing);
      expect(find.text('Manage list'), findsOneWidget);
    });

    testWidgets('and are all still there behind it', (
      WidgetTester tester,
    ) async {
      await openShopping(tester);
      await tester.tap(find.text('Manage list'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Include seasonings'), findsOneWidget);
      expect(find.textContaining('Rebuild'), findsWidgets);
      expect(find.textContaining('9/'), findsWidgets);
    });

    testWidgets('an empty list keeps its setup up front', (
      WidgetTester tester,
    ) async {
      // The review is explicit that the empty state's controls are already
      // right: "range, Build from plan, Add item are appropriate primary
      // controls". An empty list is a setup task; a full one is not.
      await openShopping(tester, lines: const <ShoppingLine>[]);

      expect(find.text('Build from the plan'), findsOneWidget);
      expect(find.text('Manage list'), findsNothing);
    });
  });

  group('the things the render turned up', () {
    testWidgets('export is reachable without scrolling past the list', (
      WidgetTester tester,
    ) async {
      // It sat below all sixteen rows — off screen in every render — and it
      // is the one action on this screen that sends anything anywhere
      // (rule 4). The words that say so go with it.
      await openShopping(tester);

      expect(find.text('Share or export'), findsOneWidget);
      final double y = tester.getTopLeft(find.text('Share or export')).dy;
      expect(y, lessThan(844), reason: 'the export is $y points down');
    });

    testWidgets('a line added by hand says that it was', (
      WidgetTester tester,
    ) async {
      // Indistinguishable from a plan-derived line, so a rebuild that would
      // keep it and a rebuild that would not look identical beforehand.
      await openShopping(
        tester,
        lines: <ShoppingLine>[
          line('Ground beef', store: 'Costco'),
          line('Paper towels', manual: true),
        ],
      );

      expect(find.textContaining('added by hand'), findsOneWidget);
    });
  });
}
