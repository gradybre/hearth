import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/data/adapters/walmart_export.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_export_sheet.dart';

class _DelayedExport implements ShoppingExportAdapter {
  final Completer<void> ready = Completer<void>();
  int calls = 0;
  @override
  String get displayName => 'Walmart';
  @override
  ShoppingExportKind get kind => ShoppingExportKind.deepLink;
  @override
  Future<ShoppingExportResult> export(List<ShoppingExportItem> items) async {
    calls++;
    await ready.future;
    return const WalmartExport().export(items);
  }
}

void main() {
  late List<MethodCall> sent;
  setUp(() {
    sent = <MethodCall>[];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') sent.add(call);
      if (call.method == 'Clipboard.hasStrings') {
        return <String, bool>{'value': false};
      }
      return null;
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

  ShoppingLine line({
    String key = 'sauce',
    double grams = 600,
    bool unresolved = false,
  }) => ShoppingLine(
    key: key,
    foodId: key,
    name: key,
    planned: <Quantity>[Quantity.of(grams, Units.gram)],
    hasUnquantified: unresolved,
  );
  Food food({
    String key = 'sauce',
    double? pack = 400,
    String product = '123456789',
    DateTime? updatedAt,
  }) => Food(
    id: key,
    householdId: 'home',
    name: 'Saved $key',
    brand: 'Kitchen brand',
    source: FoodSource.manual,
    servingOptions: const <ServingOption>[],
    packSize: pack == null ? null : Quantity.of(pack, Units.gram),
    walmartItemId: product,
    updatedAt: updatedAt,
  );
  ShoppingExportSource source({
    double grams = 600,
    double? pack = 400,
    String product = '123456789',
    DateTime? updatedAt,
  }) => ShoppingExportSource(
    lines: <ShoppingLine>[line(grams: grams)],
    foods: <String, Food>{
      'sauce': food(pack: pack, product: product, updatedAt: updatedAt),
    },
  );

  Future<void> open(
    WidgetTester tester,
    ShoppingExportSource initial, {
    Future<ShoppingExportSource?> Function()? readCurrent,
    bool Function()? isCurrent,
    ShoppingExportAdapter adapter = const WalmartExport(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => showShoppingExportSheet(
                context,
                initial.lines,
                foods: initial.foods,
                adapter: adapter,
                readCurrent: readCurrent,
                isCurrent: isCurrent,
              ),
              child: const Text('Export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('repeated review choices name the item to assistive readers', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await open(
        tester,
        ShoppingExportSource(
          lines: <ShoppingLine>[
            line(grams: 12000),
            line(key: 'rice', grams: 12000),
          ],
          foods: <String, Food>{
            'sauce': food(),
            'rice': food(key: 'rice'),
          },
        ),
      );
      for (int index = 0; index < 2; index++) {
        final String item = index == 0 ? 'sauce' : 'rice';
        await tester.ensureVisible(
          find
              .widgetWithText(CheckboxListTile, 'I reviewed this limited count')
              .at(index),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('I reviewed the limited count for $item'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.widgetWithText(CheckboxListTile, 'Skip for this trip').at(index),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Skip $item for this trip'),
          findsOneWidget,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  Finder field([String key = 'sauce']) =>
      find.byKey(ValueKey<String>('cart-count-$key'));
  bool canReview(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review at Walmart'),
          )
          .onPressed !=
      null;
  Uri launched() => Uri.parse(
    (sent.single.arguments as Map<Object?, Object?>)['url']! as String,
  );

  testWidgets(
    'saved product and known purchase arithmetic precede the handoff',
    (WidgetTester tester) async {
      await open(tester, source());
      expect(
        find.text('Saved product: Saved sauce · Kitchen brand'),
        findsOneWidget,
      );
      expect(find.text('Walmart item 123456789'), findsOneWidget);
      expect(find.text('Need 600 g → 2 × 400 g packs'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, '2');
      expect(sent, isEmpty);
      await tap(tester, 'Review at Walmart');
      expect(launched().queryParameters['items'], '123456789_2');
    },
  );

  testWidgets(
    'unknown conversion requires an explicit count, not a fallback one',
    (WidgetTester tester) async {
      await open(tester, source(pack: null));
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(canReview(tester), isFalse);
      expect(sent, isEmpty);
      await tester.enterText(field(), '3');
      await tester.pump();
      expect(canReview(tester), isTrue);
      await tap(tester, 'Review at Walmart');
      expect(launched().queryParameters['items'], '123456789_3');
    },
  );

  testWidgets(
    'fractional pasted counts are invalid rather than silently multiplied',
    (WidgetTester tester) async {
      await open(tester, source());
      await tester.enterText(field(), '1.5');
      await tester.pump();
      expect(canReview(tester), isFalse);
      expect(find.text('Enter a whole number from 1 to 24.'), findsOneWidget);
      expect(sent, isEmpty);
    },
  );

  testWidgets('an unknown item can be skipped while the known item proceeds', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      ShoppingExportSource(
        lines: <ShoppingLine>[
          line(),
          line(key: 'rice'),
        ],
        foods: <String, Food>{
          'sauce': food(),
          'rice': food(key: 'rice', pack: null, product: '987654321'),
        },
      ),
    );
    expect(canReview(tester), isFalse);
    final Finder skip = find.byKey(const ValueKey<String>('cart-skip-rice'));
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.text('1 product in this handoff. 1 left out.'), findsOneWidget);
    await tap(tester, 'Review at Walmart');
    expect(launched().queryParameters['items'], '123456789_2');
  });

  testWidgets(
    'trip-only corrections disappear on reopening without changing the list',
    (WidgetTester tester) async {
      final ShoppingExportSource original = source();
      await open(tester, original);
      await tester.enterText(field(), '4');
      await tester.pump();
      await tap(tester, 'Review at Walmart');
      expect(launched().queryParameters['items'], '123456789_4');
      sent.clear();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, '2');
      expect(original.lines.single.checked, isFalse);
      expect(original.lines.single.planned.single.canonicalAmount, 600);
      expect(original.foods['sauce']!.packSize!.canonicalAmount, 400);
    },
  );

  testWidgets(
    'cap needs acknowledgement and count must stay between one and 24',
    (WidgetTester tester) async {
      await open(tester, source(grams: 10000, pack: 100));
      expect(tester.widget<TextField>(field()).controller!.text, '24');
      expect(canReview(tester), isFalse);
      expect(
        find.textContaining('suggested count was limited to 24'),
        findsOneWidget,
      );
      for (final String invalid in <String>[
        '0',
        '25',
        '-2',
        '100000000000000000000',
      ]) {
        await tester.ensureVisible(field());
        await tester.enterText(field(), invalid);
        await tester.pump();
        expect(canReview(tester), isFalse);
      }
      await tester.enterText(field(), '24');
      await tester.pump();
      await tap(tester, 'I reviewed this limited count');
      expect(canReview(tester), isTrue);
      await tap(tester, 'Review at Walmart');
      expect(launched().queryParameters['items'], '123456789_24');
    },
  );

  for (final String change in <String>[
    'quantity',
    'product',
    'pack',
    'checked',
    'removed',
  ]) {
    testWidgets(
      '$change changes reset held counts and require a new deliberate tap',
      (WidgetTester tester) async {
        ShoppingExportSource current = source();
        await open(
          tester,
          current,
          readCurrent: () async => current,
          isCurrent: () => true,
        );
        await tester.enterText(field(), '7');
        await tester.pump();
        current = switch (change) {
          'quantity' => source(grams: 1000),
          'product' => source(product: '987654321'),
          'pack' => source(pack: 200),
          'checked' => ShoppingExportSource(
            lines: <ShoppingLine>[line().ticked(true)],
            foods: current.foods,
          ),
          _ => ShoppingExportSource(lines: const <ShoppingLine>[]),
        };
        await tap(tester, 'Review at Walmart');
        expect(sent, isEmpty);
        expect(
          find.textContaining('Your trip-only choices were reset.'),
          findsOneWidget,
        );
        if (change == 'checked' || change == 'removed') {
          expect(field(), findsNothing);
        } else {
          expect(
            tester.widget<TextField>(field()).controller!.text,
            change == 'product' ? '2' : '3',
          );
          await tap(tester, 'Review at Walmart');
          expect(
            launched().queryParameters['items'],
            change == 'product' ? '987654321_2' : '123456789_3',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('timestamp-only refresh preserves the reviewed trip count', (
    WidgetTester tester,
  ) async {
    final ShoppingExportSource initial = source();
    await open(
      tester,
      initial,
      readCurrent: () async => source(updatedAt: DateTime(2026)),
      isCurrent: () => true,
    );
    await tester.enterText(field(), '7');
    await tester.pump();
    await tap(tester, 'Review at Walmart');
    expect(launched().queryParameters['items'], '123456789_7');
  });

  for (final String action in <String>[
    'Review at Walmart',
    'Copy the list',
    'Search Walmart',
  ]) {
    testWidgets(
      'identity expiry during $action preparation stops the platform call',
      (WidgetTester tester) async {
        final _DelayedExport adapter = _DelayedExport();
        bool current = true;
        await open(
          tester,
          source(),
          adapter: adapter,
          isCurrent: () => current,
          readCurrent: () async => source(),
        );
        await tap(tester, action);
        expect(adapter.calls, 1);
        current = false;
        adapter.ready.complete();
        await tester.pumpAndSettle();
        expect(sent, isEmpty);
        expect(find.textContaining('no longer current'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'a source change during adapter work cannot launch its old result',
    (WidgetTester tester) async {
      final _DelayedExport adapter = _DelayedExport();
      ShoppingExportSource current = source();
      await open(
        tester,
        current,
        adapter: adapter,
        isCurrent: () => true,
        readCurrent: () async => current,
      );
      await tap(tester, 'Review at Walmart');
      current = source(product: '987654321');
      adapter.ready.complete();
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(
        find.textContaining('Your trip-only choices were reset.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unavailable current data blocks the handoff and can be retried',
    (WidgetTester tester) async {
      ShoppingExportSource? current;
      await open(
        tester,
        source(),
        readCurrent: () async => current,
        isCurrent: () => true,
      );
      await tap(tester, 'Review at Walmart');
      expect(sent, isEmpty);
      expect(find.textContaining('could not be checked'), findsOneWidget);
      current = source();
      await tap(tester, 'Review at Walmart');
      expect(sent, hasLength(1));
    },
  );

  testWidgets(
    'unresolved and unmatched rows stay outside the basket and in copy',
    (WidgetTester tester) async {
      await open(
        tester,
        ShoppingExportSource(
          lines: <ShoppingLine>[
            line(),
            line(key: 'rice', unresolved: true),
            line(key: 'coffee'),
          ],
          foods: <String, Food>{
            'sauce': food(),
            'rice': food(key: 'rice', product: '987654321'),
          },
        ),
      );
      expect(field('rice'), findsNothing);
      expect(field('coffee'), findsNothing);
      expect(
        find.text('1 product in this handoff. 2 left out.'),
        findsOneWidget,
      );
      await tap(tester, 'Copy the list');
      expect(sent.single.method, 'Clipboard.setData');
      final String text =
          (sent.single.arguments as Map<Object?, Object?>)['text']! as String;
      expect(text, contains('sauce'));
      expect(text, contains('amount not set rice'));
      expect(text, contains('coffee'));
    },
  );

  testWidgets('two rows for one product show and enforce their combined cap', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      ShoppingExportSource(
        lines: <ShoppingLine>[
          line(),
          line(key: 'rice'),
        ],
        foods: <String, Food>{
          'sauce': food(),
          'rice': food(key: 'rice'),
        },
      ),
    );
    await tester.ensureVisible(field());
    await tester.enterText(field(), '13');
    await tester.pump();
    await tester.ensureVisible(field('rice'));
    await tester.enterText(field('rice'), '13');
    await tester.pump();
    expect(canReview(tester), isFalse);
    expect(find.textContaining('total 26 packages'), findsOneWidget);
    expect(sent, isEmpty);
    await tester.enterText(field('rice'), '11');
    await tester.pump();
    expect(canReview(tester), isTrue);
    expect(find.text('1 product in this handoff. 0 left out.'), findsOneWidget);
    await tap(tester, 'Review at Walmart');
    expect(launched().queryParameters['items'], '123456789_24');
  });

  testWidgets(
    'changed-source explanation is visible after the held review tap',
    (WidgetTester tester) async {
      ShoppingExportSource current = source();
      await open(
        tester,
        current,
        readCurrent: () async => current,
        isCurrent: () => true,
      );
      current = source(product: '987654321');
      await tap(tester, 'Review at Walmart');
      expect(sent, isEmpty);
      expect(
        find.textContaining('Your trip-only choices were reset.').hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('changed-source explanation is reachable at large text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    ShoppingExportSource current = source();
    await open(
      tester,
      current,
      readCurrent: () async => current,
      isCurrent: () => true,
    );
    current = source(product: '987654321');
    await tap(tester, 'Review at Walmart');
    expect(sent, isEmpty);
    expect(
      find.textContaining('Your trip-only choices were reset.').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('closing a pending review prevents a late platform handoff', (
    WidgetTester tester,
  ) async {
    final _DelayedExport adapter = _DelayedExport();
    await open(tester, source(), adapter: adapter);
    await tap(tester, 'Review at Walmart');
    Navigator.of(tester.element(find.text('Review at Walmart'))).pop();
    await tester.pumpAndSettle();
    adapter.ready.complete();
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated taps during preparation produce one platform handoff', (
    WidgetTester tester,
  ) async {
    final _DelayedExport adapter = _DelayedExport();
    await open(tester, source(), adapter: adapter);
    await tap(tester, 'Review at Walmart');
    await tap(tester, 'Review at Walmart');
    expect(adapter.calls, 1);
    expect(sent, isEmpty);
    adapter.ready.complete();
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
  });

  testWidgets(
    'current-source failure is visible without leaking or dismissing',
    (WidgetTester tester) async {
      await open(
        tester,
        source(),
        readCurrent: () async => throw StateError('synthetic read failure'),
        isCurrent: () => true,
      );
      await tap(tester, 'Review at Walmart');
      expect(sent, isEmpty);
      expect(
        find.textContaining('handoff could not be prepared'),
        findsOneWidget,
      );
      expect(find.text('Review at Walmart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trip edits and Skip never rewrite the full copied shopping list',
    (WidgetTester tester) async {
      await open(tester, source());
      await tester.enterText(field(), '7');
      await tester.pump();
      await tap(tester, 'Skip for this trip');
      await tap(tester, 'Copy the list');
      expect(sent.single.method, 'Clipboard.setData');
      expect(
        (sent.single.arguments as Map<Object?, Object?>)['text'],
        '- 2 × 400 g sauce (needs 600 g)',
      );
    },
  );

  for (final double scale in <double>[1, 3]) {
    testWidgets(
      'narrow review has reachable quantity controls and actions at ${scale}x',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await open(tester, source());
        await tester.ensureVisible(field());
        await tester.pumpAndSettle();
        await tester.enterText(field(), '3');
        await tester.pumpAndSettle();
        for (final Element text
            in find
                .descendant(of: field(), matching: find.byType(RichText))
                .evaluate()) {
          expect(
            (text.renderObject! as RenderParagraph).didExceedMaxLines,
            isFalse,
            reason:
                'The package-count field text must be readable: ${(text.renderObject! as RenderParagraph).text.toPlainText()}',
          );
        }
        expect(tester.takeException(), isNull);
        await tap(tester, 'Review at Walmart');
        expect(launched().queryParameters['items'], '123456789_3');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
