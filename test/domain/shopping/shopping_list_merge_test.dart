import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_list_merge.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// Rebuilding a list without throwing away what was done to it (spec §5.7).
///
/// This decides whether Rebuild is a button you press freely or one you learn
/// to be afraid of. The plan owns what the recipes call for; everything a
/// person decided is theirs.
void main() {
  ShoppingLine line(
    String name, {
    double planned = 2,
    double? wanted,
    double? onHand,
    bool checked = false,
    bool manual = false,
    int sortOrder = 0,
    String? storeTag,
  }) => ShoppingLine(
    key: name,
    name: name,
    planned: <Quantity>[Quantity.of(planned, Units.pound)],
    wanted: wanted == null ? null : Quantity.of(wanted, Units.pound),
    onHand: onHand == null ? null : Quantity.of(onHand, Units.pound),
    checked: checked,
    isManual: manual,
    sortOrder: sortOrder,
    storeTag: storeTag,
  );

  group('what the plan owns, and gets back', () {
    test('the quantity the recipes call for', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', planned: 2)],
        <ShoppingLine>[line('beef', planned: 3)],
      );

      expect(merged.single.planned.single.amountIn(Units.pound), 3);
    });

    test('a line the plan no longer wants goes', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef'), line('rice')],
        <ShoppingLine>[line('beef')],
      );

      expect(merged.map((ShoppingLine l) => l.name), <String>['beef']);
    });

    test('and a line it newly wants arrives at the end', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', sortOrder: 5)],
        <ShoppingLine>[line('beef'), line('rice')],
      );

      expect(merged.last.name, 'rice');
      expect(merged.last.sortOrder, greaterThan(5));
    });
  });

  group('what a person owns, and keeps', () {
    test('a tick', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', checked: true)],
        <ShoppingLine>[line('beef', planned: 3)],
      );

      expect(merged.single.isChecked, isTrue);
    });

    test('what you already have', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', onHand: 1)],
        <ShoppingLine>[line('beef', planned: 3)],
      );

      // Adding a dinner did not empty the freezer.
      expect(merged.single.onHand!.amountIn(Units.pound), 1);
      // closeTo, not equals: subtracting canonical grams and reading them back
      // as pounds drifts in the last bit. Hearth rounds on display and never
      // in storage (§9.1), so the drift belongs here rather than in the code.
      expect(merged.single.toBuy!.amountIn(Units.pound), closeTo(2, 1e-9));
    });

    test('an edited amount, with the plan visible underneath it', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', planned: 1.5, wanted: 2)],
        <ShoppingLine>[line('beef', planned: 2.5)],
      );

      // The decision stands; what the recipes now say is on the line too, so
      // the difference can be seen rather than silently resolved.
      expect(merged.single.wanted!.amountIn(Units.pound), 2);
      expect(merged.single.planned.single.amountIn(Units.pound), 2.5);
      expect(merged.single.isEdited, isTrue);
    });

    test('the order', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('beef', sortOrder: 9)],
        <ShoppingLine>[line('beef', sortOrder: 0)],
      );

      expect(merged.single.sortOrder, 9);
    });

    test('a manual item, even when the plan has never heard of it', () {
      // The plan never put coffee here, so the plan does not get a vote.
      final List<ShoppingLine> merged = ShoppingListMerge.into(
        <ShoppingLine>[line('coffee', manual: true)],
        <ShoppingLine>[line('beef')],
      );

      expect(merged.map((ShoppingLine l) => l.name), contains('coffee'));
    });

    test('and a ticked line the plan dropped, because the tick is a note', () {
      final List<ShoppingLine> merged = ShoppingListMerge.into(<ShoppingLine>[
        line('rice', checked: true),
      ], <ShoppingLine>[]);

      expect(merged.single.name, 'rice');
    });
  });

  group('the order carries to the next list', () {
    test('a new list inherits where things were put', () {
      // Without this an order arranged once evaporates with the list it was
      // arranged on, and nobody drags anything twice.
      final List<ShoppingLine> next = ShoppingListMerge.ordered(
        <ShoppingLine>[line('beef'), line('rice')],
        <ShoppingLine>[line('rice', sortOrder: 1), line('beef', sortOrder: 2)],
      );

      expect(
        next.firstWhere((ShoppingLine l) => l.name == 'rice').sortOrder,
        1,
      );
      expect(
        next.firstWhere((ShoppingLine l) => l.name == 'beef').sortOrder,
        2,
      );
    });

    test('something the last list never saw goes to the end', () {
      final List<ShoppingLine> next = ShoppingListMerge.ordered(
        <ShoppingLine>[line('beef'), line('kale')],
        <ShoppingLine>[line('beef', sortOrder: 4)],
      );

      expect(
        next.firstWhere((ShoppingLine l) => l.name == 'kale').sortOrder,
        greaterThan(4),
      );
    });

    test('but ticks and on-hand amounts do not carry', () {
      // Hearth cannot see what was eaten between one shop and the next, and a
      // stale "you already have this" is how something gets left off a list.
      final List<ShoppingLine> next = ShoppingListMerge.ordered(
        <ShoppingLine>[line('beef')],
        <ShoppingLine>[line('beef', checked: true, onHand: 2, sortOrder: 3)],
      );

      expect(next.single.isChecked, isFalse);
      expect(next.single.onHand, isNull);
      expect(next.single.sortOrder, 3);
    });
  });

  group('how the screen sees it', () {
    test('grouped by store, untagged last, then by the order you chose', () {
      final List<ShoppingLine> shown = ShoppingListMerge.display(<ShoppingLine>[
        line('paper towels'),
        line('beef', storeTag: 'Publix', sortOrder: 2),
        line('kale', storeTag: 'Publix', sortOrder: 1),
        line('bulk rice', storeTag: 'Costco'),
      ]);

      expect(shown.map((ShoppingLine l) => l.name), <String>[
        'bulk rice',
        'kale',
        'beef',
        'paper towels',
      ]);
    });
  });
}
