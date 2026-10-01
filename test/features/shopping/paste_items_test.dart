import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/shopping/manual_addition.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/paste_items_sheet.dart';

class _Result {
  List<ManualListItem>? items;
  bool completed = false;
}

Future<_Result> _open(
  WidgetTester tester, {
  List<ShoppingLine> current = const <ShoppingLine>[],
  Future<void> Function(List<ManualListItem>)? onCommit,
  String? Function()? unavailableReason,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final _Result result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? HearthTheme.dark()
          : HearthTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => FilledButton(
            onPressed: () async {
              result.items = await showPasteItemsSheet(
                context,
                currentLines: current,
                onCommit: onCommit,
                unavailableReason: unavailableReason,
              );
              result.completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  bool menu = false,
}) async {
  await tester.pumpAndSettle();
  final Finder scrollable = menu
      ? find.byType(Scrollable).last
      : find
            .descendant(
              of: _key('paste-items-scroll'),
              matching: find.byType(Scrollable),
            )
            .first;
  if (target.evaluate().isEmpty) {
    if (menu) {
      await tester.drag(scrollable, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        target,
        120,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    } else {
      // At 3× with the keyboard open, the pasted field's selection handle can
      // cover the viewport's centre. Swipe the sheet's clear padding instead.
      Future<void> swipe(double distance) async {
        final Rect bounds = tester.getRect(scrollable);
        await tester.dragFrom(
          Offset(bounds.left + 8, bounds.center.dy),
          Offset(0, distance),
        );
        await tester.pumpAndSettle();
      }

      await swipe(3000);
      for (
        int attempt = 0;
        target.evaluate().isEmpty && attempt < 80;
        attempt++
      ) {
        await swipe(-120);
      }
    }
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String key) async {
  await _reveal(tester, _key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester, String text) async {
  await _reveal(tester, _key('paste-items-input'));
  await tester.enterText(_key('paste-items-input'), text);
  await tester.pumpAndSettle();
  await _press(tester, 'paste-items-review');
}

Future<void> _chooseUnit(WidgetTester tester, String label) async {
  await _reveal(tester, find.text(label), menu: true);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'paste is reviewed before any write and ambiguous wording stays literal',
    (WidgetTester tester) async {
      int commits = 0;
      final _Result result = await _open(
        tester,
        onCommit: (_) async => commits++,
      );
      await _review(tester, '  Coffee 500g\n\n Eggs 12items\n  Paper towels  ');
      expect(commits, 0);
      expect(
        tester.widget<TextField>(_key('paste-name-0')).controller!.text,
        'Coffee 500g',
      );
      expect(
        tester.widget<TextField>(_key('paste-name-1')).controller!.text,
        'Eggs 12items',
      );
      expect(find.text('3 ready to add · 0 will be skipped'), findsOneWidget);
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result.completed, isTrue);
      expect(result.items, isNull);
      expect(commits, 0);
    },
  );

  testWidgets(
    'review can rename, remove, and set a fractional quantity before saving',
    (WidgetTester tester) async {
      final _Result result = await _open(tester);
      await _review(tester, 'Coffee\nEggs\nPaper towels');
      await tester.enterText(_key('paste-name-0'), 'Ground coffee');
      await _press(tester, 'paste-add-amount-0');
      await tester.enterText(_key('paste-0-amount'), '1 1/2');
      await _press(tester, 'paste-0-unit');
      await _chooseUnit(tester, 'lb');
      await _press(tester, 'paste-remove-1');
      await _press(tester, 'paste-items-save');
      expect(result.items!.map((ManualListItem item) => item.name), <String>[
        'Ground coffee',
        'Paper towels',
      ]);
      expect(result.items!.first.quantity!.amountIn(Units.pound), 1.5);
      expect(result.items!.first.quantity!.preferredUnit, Units.pound);
      expect(result.items!.last.quantity, isNull);
    },
  );

  testWidgets('duplicate labels update when a row is renamed or removed', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      current: <ShoppingLine>[
        const ShoppingLine(
          key: 'food:milk',
          name: 'MILK',
          planned: [],
          foodId: 'milk',
        ),
      ],
    );
    await _review(tester, 'Milk\ncoffee\n Coffee ');
    expect(find.text('Already on the list · will skip'), findsOneWidget);
    await _reveal(tester, _key('paste-name-2'));
    expect(find.text('Repeated in this paste · will skip'), findsOneWidget);
    await tester.enterText(_key('paste-name-2'), 'Tea');
    await tester.pumpAndSettle();
    expect(find.text('Repeated in this paste · will skip'), findsNothing);
    await _reveal(tester, find.text('2 ready to add · 1 will be skipped'));
    expect(find.text('2 ready to add · 1 will be skipped'), findsOneWidget);
    await _press(tester, 'paste-remove-0');
    expect(find.text('Already on the list · will skip'), findsNothing);
    await _reveal(tester, find.text('2 ready to add · 0 will be skipped'));
    expect(find.text('2 ready to add · 0 will be skipped'), findsOneWidget);
  });

  testWidgets(
    'blank names and invalid amounts cannot be saved; blank amount can',
    (WidgetTester tester) async {
      final _Result result = await _open(tester);
      await _review(tester, 'Coffee');
      await _press(tester, 'paste-add-amount-0');
      for (final String invalid in <String>[
        '0',
        '-1/2',
        'NaN',
        'Infinity',
        'wrong',
      ]) {
        await tester.enterText(_key('paste-0-amount'), invalid);
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(_key('paste-items-save')).onPressed,
          isNull,
          reason: invalid,
        );
      }
      await tester.enterText(_key('paste-0-amount'), '');
      await tester.enterText(_key('paste-name-0'), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('paste-items-save')).onPressed,
        isNull,
      );
      await tester.enterText(_key('paste-name-0'), 'Coffee');
      await _press(tester, 'paste-items-save');
      expect(result.items!.single.quantity, isNull);
    },
  );

  testWidgets('failed save preserves edited rows, amount, and unit for retry', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    List<ManualListItem>? saved;
    await _open(
      tester,
      onCommit: (List<ManualListItem> items) async {
        attempts++;
        if (attempts == 1) throw StateError('write failed');
        saved = items;
      },
    );
    await _review(tester, 'Coffee\nEggs');
    await tester.enterText(_key('paste-name-0'), 'Decaf coffee');
    await _press(tester, 'paste-add-amount-0');
    await tester.enterText(_key('paste-0-amount'), '500');
    await _press(tester, 'paste-0-unit');
    await _chooseUnit(tester, 'g');
    await _press(tester, 'paste-remove-1');
    await _press(tester, 'paste-items-save');
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('paste-name-0')).controller!.text,
      'Decaf coffee',
    );
    expect(
      tester.widget<TextField>(_key('paste-0-amount')).controller!.text,
      '500',
    );
    await _press(tester, 'paste-items-save');
    expect(attempts, 2);
    expect(saved!.single.name, 'Decaf coffee');
    expect(saved!.single.quantity!.amountIn(Units.gram), 500);
    expect(saved!.single.quantity!.preferredUnit, Units.gram);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated save presses produce one commit and completion can outlive the sheet',
    (WidgetTester tester) async {
      final Completer<void> pending = Completer<void>();
      int calls = 0;
      await _open(
        tester,
        onCommit: (_) {
          calls++;
          return pending.future;
        },
      );
      await _review(tester, 'Coffee');
      await _reveal(tester, _key('paste-items-save'));
      await tester.tap(_key('paste-items-save'));
      await tester.tap(_key('paste-items-save'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(_key('paste-items-save')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changed identity expires a held retry without a second commit', (
    WidgetTester tester,
  ) async {
    bool current = true;
    int calls = 0;
    await _open(
      tester,
      unavailableReason: () => current ? null : ShoppingAdditionExpired.message,
      onCommit: (_) async {
        calls++;
        throw StateError('write failed');
      },
    );
    await _review(tester, 'Coffee');
    await _press(tester, 'paste-items-save');
    current = false;
    await _press(tester, 'paste-items-save');
    expect(calls, 1);
    expect(find.text(ShoppingAdditionExpired.message), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('paste-items-save')).onPressed,
      isNull,
    );
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'review controls work at 320px / 3× with keyboard in ${brightness.name}',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.reset);
        final _Result result = await _open(
          tester,
          textScale: 3,
          brightness: brightness,
        );
        await _review(tester, 'Coffee');
        await _press(tester, 'paste-add-amount-0');
        await _reveal(tester, _key('paste-0-amount'));
        await tester.enterText(_key('paste-0-amount'), '12');
        await _press(tester, 'paste-items-save');
        expect(result.items!.single.quantity!.canonicalAmount, 12);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
