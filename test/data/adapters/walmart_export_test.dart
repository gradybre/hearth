import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/data/adapters/walmart_export.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// The store hand-off (spec §5.7, §9.4).
///
/// A contract test in the strict sense: what this builds is what the sheet
/// hands to the clipboard and the browser. Nothing here reaches a network, and
/// that is the property worth pinning — the list is editable right up to the
/// tap that exports it, and an adapter that could send on its own would make
/// that promise unkeepable.
void main() {
  ShoppingLine line(
    String name, {
    double? planned = 2,
    double? onHand,
    bool checked = false,
    String? store,
  }) => ShoppingLine(
    key: name,
    name: name,
    planned: <Quantity>[if (planned != null) Quantity.of(planned, Units.pound)],
    onHand: onHand == null ? null : Quantity.of(onHand, Units.pound),
    checked: checked,
    storeTag: store,
  );

  group('what goes to the shop', () {
    test('what is left to buy, not what the recipes wanted', () {
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        line('ground beef', planned: 2, onHand: 1),
      ]);

      expect(items.single.quantityLabel, '1 lb');
    });

    test('nothing you have already ticked', () {
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        line('rice', checked: true),
        line('beef'),
      ]);

      expect(items.map((ShoppingExportItem i) => i.name), <String>['beef']);
    });

    test('nor anything you have enough of', () {
      // The same thing to somebody standing in a shop: nothing to pick up.
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        line('beef', planned: 2, onHand: 2),
      ]);

      expect(items, isEmpty);
    });

    test('a line written two ways at once keeps both', () {
      // Dropping one would be choosing an amount the app declined to choose.
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        ShoppingLine(
          key: 'butter',
          name: 'butter',
          planned: <Quantity>[
            Quantity.of(2, Units.tbsp),
            Quantity.of(50, Units.gram),
          ],
        ),
      ]);

      // Both amounts, joined — rendered in the reader's own units, so the
      // grams arrive as ounces. What matters is that neither was dropped.
      expect(items.single.quantityLabel, contains('tbsp'));
      expect(items.single.quantityLabel, contains(' + '));
    });
  });

  group('the copy', () {
    test('is grouped by store, the way it was read on screen', () async {
      // A list that reorders itself on the way out is one you check again.
      final ShoppingExportResult result = await const WalmartExport().export(
        exportableLines(<ShoppingLine>[
          line('bulk rice', store: 'Costco'),
          line('kale', store: 'Publix'),
          line('paper towels'),
        ]),
      );

      expect(result.clipboardText, '''
Costco
- 2 lb bulk rice

Publix
- 2 lb kale

Anywhere
- 2 lb paper towels''');
    });

    test('an item with no amount is still a line', () async {
      final ShoppingExportResult result = await const WalmartExport().export(
        exportableLines(<ShoppingLine>[line('coffee', planned: null)]),
      );

      expect(result.clipboardText, '- coffee');
    });
  });

  group('the links', () {
    test('search for the item by name, without the amount', () async {
      // "2 lb ground beef" is not a product; the quantity is for the person
      // reading the list, not for the shop's index.
      final ShoppingExportResult result = await const WalmartExport().export(
        exportableLines(<ShoppingLine>[line('ground beef')]),
      );

      final Uri link = result.deepLinks.single;
      expect(link.host, 'www.walmart.com');
      expect(link.path, '/search');
      expect(link.queryParameters['q'], 'ground beef');
    });

    test('one per item, in the order the list is in', () async {
      final ShoppingExportResult result = await const WalmartExport().export(
        exportableLines(<ShoppingLine>[line('beef'), line('rice')]),
      );

      expect(result.deepLinks.map((Uri u) => u.queryParameters['q']), <String>[
        'beef',
        'rice',
      ]);
    });

    test('and the adapter says what it can actually do', () {
      // The sheet describes the hand-off from this rather than promising a
      // cart Walmart offers no public way to fill.
      expect(const WalmartExport().kind, ShoppingExportKind.deepLink);
      expect(const WalmartExport().displayName, 'Walmart');
    });
  });
}
