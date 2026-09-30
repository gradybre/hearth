import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/grocery_clarity_view.dart';

import '../../support/package_fixtures.dart';

void main() {
  ShoppingLine corn({Quantity? have, Quantity? wanted, bool checked = false}) =>
      ShoppingLine(
        key: 'corn',
        name: 'Frozen corn',
        planned: <Quantity>[Quantity.of(10, Units.ounce)],
        onHand: have,
        wanted: wanted,
        checked: checked,
      );

  test('At home requires evidence covering a positive need', () {
    expect(
      groceryLineState(
        corn(have: Quantity.of(2, Units.cup)),
        food: packageCorn(),
      ),
      GroceryLineState.atHome,
    );
    expect(
      groceryLineState(corn(have: Quantity.of(2, Units.cup))),
      GroceryLineState.remaining,
    );
    expect(
      groceryLineState(corn(have: Quantity.of(5, Units.ounce))),
      GroceryLineState.remaining,
    );
    expect(
      groceryLineState(corn(wanted: Quantity.of(0, Units.ounce))),
      GroceryLineState.notNeeded,
    );
    expect(
      groceryLineState(
        corn(
          wanted: Quantity.of(0, Units.ounce),
          have: Quantity.of(10, Units.ounce),
        ),
      ),
      GroceryLineState.notNeeded,
    );
    expect(
      groceryLineState(corn(checked: true, have: Quantity.of(10, Units.ounce))),
      GroceryLineState.bought,
    );
  });

  test('unknown and unquantified asks are still remaining until checked', () {
    final ShoppingLine mixed = corn(have: Quantity.of(10, Units.ounce))
        .copyWith(
          planned: <Quantity>[
            Quantity.of(10, Units.ounce),
            Quantity.of(2, Units.cup),
          ],
        );
    expect(groceryLineState(mixed), GroceryLineState.remaining);
    expect(groceryLineState(mixed.ticked(true)), GroceryLineState.bought);
    expect(
      groceryLineState(
        corn(have: Quantity.of(10, Units.ounce))
            .copyWith(hasUnquantified: true),
      ),
      GroceryLineState.remaining,
    );
    expect(
      groceryLineState(ShoppingLine.manual(key: 'coffee', name: 'Coffee')),
      GroceryLineState.remaining,
    );
  });

  ShoppingLine item(
    String key,
    int rank, {
    String store = 'Market',
    bool checked = false,
  }) => ShoppingLine.manual(
    key: key,
    name: key,
    storeTag: store,
    sortOrder: rank,
  ).ticked(checked);

  test('filtered reorder keeps hidden positions and other stores intact', () {
    final List<ShoppingLine> source = <ShoppingLine>[
      item('A', 10),
      item('B', 20, checked: true),
      item('C', 30),
      item('D', 40, checked: true),
      item('E', 50),
      item('Other', 7, store: 'Elsewhere'),
    ];
    final List<ShoppingLine> result = reorderGroceryLines(
      lines: source,
      store: 'Market',
      visibleOrder: <String>['E', 'A', 'C'],
    );
    final List<ShoppingLine> group =
        result.where((ShoppingLine line) => line.storeTag == 'Market').toList()
          ..sort(
            (ShoppingLine a, ShoppingLine b) =>
                a.sortOrder.compareTo(b.sortOrder),
          );
    expect(group.map((ShoppingLine line) => line.key), <String>[
      'E',
      'B',
      'A',
      'D',
      'C',
    ]);
    expect(result.last, source.last);
    expect(result.length, source.length);
    expect(
      group.map((ShoppingLine line) => line.sortOrder).toSet().length,
      group.length,
    );
  });

  test('reorder reads the current rows and keeps additions during a drag', () {
    final List<ShoppingLine> result =
        reorderGroceryLines(
          lines: <ShoppingLine>[
            item('B', 1, checked: true),
            item('New', 2),
            item('C', 3),
          ],
          store: 'Market',
          visibleOrder: <String>['C', 'A', 'B'],
        )..sort(
          (ShoppingLine a, ShoppingLine b) =>
              a.sortOrder.compareTo(b.sortOrder),
        );
    expect(result.map((ShoppingLine line) => line.key), <String>[
      'C',
      'New',
      'B',
    ]);
    expect(result.last.checked, isTrue);
    expect(result.where((ShoppingLine line) => line.key == 'A'), isEmpty);
  });
}
