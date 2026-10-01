import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/shopping/manual_addition.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_screen.dart';

import '../../support/app_harness.dart';

class _RecordingShopping extends ShoppingRepository {
  _RecordingShopping(HearthDatabase db)
    : super(
        database: db,
        store: ShoppingStore(db),
        queue: PendingWriteStore(db),
        householdId: 'local-household',
      );

  int failures = 0;
  Completer<void>? pending;
  final List<List<ManualListItem>> attempts = <List<ManualListItem>>[];
  List<ManualListItem> beforeSave = const <ManualListItem>[];

  @override
  Future<ManualAdditionResult> addManualItems(
    List<ManualListItem> items,
  ) async {
    attempts.add(items);
    if (failures > 0) {
      failures--;
      throw StateError('A recoverable write failure');
    }
    await pending?.future;
    if (beforeSave.isNotEmpty) {
      await super.addManualItems(beforeSave);
      beforeSave = const <ManualListItem>[];
    }
    return super.addManualItems(items);
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<_RecordingShopping> _open(
  WidgetTester tester, {
  int failures = 0,
  List<Object> extraOverrides = const <Object>[],
  List<ShoppingLine> lines = const <ShoppingLine>[],
}) async {
  late _RecordingShopping shopping;
  await pumpHearthApp(
    tester,
    shoppingLines: lines,
    extraOverrides: <Object>[
      ...extraOverrides,
      shoppingRepositoryProvider.overrideWith((Ref ref) {
        shopping = _RecordingShopping(ref.read(databaseProvider))
          ..failures = failures;
        return shopping;
      }),
    ],
  );
  await tester.tap(find.text('Shopping').last);
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.text('Add item').last);
  await pumpFrames(tester, frames: 12);
  return shopping;
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  bool menu = false,
}) async {
  await pumpFrames(tester);
  final String sheet = _key('paste-items-scroll').evaluate().isNotEmpty
      ? 'paste-items-scroll'
      : 'add-to-list-scroll';
  final Finder scrollable = menu
      ? find.byType(Scrollable).last
      : find
            .descendant(of: _key(sheet), matching: find.byType(Scrollable))
            .first;
  if (target.evaluate().isEmpty) {
    await tester.drag(scrollable, const Offset(0, 3000));
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: scrollable,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(target);
  await pumpFrames(tester);
}

Future<void> _press(WidgetTester tester, String key) async {
  await _reveal(tester, _key(key));
  await tester.tap(_key(key));
  await pumpFrames(tester, frames: 16);
}

Future<void> _paste(WidgetTester tester, String text) async {
  await _press(tester, 'paste-items-open');
  await tester.enterText(_key('paste-items-input'), text);
  await pumpFrames(tester);
  await _press(tester, 'paste-items-review');
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ShoppingScreen)));

void main() {
  testWidgets('a failed manual save keeps the typed name available to retry', (
    WidgetTester tester,
  ) async {
    // Regression: previously the sheet popped first, then replace threw and
    // the name had already been discarded. This test failed before the fix.
    final _RecordingShopping shopping = await _open(tester, failures: 1);
    await tester.enterText(_key('manual-item-name'), 'Coffee');
    await pumpFrames(tester);
    await _press(tester, 'manual-item-add');
    expect(find.widgetWithText(TextField, 'Coffee'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(shopping.attempts, hasLength(1));
    await _press(tester, 'manual-item-add');
    expect(shopping.attempts, hasLength(2));
    final ShoppingListSnapshot? saved = await shopping.current();
    expect(saved!.lines.single.name, 'Coffee');
    expect(saved.lines.single.planned, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial manual quantity saves current fractional text without keyboard Done',
    (WidgetTester tester) async {
      final _RecordingShopping shopping = await _open(tester);
      await tester.enterText(_key('manual-item-name'), 'Coffee');
      await _press(tester, 'manual-item-add-amount');
      await tester.enterText(_key('manual-item-amount'), '1 1/2');
      await _press(tester, 'manual-item-unit');
      await _reveal(tester, find.text('lb'), menu: true);
      await tester.tap(find.text('lb'));
      await pumpFrames(tester);
      await tester.enterText(_key('manual-item-amount'), '1/2');
      await _press(tester, 'manual-item-add');
      final ShoppingLine line = (await shopping.current())!.lines.single;
      expect(line.name, 'Coffee');
      expect(line.planned.single.amountIn(Units.pound), 0.5);
      expect(line.planned.single.preferredUnit, Units.pound);
      expect(line.isManual, isTrue);
    },
  );

  testWidgets(
    'invalid manual quantity blocks add and clearing it restores a quick unquantified item',
    (WidgetTester tester) async {
      final _RecordingShopping shopping = await _open(tester);
      await tester.enterText(_key('manual-item-name'), 'Paper towels');
      await _press(tester, 'manual-item-add-amount');
      for (final String invalid in <String>[
        '0',
        '-1',
        'NaN',
        'Infinity',
        '1/0',
      ]) {
        await tester.enterText(_key('manual-item-amount'), invalid);
        await pumpFrames(tester);
        expect(
          tester.widget<ListTile>(_key('manual-item-add')).onTap,
          isNull,
          reason: invalid,
        );
      }
      expect(shopping.attempts, isEmpty);
      await tester.enterText(_key('manual-item-amount'), '');
      await _press(tester, 'manual-item-add');
      expect((await shopping.current())!.lines.single.planned, isEmpty);
    },
  );

  testWidgets(
    'batch save skips repeated and food-backed duplicates without changing existing rows',
    (WidgetTester tester) async {
      final ShoppingLine milk = ShoppingLine(
        key: 'food:milk',
        name: 'Milk',
        planned: <Quantity>[Quantity.of(2, Units.litre)],
        foodId: 'milk',
        checked: true,
        storeTag: 'Market',
      );
      final _RecordingShopping shopping = await _open(
        tester,
        lines: <ShoppingLine>[milk],
      );
      await _paste(tester, 'Milk\nCoffee\n coffee \nEggs');
      await _press(tester, 'paste-items-save');
      final List<ShoppingLine> saved = (await shopping.current())!.lines;
      expect(saved.map((ShoppingLine line) => line.name), <String>[
        'Milk',
        'Coffee',
        'Eggs',
      ]);
      final ShoppingLine existing = saved.first;
      expect(existing.planned.single.amountIn(Units.litre), 2);
      expect(existing.checked, isTrue);
      expect(existing.storeTag, 'Market');
      expect(find.text('Added 2; skipped 2.'), findsOneWidget);
    },
  );

  testWidgets(
    'an item arriving after review is skipped at commit and reported',
    (WidgetTester tester) async {
      final _RecordingShopping shopping = await _open(tester);
      await _paste(tester, 'Coffee\nEggs');
      expect(find.text('2 ready to add · 0 will be skipped'), findsOneWidget);
      shopping.beforeSave = <ManualListItem>[
        ManualListItem(name: 'Coffee', quantity: Quantity.of(500, Units.gram)),
      ];
      await _press(tester, 'paste-items-save');
      final List<ShoppingLine> saved = (await shopping.current())!.lines;
      expect(saved, hasLength(2));
      expect(saved.first.planned.single.amountIn(Units.gram), 500);
      expect(find.text('Added 1; skipped 1.'), findsOneWidget);
    },
  );

  testWidgets(
    'failed batch save keeps the edited review and succeeds on retry',
    (WidgetTester tester) async {
      final _RecordingShopping shopping = await _open(tester, failures: 1);
      await _paste(tester, 'Coffee\nEggs');
      await tester.enterText(_key('paste-name-0'), 'Decaf coffee');
      await _press(tester, 'paste-remove-1');
      await _press(tester, 'paste-items-save');
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester.widget<TextField>(_key('paste-name-0')).controller!.text,
        'Decaf coffee',
      );
      await _press(tester, 'paste-items-save');
      expect((await shopping.current())!.lines.single.name, 'Decaf coffee');
      expect(shopping.attempts, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid taps commit a plain item once', (
    WidgetTester tester,
  ) async {
    final _RecordingShopping shopping = await _open(tester);
    shopping.pending = Completer<void>();
    await tester.enterText(_key('manual-item-name'), 'Coffee');
    await pumpFrames(tester);
    await tester.tap(_key('manual-item-add'));
    await tester.tap(_key('manual-item-add'));
    await pumpFrames(tester);
    expect(shopping.attempts, hasLength(1));
    expect(tester.widget<ListTile>(_key('manual-item-add')).onTap, isNull);
    shopping.pending!.complete();
    await pumpFrames(tester, frames: 20);
    expect((await shopping.current())!.lines, hasLength(1));
  });

  for (final bool paste in <bool>[false, true]) {
    for (final bool fails in <bool>[false, true]) {
      testWidgets(
        'dragging a pending ${paste ? 'batch' : 'plain'} save preserves ${fails ? 'the retry draft' : 'completion'}',
        (WidgetTester tester) async {
          final _RecordingShopping shopping = await _open(tester);
          final Completer<void> pending = Completer<void>();
          shopping.pending = pending;
          if (paste) {
            await _paste(tester, 'Coffee\nEggs');
            await tester.enterText(_key('paste-name-0'), 'Decaf coffee');
            await _press(tester, 'paste-remove-1');
          } else {
            await tester.enterText(_key('manual-item-name'), 'Decaf coffee');
          }
          await _press(
            tester,
            paste ? 'paste-add-amount-0' : 'manual-item-add-amount',
          );
          final String amountKey = paste
              ? 'paste-0-amount'
              : 'manual-item-amount';
          final String unitKey = paste ? 'paste-0-unit' : 'manual-item-unit';
          await tester.enterText(_key(amountKey), '1/2');
          await _press(tester, unitKey);
          await _reveal(tester, find.text('lb'), menu: true);
          await tester.tap(find.text('lb'));
          final String saveKey = paste ? 'paste-items-save' : 'manual-item-add';
          await _press(tester, saveKey);
          expect(shopping.attempts, hasLength(1));

          // Back and tapping outside also keep the save and its draft together.
          await tester.binding.handlePopRoute();
          await tester.tapAt(const Offset(8, 8));
          await pumpFrames(tester);
          expect(
            _key(paste ? 'paste-items-scroll' : 'add-to-list-scroll'),
            findsOneWidget,
          );

          final Rect sheet = tester.getRect(find.byType(BottomSheet).last);
          await tester.flingFrom(
            Offset(sheet.center.dx, sheet.top + 4),
            Offset(0, sheet.height),
            2000,
          );
          if (fails) {
            pending.completeError(StateError('A recoverable write failure'));
            await pumpFrames(tester, frames: 40);
            expect(
              _key(paste ? 'paste-items-scroll' : 'add-to-list-scroll'),
              findsOneWidget,
              reason: 'A closing gesture must not discard a pending draft.',
            );
            await _reveal(tester, find.text('Retry'));
            expect(find.text('Retry'), findsOneWidget);
            final String nameKey = paste ? 'paste-name-0' : 'manual-item-name';
            await _reveal(tester, _key(nameKey));
            expect(
              tester.widget<TextField>(_key(nameKey)).controller!.text,
              'Decaf coffee',
            );
            await _reveal(tester, _key(amountKey));
            expect(
              tester.widget<TextField>(_key(amountKey)).controller!.text,
              '1/2',
            );
            await _reveal(tester, _key(unitKey));
            expect(find.text('lb'), findsOneWidget);
            shopping.pending = null;
            await _press(tester, saveKey);
          } else {
            pending.complete();
            await pumpFrames(tester, frames: 40);
          }
          final ShoppingLine saved = (await shopping.current())!.lines.single;
          expect(saved.name, 'Decaf coffee');
          expect(saved.planned.single.amountIn(Units.pound), 0.5);
          expect(shopping.attempts, hasLength(fails ? 2 : 1));
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byType(ShoppingScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final String dismissal in <String>['Cancel', 'back', 'outside']) {
      testWidgets(
        '${paste ? 'paste' : 'plain'} draft can close via $dismissal before saving',
        (WidgetTester tester) async {
          final _RecordingShopping shopping = await _open(tester);
          await tester.enterText(_key('manual-item-name'), 'Coffee');
          if (paste) await _paste(tester, 'Eggs');
          if (dismissal == 'Cancel') {
            await _reveal(tester, find.text('Cancel').last);
            await tester.tap(find.text('Cancel').last);
          } else if (dismissal == 'back') {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tapAt(const Offset(8, 8));
          }
          await pumpFrames(tester, frames: 40);
          expect(_key('paste-items-scroll'), findsNothing);
          if (paste) {
            expect(_key('add-to-list-scroll'), findsOneWidget);
            expect(
              tester
                  .widget<TextField>(_key('manual-item-name'))
                  .controller!
                  .text,
              'Coffee',
            );
          } else {
            expect(find.byType(BottomSheet), findsNothing);
          }
          expect(shopping.attempts, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final bool household in <bool>[false, true]) {
    for (final bool paste in <bool>[false, true]) {
      for (final bool retry in <bool>[false, true]) {
        testWidgets(
          '${household ? 'household' : 'account'} change expires ${paste ? 'paste' : 'plain'} ${retry ? 'retry' : 'review'}',
          (WidgetTester tester) async {
            String identity = household ? 'local-household' : 'local-user';
            final _RecordingShopping shopping = await _open(
              tester,
              failures: retry ? 1 : 0,
              extraOverrides: <Object>[
                if (household)
                  currentHouseholdIdProvider.overrideWith((Ref ref) => identity)
                else
                  currentUserIdProvider.overrideWith((Ref ref) => identity),
              ],
            );
            final ProviderContainer container = _container(tester);
            if (paste) {
              await _paste(tester, 'Coffee');
            } else {
              await tester.enterText(_key('manual-item-name'), 'Coffee');
              await pumpFrames(tester);
            }
            final String saveKey = paste
                ? 'paste-items-save'
                : 'manual-item-add';
            if (retry) await _press(tester, saveKey);
            identity = 'someone-else';
            if (household) {
              container.invalidate(currentHouseholdIdProvider);
            } else {
              container.invalidate(currentUserIdProvider);
            }
            await pumpFrames(tester);
            await _press(tester, saveKey);
            expect(shopping.attempts, hasLength(retry ? 1 : 0));
            expect(
              find.textContaining('account or household changed'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final bool paste in <bool>[false, true]) {
    testWidgets(
      'disposing during ${paste ? 'batch' : 'plain'} save avoids stale context or ref access',
      (WidgetTester tester) async {
        final _RecordingShopping shopping = await _open(tester);
        shopping.pending = Completer<void>();
        if (paste) {
          await _paste(tester, 'Coffee');
        } else {
          await tester.enterText(_key('manual-item-name'), 'Coffee');
          await pumpFrames(tester);
        }
        await _press(tester, paste ? 'paste-items-save' : 'manual-item-add');
        expect(shopping.attempts, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        shopping.pending!.complete();
        await pumpFrames(tester, frames: 20);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
