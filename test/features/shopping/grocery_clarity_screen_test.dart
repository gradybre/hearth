import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_screen.dart';

import '../../support/app_harness.dart';
import '../../support/package_fixtures.dart';

void main() {
  ShoppingLine line(
    String name, {
    bool checked = false,
    double? have,
    double? wanted,
    int order = 0,
  }) => ShoppingLine(
    key: name,
    name: name,
    planned: <Quantity>[Quantity.of(2, Units.item)],
    checked: checked,
    onHand: have == null ? null : Quantity.of(have, Units.item),
    wanted: wanted == null ? null : Quantity.of(wanted, Units.item),
    sortOrder: order,
  );

  testWidgets('Remaining separates bought, at home and zero total needed', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      shoppingLines: <ShoppingLine>[
        line('Apples'),
        line('Bread', checked: true, order: 1),
        line('Rice', have: 2, order: 2),
        line('Coffee', wanted: 0, order: 3),
      ],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);

    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Rice'), findsNothing);
    expect(find.text('Bought 1'), findsOneWidget);
    expect(find.text('At home 1'), findsOneWidget);
    expect(find.text('Not needed 1'), findsOneWidget);
    await tester.tap(find.text('All'));
    await pumpFrames(tester);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.textContaining('in the basket'), findsNothing);
  });

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ShoppingScreen)));

  Future<List<ShoppingLine>> stored(WidgetTester tester) async =>
      (await tester.runAsync(
        () => container(tester).read(shoppingRepositoryProvider).current(),
      ))!.lines;

  testWidgets('filtered reorder retains hidden rows and the All order', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      shoppingLines: <ShoppingLine>[
        line('A'),
        line('B', checked: true, order: 1),
        line('C', order: 2),
        line('D', have: 2, order: 3),
        line('E', order: 4),
      ],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(2, 0);
    await pumpFrames(tester, frames: 24);
    expect(
      (await stored(tester)).map((ShoppingLine line) => line.name),
      <String>['E', 'B', 'A', 'D', 'C'],
    );
    await tester.tap(find.text('All'));
    await pumpFrames(tester);
    final List<double> positions = <String>[
      'E',
      'B',
      'A',
      'D',
      'C',
    ].map((String name) => tester.getTopLeft(find.text(name)).dy).toList();
    expect(positions, orderedEquals(<double>[...positions]..sort()));
    expect(find.text('5 items'), findsOneWidget);
  });

  testWidgets(
    'all resolved is distinct from an empty list and can be unticked',
    (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        shoppingLines: <ShoppingLine>[line('Bread', checked: true)],
      );
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);
      expect(find.text('Nothing left to buy.'), findsOneWidget);
      expect(find.text('Nothing on the list yet.'), findsNothing);
      expect(find.text('Bought 1'), findsOneWidget);
      await tester.tap(find.text('All'));
      await pumpFrames(tester);
      await tester.tap(find.text('Bread'));
      await pumpFrames(tester);
      await tester.tap(find.text('Remaining'));
      await pumpFrames(tester);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('1 left to buy'), findsOneWidget);
      expect((await stored(tester)).single.checked, isFalse);
    },
  );

  for (final bool checked in <bool>[false, true]) {
    testWidgets('package coverage can be unticked (bought: $checked)', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        foods: <Food>[packageCorn()],
        shoppingLines: <ShoppingLine>[
          ShoppingLine(
            key: 'corn',
            checked: checked,
            name: 'Frozen corn',
            foodId: packageCorn().id,
            planned: <Quantity>[Quantity.of(10, Units.ounce)],
            onHand: Quantity.of(2, Units.cup),
          ),
        ],
      );
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);
      expect(find.text(checked ? 'Bought 1' : 'At home 1'), findsOneWidget);
      await tester.tap(find.text('All'));
      await pumpFrames(tester);
      await tester.tap(find.text('Frozen corn'));
      await pumpFrames(tester);
      expect((await stored(tester)).single.onHand, isNull);
      await tester.tap(find.text('Remaining'));
      await pumpFrames(tester);
      expect(find.text('Frozen corn'), findsOneWidget);
    });
  }

  testWidgets('a partner update waits until the active pointer is released', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      shoppingLines: <ShoppingLine>[line('Bread', order: 1)],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    final Offset position = tester.getCenter(find.text('Bread'));
    final TestGesture pointer = await tester.startGesture(position);
    final ProviderContainer scope = container(tester);
    await tester.runAsync(
      () => scope.read(shoppingRepositoryProvider).replace(<ShoppingLine>[
        line('Apples'),
        line('Bread', order: 1),
      ]),
    );
    scope.invalidate(shoppingListProvider);
    await pumpFrames(tester);
    expect(find.text('Apples'), findsNothing);
    expect(tester.getCenter(find.text('Bread')), position);
    await pointer.cancel();
    await pumpFrames(tester);
    expect(find.text('Apples'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('export receives all source lines in either view', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      shoppingLines: <ShoppingLine>[
        line('Apples'),
        line('Bread', checked: true, order: 1),
        line('Rice', have: 2, order: 2),
      ],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    for (final String view in <String>['Remaining', 'All']) {
      await tester.tap(find.text(view));
      await pumpFrames(tester);
      await tester.tap(find.text('More'));
      await pumpFrames(tester);
      await tester.tap(find.text('Share or export'));
      await pumpFrames(tester);
      expect(find.textContaining('1 item still to buy'), findsOneWidget);
      final BuildContext sheet = tester.element(
        find.text('Take the list with you'),
      );
      Navigator.of(sheet).pop();
      await pumpFrames(tester);
    }
    expect((await stored(tester)).length, 3);
  });

  testWidgets('releasing a neutral pointer schedules the held update', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      shoppingLines: <ShoppingLine>[line('Bread', order: 1)],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    await tester.pumpAndSettle();
    final Finder list = find.byKey(
      const ValueKey<String>('grocery-list-scroll'),
    );
    final Offset neutral = tester.getBottomRight(list) - const Offset(30, 50);
    final TestGesture pointer = await tester.startGesture(neutral);
    final ProviderContainer scope = container(tester);
    await tester.runAsync(
      () => scope.read(shoppingRepositoryProvider).replace(<ShoppingLine>[
        line('Apples'),
        line('Bread', order: 1),
      ]),
    );
    scope.invalidate(shoppingListProvider);
    await pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text('Apples'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await pointer.up();
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'reconciliation cannot depend on an unrelated future frame',
    );
    await tester.pumpAndSettle();
    expect(find.text('Apples'), findsOneWidget);
  });

  testWidgets('a held check-off preserves newly received amounts', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, shoppingLines: <ShoppingLine>[line('Bread')]);
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    final TestGesture pointer = await tester.startGesture(
      tester.getCenter(find.text('Bread')),
    );
    final ProviderContainer scope = container(tester);
    await tester.runAsync(
      () => scope.read(shoppingRepositoryProvider).replace(<ShoppingLine>[
        line('Bread', wanted: 5, have: 1),
      ]),
    );
    scope.invalidate(shoppingListProvider);
    await pumpFrames(tester);
    await pointer.up();
    await pumpFrames(tester, frames: 24);

    final ShoppingLine bread = (await stored(tester)).single;
    expect(bread.checked, isTrue);
    expect(bread.wanted?.canonicalAmount, 5);
    expect(bread.onHand?.canonicalAmount, 1);
  });

  testWidgets('a held amount tap opens the newly received amounts', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, shoppingLines: <ShoppingLine>[line('Bread')]);
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    final TestGesture pointer = await tester.startGesture(
      tester.getCenter(find.text('2')),
    );
    final ProviderContainer scope = container(tester);
    await tester.runAsync(
      () => scope.read(shoppingRepositoryProvider).replace(<ShoppingLine>[
        line('Bread', wanted: 5, have: 1),
      ]),
    );
    scope.invalidate(shoppingListProvider);
    await pumpFrames(tester);
    await pointer.up();
    await pumpFrames(tester, frames: 24);

    final List<TextField> amounts = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(amounts.first.controller!.text, '5');
    expect(amounts.last.controller!.text, '1');
    expect(find.text('Buy 4'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, frames: 24);
    expect((await stored(tester)).single.wanted?.canonicalAmount, 5);
  });

  testWidgets('a held deletion restores the row that was actually removed', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, shoppingLines: <ShoppingLine>[line('Bread')]);
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    await tester.drag(find.text('Bread'), const Offset(-200, 0));
    await pumpFrames(tester, frames: 20);
    final TestGesture pointer = await tester.startGesture(
      tester.getCenter(find.text('Delete')),
    );
    final ProviderContainer scope = container(tester);
    await tester.runAsync(
      () => scope.read(shoppingRepositoryProvider).replace(<ShoppingLine>[
        line('Bread', wanted: 5, have: 1),
      ]),
    );
    scope.invalidate(shoppingListProvider);
    await pumpFrames(tester);
    await pointer.up();
    await pumpFrames(tester, frames: 24);
    expect(find.text('Bread'), findsNothing);
    await tester.tap(find.text('Undo'));
    await pumpFrames(tester, frames: 24);

    final ShoppingLine restored = (await stored(tester)).single;
    expect(restored.wanted?.canonicalAmount, 5);
    expect(restored.onHand?.canonicalAmount, 1);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      '320pt at 3x keeps groceries visible and More reachable in ${brightness.name}',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await pumpHearthApp(
            tester,
            size: const Size(320, 568),
            textScale: 3,
            brightness: brightness,
            viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
            shoppingLines: <ShoppingLine>[line('Apples')],
          );
          await tester.tap(find.text('Shopping').last);
          await pumpFrames(tester);
          expect(tester.takeException(), isNull);
          final Rect groceries = tester.getRect(find.text('Apples'));
          final Rect viewport = tester.getRect(
            find.byKey(const ValueKey<String>('grocery-list-scroll')),
          );
          expect(
            viewport.overlaps(groceries),
            isTrue,
            reason: 'the initial view includes the first grocery',
          );
          await tester.scrollUntilVisible(
            find.text('More'),
            160,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey<String>('grocery-list-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await pumpFrames(tester);
          expect(
            tester.getSize(find.widgetWithText(OutlinedButton, 'More')).height,
            greaterThanOrEqualTo(44),
          );
          expect(
            tester
                .getSemantics(find.text('More'))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(find.text('More'));
          await pumpFrames(tester);
          for (final String label in <String>[
            'Share or export',
            'Manage list',
            'List help',
            'Clear the list',
          ]) {
            await tester.ensureVisible(find.text(label));
            await pumpFrames(tester);
            expect(find.text(label).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
