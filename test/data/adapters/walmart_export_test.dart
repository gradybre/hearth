import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/data/adapters/walmart_export.dart';
import 'package:hearth/domain/models/food.dart';
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

    test('nor a component somebody asked them to leave off', () {
      // A meal built as "burger, no lettuce" carries a −1 lb line. Flip its
      // "Ate out" switch off and the recipe stops being skipped, so the
      // deduction reaches the list — and the cart quantity clamps to at
      // least one, which ordered one lettuce for the person who asked for
      // none. Nothing to pick up is nothing to export.
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        line('lettuce', planned: -1),
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
      // cart Hearth has no product codes to fill.
      expect(const WalmartExport().kind, ShoppingExportKind.deepLink);
      expect(const WalmartExport().displayName, 'Walmart');
    });
  });

  group('the basket', () {
    Food product(String id, {Quantity? pack}) => Food(
      id: 'food-$id',
      householdId: 'household-1',
      name: 'Ground beef',
      source: FoodSource.manual,
      servingOptions: const <ServingOption>[],
      walmartItemId: id,
      packSize: pack,
    );

    ShoppingLine lineFor(String foodId, Quantity planned) => ShoppingLine(
      key: foodId,
      name: 'ground beef',
      planned: <Quantity>[planned],
      foodId: foodId,
    );

    test('several items ride in one link', () async {
      final List<ShoppingExportItem> items = exportableLines(
        <ShoppingLine>[
          lineFor('food-a', Quantity.of(1, Units.pound)),
          lineFor('food-b', Quantity.of(1, Units.pound)),
        ],
        foods: <String, Food>{
          'food-a': product('111111111'),
          'food-b': product('222222222'),
        },
      );

      final Uri link = WalmartExport.cartLinkFor(items)!;
      expect(link.host, 'www.walmart.com');
      expect(link.path, '/sc/cart/addToCart');
      expect(link.queryParameters['items'], '111111111,222222222');
    });

    test('a quantity rides with the id, and one is left implied', () async {
      // A bare id already means one, so the suffix would be noise on most
      // lines — and the documented format allows either.
      final List<ShoppingExportItem> items = exportableLines(
        <ShoppingLine>[
          lineFor('food-a', Quantity.of(3, Units.pound)),
          lineFor('food-b', Quantity.of(1, Units.pound)),
        ],
        foods: <String, Food>{
          'food-a': product('111111111', pack: Quantity.of(1, Units.pound)),
          'food-b': product('222222222', pack: Quantity.of(1, Units.pound)),
        },
      );

      expect(
        WalmartExport.cartLinkFor(items)!.queryParameters['items'],
        '111111111_3,222222222',
      );
    });

    test('a line with no saved product is left out of the basket', () async {
      // Walmart drops the shopper on its homepage if any item fails to add,
      // so a name Hearth invented would cost the whole trip.
      final List<ShoppingExportItem> items = exportableLines(
        <ShoppingLine>[
          lineFor('food-a', Quantity.of(1, Units.pound)),
          lineFor('food-b', Quantity.of(1, Units.pound)),
        ],
        foods: <String, Food>{'food-a': product('111111111')},
      );

      expect(
        WalmartExport.cartLinkFor(items)!.queryParameters['items'],
        '111111111',
      );
    });

    test(
      'but it is still in the copied text, which is the safety net',
      () async {
        final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
          lineFor('food-b', Quantity.of(1, Units.pound)),
        ]);

        expect(WalmartExport.asText(items), contains('ground beef'));
      },
    );

    test('no saved products at all means no basket to offer', () async {
      final List<ShoppingExportItem> items = exportableLines(<ShoppingLine>[
        lineFor('food-a', Quantity.of(1, Units.pound)),
      ]);

      expect(WalmartExport.cartLinkFor(items), isNull);
    });

    test('and the kind says which hand-off is actually available', () async {
      // A screen reads this to decide whether to offer the basket at all.
      final ShoppingExportResult without = await const WalmartExport().export(
        exportableLines(<ShoppingLine>[
          lineFor('food-a', Quantity.of(1, Units.pound)),
        ]),
      );
      expect(without.kind, ShoppingExportKind.deepLink);
      expect(without.cartLink, isNull);

      final ShoppingExportResult with_ = await const WalmartExport().export(
        exportableLines(
          <ShoppingLine>[lineFor('food-a', Quantity.of(1, Units.pound))],
          foods: <String, Food>{'food-a': product('111111111')},
        ),
      );
      expect(with_.kind, ShoppingExportKind.cart);
      expect(with_.cartLink, isNotNull);
      // The copy and the search links survive either way — the basket is an
      // addition, never a replacement.
      expect(with_.clipboardText, isNotNull);
      expect(with_.deepLinks, isNotEmpty);
    });
  });
}
