import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_amount_sheet.dart';

import '../../support/package_fixtures.dart';

/// The amount sheet, against a food that states a package relationship
/// (spec R5, R6).
///
/// Two properties, and they pull in opposite directions, which is why the
/// sheet is easy to get wrong:
///
///  * what it *shows* is derived — the same settled amounts and the same
///    units the list and the export show, so the sheet cannot be the one
///    surface reading a shopping line differently;
///  * what it *saves* is stored — a field nobody typed in hands back exactly
///    the quantity that was already there, kind, unit and full precision, so
///    opening the sheet and pressing Done changes nothing at all.
void main() {
  /// A food that can say nothing about how its volume relates to its weight.
  Food plainFood() => const Food(
    id: 'test-plain',
    name: 'Test pantry item',
    source: FoodSource.manual,
    servingOptions: <ServingOption>[],
  );

  ShoppingLine cornLine({
    required List<Quantity> planned,
    Quantity? wanted,
    Quantity? onHand,
  }) => ShoppingLine(
    key: 'test-package-corn',
    name: 'Frozen corn',
    planned: planned,
    wanted: wanted,
    onHand: onHand,
    foodId: 'test-package-corn',
  );

  /// Opens the sheet over a bare host and hands back a reader for whatever
  /// it finally returns — which is the only place the saved line exists.
  Future<ShoppingLine? Function()> openSheet(
    WidgetTester tester,
    ShoppingLine line, {
    Food? food,
  }) async {
    ShoppingLine? returned;
    await tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  returned = await showShoppingAmountSheet(
                    context,
                    line,
                    food: food,
                  );
                },
                child: const Text('Edit amount'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit amount'));
    await tester.pumpAndSettle();
    return () => returned;
  }

  List<TextField> fields(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).toList();

  String buyText(WidgetTester tester) => fields(tester)[0].controller!.text;
  String haveText(WidgetTester tester) => fields(tester)[1].controller!.text;

  Future<void> pressDone(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('total needed and have show the live purchase calculation', (
    WidgetTester tester,
  ) async {
    final ShoppingLine? Function() result = await openSheet(
      tester,
      cornLine(planned: <Quantity>[Quantity.of(30, Units.ounce)]),
      food: packageCorn(),
    );

    expect(find.text('Total needed'), findsOneWidget);
    expect(find.text('Have at home'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '25');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.pump();
    expect(find.text('Buy 15 oz'), findsOneWidget);
    expect(find.text('2 × 10 oz'), findsOneWidget);
    expect(find.textContaining('Needed for meals: 30 oz'), findsOneWidget);
    await pressDone(tester);
    expect(result()!.wanted!.amountIn(Units.ounce), closeTo(25, 1e-9));
    expect(result()!.onHand!.amountIn(Units.ounce), closeTo(10, 1e-9));
  });

  testWidgets('a weight opens in the package unit rather than the ladder', (
    WidgetTester tester,
  ) async {
    // Thirty ounces of something sold in 10 oz bags is three bags. The
    // ladder on its own would promote it to 1.88 lb, which is the same
    // weight and a worse answer: nothing in a shop is measured that way,
    // and the list beside this sheet does not say it either.
    await openSheet(
      tester,
      cornLine(planned: <Quantity>[Quantity.of(30, Units.ounce)]),
      food: packageCorn(),
    );

    expect(buyText(tester), '30');
    expect(find.text('lb'), findsNothing);
    expect(find.text('oz'), findsNWidgets(2));
  });

  testWidgets('a volume ask reads through the package relationship', (
    WidgetTester tester,
  ) async {
    // Six cups of a food whose label states 10 oz and two 1-cup servings is
    // three packages, which is 30 oz. The sheet reads the settled total
    // rather than the raw ask, so it agrees with the row behind it.
    await openSheet(
      tester,
      cornLine(planned: <Quantity>[Quantity.of(6, Units.cup)]),
      food: packageCorn(),
    );

    expect(buyText(tester), '30');
    expect(find.text('Needed for meals: 30 oz'), findsOneWidget);
    expect(find.text('Buy 30 oz'), findsOneWidget);
    expect(find.text('cup'), findsNothing);
  });

  testWidgets('opening and closing keeps the chosen amount exactly', (
    WidgetTester tester,
  ) async {
    // The whole reason to be careful here. The chosen 14.5 oz is a decision
    // somebody made, and the cupboard cup is a fact they recorded; the sheet
    // may show either of them converted, but pressing Done without typing is
    // not a new claim about either.
    final Quantity chosen = Quantity.of(14.5, Units.ounce);
    final Quantity cupboard = Quantity.of(1, Units.cup);
    final ShoppingLine? Function() result = await openSheet(
      tester,
      cornLine(
        planned: <Quantity>[Quantity.of(30, Units.ounce)],
        wanted: chosen,
        onHand: cupboard,
      ),
      food: packageCorn(),
    );

    await pressDone(tester);

    final ShoppingLine saved = result()!;
    expect(saved.wanted!.canonicalAmount, chosen.canonicalAmount);
    expect(saved.wanted!.preferredUnit, Units.ounce);
    expect(saved.onHand!.kind, UnitKind.volume);
    expect(saved.onHand!.preferredUnit, Units.cup);
    expect(saved.onHand!.canonicalAmount, cupboard.canonicalAmount);
  });

  testWidgets('and a line with no chosen amount still has none', (
    WidgetTester tester,
  ) async {
    final ShoppingLine? Function() result = await openSheet(
      tester,
      cornLine(planned: <Quantity>[Quantity.of(30, Units.ounce)]),
      food: packageCorn(),
    );

    await pressDone(tester);

    expect(result()!.wanted, isNull);
    expect(result()!.isEdited, isFalse);
  });

  testWidgets('typing what is in the cupboard changes nothing else', (
    WidgetTester tester,
  ) async {
    final ShoppingLine? Function() result = await openSheet(
      tester,
      cornLine(planned: <Quantity>[Quantity.of(30, Units.ounce)]),
      food: packageCorn(),
    );

    await tester.enterText(find.byType(TextField).at(1), '10');
    await pressDone(tester);

    final ShoppingLine saved = result()!;
    expect(saved.onHand!.amountIn(Units.ounce), closeTo(10, 1e-9));
    expect(saved.wanted, isNull);
    expect(saved.planned.single.amountIn(Units.ounce), closeTo(30, 1e-9));
  });

  testWidgets('no relationship means no invented conversion', (
    WidgetTester tester,
  ) async {
    // A need in cups and a cupboard in ounces, and a food that has never
    // said how the two relate. Each field stands in its own unit; nothing
    // here asks a weight how many cups it is, and nothing throws for asking.
    await openSheet(
      tester,
      ShoppingLine(
        key: 'test-plain',
        name: 'Test pantry item',
        planned: <Quantity>[Quantity.of(6, Units.cup)],
        onHand: Quantity.of(8, Units.ounce),
        foodId: 'test-plain',
      ),
      food: plainFood(),
    );

    expect(buyText(tester), '6');
    expect(haveText(tester), '8');
    expect(find.text('cup'), findsOneWidget);
    expect(find.text('oz'), findsOneWidget);
    expect(find.text('Buy 6 cups'), findsOneWidget);
    expect(find.textContaining('has not been subtracted'), findsOneWidget);
  });

  testWidgets('mixed-unit needs stay separate until a total is set', (
    WidgetTester tester,
  ) async {
    final ShoppingLine mixed = ShoppingLine(
      key: 'test-plain',
      name: 'Test pantry item',
      planned: <Quantity>[
        Quantity.of(6, Units.cup),
        Quantity.of(8, Units.ounce),
      ],
    );
    final ShoppingLine? Function() result = await openSheet(
      tester,
      mixed,
      food: plainFood(),
    );
    expect(find.text('Needed for meals: 6 cups + 8 oz'), findsOneWidget);
    expect(find.text('Buy: 6 cups + 8 oz'), findsOneWidget);
    expect(find.textContaining('no known conversion'), findsOneWidget);
    await pressDone(tester);
    expect(result(), mixed);
  });

  testWidgets(
    'a manual total overrides mixed units without rewriting the asks',
    (WidgetTester tester) async {
      final ShoppingLine mixed = ShoppingLine(
        key: 'test-plain',
        name: 'Test pantry item',
        planned: <Quantity>[
          Quantity.of(6, Units.cup),
          Quantity.of(8, Units.ounce),
        ],
      );
      final ShoppingLine? Function() result = await openSheet(
        tester,
        mixed,
        food: plainFood(),
      );
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.enterText(find.byType(TextField).last, '1');
      await tester.pump();
      expect(find.text('Buy 2 cups'), findsOneWidget);
      await pressDone(tester);
      expect(result()!.planned, mixed.planned);
      expect(result()!.wanted!.amountIn(Units.cup), closeTo(3, 1e-9));
    },
  );

  testWidgets(
    'unknown package facts show an amount without inventing a pack count',
    (WidgetTester tester) async {
      await openSheet(
        tester,
        ShoppingLine(
          key: 'plain',
          name: 'Test pantry item',
          planned: <Quantity>[Quantity.of(3, Units.cup)],
        ),
        food: plainFood(),
      );
      expect(find.text('Buy 3 cups'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
    },
  );

  testWidgets(
    'a blank manual item stays unquantified until the user enters a total',
    (WidgetTester tester) async {
      final ShoppingLine? Function() result = await openSheet(
        tester,
        ShoppingLine.manual(key: 'towels', name: 'Paper towels'),
      );
      expect(find.text('Needed: no amount set.'), findsOneWidget);
      expect(find.text('Buy: amount not set'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.enterText(find.byType(TextField).last, '1');
      await tester.pump();
      expect(find.text('Buy 2'), findsOneWidget);
      await pressDone(tester);
      expect(result()!.toBuy!.canonicalAmount, 2);
    },
  );

  testWidgets('display rounding never changes untouched stored precision', (
    WidgetTester tester,
  ) async {
    final ShoppingLine exact = cornLine(
      planned: <Quantity>[Quantity.of(30, Units.ounce)],
      wanted: Quantity.of(14.5123456789, Units.ounce),
      onHand: Quantity.of(1.123456789, Units.cup),
    );
    final ShoppingLine? Function() result = await openSheet(
      tester,
      exact,
      food: packageCorn(),
    );
    await pressDone(tester);
    expect(result(), exact);
  });

  testWidgets(
    '3x text and the keyboard leave the equation and Done reachable',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final ShoppingLine? Function() result = await openSheet(
        tester,
        cornLine(planned: <Quantity>[Quantity.of(30, Units.ounce)]),
        food: packageCorn(),
      );
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '25');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Buy 15 oz'));
      expect(find.text('Buy 15 oz').hitTestable(), findsOneWidget);
      expect(find.text('2 × 10 oz'), findsOneWidget);
      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Done').hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Done')).height,
        greaterThanOrEqualTo(44),
      );
      await pressDone(tester);
      expect(result()!.wanted!.amountIn(Units.ounce), closeTo(25, 1e-9));
      expect(tester.takeException(), isNull);
    },
  );
}
