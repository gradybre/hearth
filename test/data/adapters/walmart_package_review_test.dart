import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/data/adapters/walmart_export.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  for (final double need in <double>[1, 12]) {
    test(
      'incompatible on-hand counts stay in review and copy: $need scoops',
      () {
        final List<ShoppingExportItem> items = exportableLines(
          <ShoppingLine>[
            ShoppingLine(
              key: 'powder',
              name: 'Protein powder',
              foodId: 'powder',
              planned: <Quantity>[Quantity.of(need, Units.scoop)],
              onHand: Quantity.of(1, Units.container),
            ),
          ],
          foods: <String, Food>{
            'powder': Food(
              id: 'powder',
              name: 'Protein powder',
              source: FoodSource.manual,
              servingOptions: const <ServingOption>[],
              packSize: Quantity.of(12, Units.scoop),
              walmartItemId: '123456789',
            ),
          },
        );
        expect(items, hasLength(1));
        expect(items.single.hasUnresolvedAmount, isTrue);
        expect(items.single.canChooseCartQuantity, isFalse);
        expect(items.single.quantity, isNull);
        expect(WalmartExport.cartLinkFor(items), isNull);
        expect(WalmartExport.asText(items), contains('Protein powder'));
        expect(WalmartExport.asText(items), contains('scoop'));
        expect(WalmartExport.asText(items), contains('container'));
        expect(
          WalmartExport.asText(items),
          contains('remaining amount unknown'),
        );
      },
    );
  }

  test('an unknown package conversion never silently sends one product', () {
    final List<ShoppingExportItem> items = exportableLines(
      <ShoppingLine>[
        ShoppingLine(
          key: 'sauce',
          name: 'sauce',
          foodId: 'sauce',
          planned: <Quantity>[Quantity.of(600, Units.gram)],
        ),
      ],
      foods: const <String, Food>{
        'sauce': Food(
          id: 'sauce',
          name: 'Saved sauce',
          servingOptions: <ServingOption>[],
          source: FoodSource.manual,
          walmartItemId: '123456789',
        ),
      },
    );
    expect(WalmartExport.cartLinkFor(items), isNull);
    expect(WalmartExport.asText(items), contains('sauce'));
  });

  test('a direct adapter input cannot exceed the reviewed package cap', () {
    expect(
      WalmartExport.cartLinkFor(const <ShoppingExportItem>[
        ShoppingExportItem(name: 'sauce', productId: '123456789', quantity: 25),
      ]),
      isNull,
    );
  });

  test('two lines for one product cannot bypass the combined package cap', () {
    expect(
      WalmartExport.cartLinkFor(const <ShoppingExportItem>[
        ShoppingExportItem(name: 'sauce', productId: '123456789', quantity: 13),
        ShoppingExportItem(
          name: 'pasta sauce',
          productId: '123456789',
          quantity: 13,
        ),
      ]),
      isNull,
    );
  });

  test('duplicate saved products combine exactly within the cap', () {
    final Uri link = WalmartExport.cartLinkFor(const <ShoppingExportItem>[
      ShoppingExportItem(name: 'sauce', productId: '123456789', quantity: 2),
      ShoppingExportItem(
        name: 'pasta sauce',
        productId: '123456789',
        quantity: 3,
      ),
      ShoppingExportItem(name: 'rice', productId: '987654321', quantity: 1),
    ])!;
    expect(link.queryParameters['items'], '123456789_5,987654321');
  });

  test('malformed product IDs and nonpositive counts do not enter the URL', () {
    for (final String id in <String>[
      '',
      '123_4,987_2',
      'https://other.test/123',
      '12',
      '123456789012345678901',
    ]) {
      expect(
        WalmartExport.cartLinkFor(<ShoppingExportItem>[
          ShoppingExportItem(name: 'sauce', productId: id, quantity: 2),
        ]),
        isNull,
      );
    }
    for (final int count in <int>[0, -1, 25]) {
      expect(
        WalmartExport.cartLinkFor(<ShoppingExportItem>[
          ShoppingExportItem(
            name: 'sauce',
            productId: '123456789',
            quantity: count,
          ),
        ]),
        isNull,
      );
    }
  });

  test(
    'unmeasured and unresolved items cannot enter even with an explicit count',
    () {
      for (final ShoppingExportItem item in const <ShoppingExportItem>[
        ShoppingExportItem(
          name: 'sauce',
          productId: '123456789',
          quantity: 2,
          hasUnquantified: true,
        ),
        ShoppingExportItem(
          name: 'sauce',
          productId: '123456789',
          quantity: 2,
          hasUnresolvedAmount: true,
        ),
      ]) {
        expect(WalmartExport.cartLinkFor(<ShoppingExportItem>[item]), isNull);
        expect(WalmartExport.asText(<ShoppingExportItem>[item]), '- sauce');
      }
    },
  );
}
