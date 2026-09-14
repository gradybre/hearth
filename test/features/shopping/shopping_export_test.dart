import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_export_sheet.dart';

/// The hand-off itself (spec §5.7, CLAUDE.md rule 4).
///
/// Two properties, and the second is the load-bearing one: the copy says what
/// the list said, and *nothing at all* leaves the app until somebody presses
/// something. The sheet is a hand-off rather than a review because the list
/// behind it is editable up to this moment — which only holds if opening the
/// sheet is inert.
void main() {
  /// Every call the sheet makes to the OS: the clipboard and the launcher.
  late List<MethodCall> sent;

  setUp(() {
    sent = <MethodCall>[];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method.startsWith('Clipboard.')) sent.add(call);
      return call.method == 'Clipboard.getData' ? null : null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        sent.add(call);
        return true;
      },
    );
  });

  tearDown(() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  final Quantity jar = Quantity.of(24, Units.ounce);

  Food sauce({Quantity? pack}) => Food(
    id: 'f-sauce',
    householdId: 'household-1',
    name: 'Marinara sauce',
    source: FoodSource.manual,
    servingOptions: const <ServingOption>[],
    packSize: pack,
  );

  ShoppingLine sauceLine(Quantity planned) => ShoppingLine(
    key: 'f-sauce',
    name: 'marinara sauce',
    planned: <Quantity>[planned],
    foodId: 'f-sauce',
  );

  Future<void> openSheet(
    WidgetTester tester, {
    required List<ShoppingLine> lines,
    Map<String, Food> foods = const <String, Food>{},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showShoppingExportSheet(context, lines, foods: foods),
                child: const Text('Share or export'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share or export'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing leaves the app just because the sheet opened', (
    WidgetTester tester,
  ) async {
    // Rule 4. Opening the hand-off is not the hand-off — no clipboard write,
    // no link handed to the OS, until a button is pressed.
    await openSheet(
      tester,
      lines: <ShoppingLine>[sauceLine(Quantity.of(64, Units.ounce))],
      foods: <String, Food>{'f-sauce': sauce(pack: jar)},
    );

    expect(find.text('Copy the list'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('and the copied list counts jars, not pounds', (
    WidgetTester tester,
  ) async {
    // What the screen behind this sheet has said since b3ec3c3, now in the
    // text somebody actually reads in a shop. Sixty-four ounces of a sauce
    // sold in 24-ounce jars is three jars, and the eight ounces over are
    // said rather than rounded away in silence.
    await openSheet(
      tester,
      lines: <ShoppingLine>[sauceLine(Quantity.of(64, Units.ounce))],
      foods: <String, Food>{'f-sauce': sauce(pack: jar)},
    );

    await tester.tap(find.text('Copy the list'));
    await tester.pumpAndSettle();

    expect(sent.single.method, 'Clipboard.setData');
    expect(
      (sent.single.arguments as Map<Object?, Object?>)['text'],
      '- 3 × 24 oz marinara sauce (needs 64 oz)',
    );
  });

  testWidgets('a food with no pack size is still copied by weight', (
    WidgetTester tester,
  ) async {
    // The pack count only ever replaces an answer that was already right.
    await openSheet(
      tester,
      lines: <ShoppingLine>[sauceLine(Quantity.of(2, Units.pound))],
      foods: <String, Food>{'f-sauce': sauce()},
    );

    await tester.tap(find.text('Copy the list'));
    await tester.pumpAndSettle();

    expect(
      (sent.single.arguments as Map<Object?, Object?>)['text'],
      '- 2 lb marinara sauce',
    );
  });
}
