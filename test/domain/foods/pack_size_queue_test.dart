import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/pack_size_queue.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Which foods want a pack size, and in what order (spec §5.7).
///
/// The ordering is the whole feature. Four hundred and sixty-nine foods sorted
/// by name is a list nobody finishes, and the twenty that ever reach a shelf
/// are scattered through it.
void main() {
  List<String> namesOf(PackSizeQueue queue) => <String>[
    for (final PackSizeGap gap in queue.gaps) gap.food.name,
  ];

  group('who is in it', () {
    test('a food with a pack size is not', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Marinara', id: 'f-1').withPack(Quantity.of(24, Units.ounce)),
          aFood('Oats', id: 'f-2'),
        ],
      );

      expect(namesOf(queue), <String>['Oats']);
    });

    test('nor a deleted one, which is not in the library any more', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[aFood('Oats', id: 'f-1').withDeleted()],
      );

      expect(queue.isEmpty, isTrue);
    });

    test('nor a restaurant menu row, which nobody buys at a shelf', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Harvest Bowl', id: 'f-1', source: FoodSource.restaurant),
          aFood('Oats', id: 'f-2'),
        ],
      );

      expect(namesOf(queue), <String>['Oats']);
    });

    test('nor a modifier, which is a deduction rather than a thing', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[aFood('No cheese', id: 'f-1').asModifier()],
      );

      expect(queue.isEmpty, isTrue);
    });
  });

  group('the order', () {
    test('leads with what is on the shopping list', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Almonds', id: 'f-almonds'),
          aFood('Zucchini', id: 'f-zucchini'),
        ],
        onShoppingList: <String>{'f-zucchini'},
      );

      expect(namesOf(queue), <String>['Zucchini', 'Almonds']);
      expect(queue.gaps.first.need, PackNeed.onTheList);
      expect(queue.gaps.last.need, PackNeed.elsewhere);
    });

    test('then what recipes ask for, the most-wanted first', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Almonds', id: 'f-almonds'),
          aFood('Tomatoes', id: 'f-tomatoes'),
          aFood('Butter', id: 'f-butter'),
        ],
        recipeUses: <String, int>{'f-tomatoes': 6, 'f-butter': 2},
      );

      expect(namesOf(queue), <String>['Tomatoes', 'Butter', 'Almonds']);
      expect(queue.gaps[1].recipeCount, 2);
    });

    test('and the shopping list beats a recipe count', () {
      // A food six recipes want is not on any shelf this week; the one on the
      // list is the one somebody is about to stand in front of.
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Tomatoes', id: 'f-tomatoes'),
          aFood('Yeast', id: 'f-yeast'),
        ],
        onShoppingList: <String>{'f-yeast'},
        recipeUses: <String, int>{'f-tomatoes': 6},
      );

      expect(namesOf(queue), <String>['Yeast', 'Tomatoes']);
    });

    test('ties fall back to the name, ignoring case', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('banana', id: 'f-2'),
          aFood('Apple', id: 'f-1'),
        ],
      );

      expect(namesOf(queue), <String>['Apple', 'banana']);
    });
  });

  group('what can be looked up', () {
    test('only foods with a barcode', () {
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[
          aFood('Oats', id: 'f-1', barcode: '5000157024671'),
          aFood('Carrots', id: 'f-2'),
        ],
      );

      expect(queue.length, 2);
      expect(queue.lookupable.map((PackSizeGap g) => g.food.name), <String>[
        'Oats',
      ]);
    });

    test('and a blank barcode is not one', () {
      // A lookup on an empty string is a round trip that can only miss.
      final PackSizeQueue queue = PackSizeQueue.build(
        foods: <Food>[aFood('Oats', id: 'f-1', barcode: '   ')],
      );

      expect(queue.gaps.single.canBeLookedUp, isFalse);
      expect(queue.lookupable, isEmpty);
    });
  });

  group('putting a pack size on', () {
    test('changes that and nothing else', () {
      final Food before = aFood(
        'Marinara',
        id: 'f-1',
        brand: "Rao's",
        barcode: '5000157024671',
      ).withStoreTag('Publix').asDefault();

      final Food after = before.withPackSize(Quantity.of(24, Units.ounce));

      expect(after.packSize!.amountIn(Units.ounce), closeTo(24, 0.001));
      expect(after.id, before.id);
      expect(after.name, before.name);
      expect(after.brand, before.brand);
      expect(after.barcode, before.barcode);
      expect(after.storeTag, before.storeTag);
      expect(after.isDefault, isTrue);
      // The macros a log was frozen against are not this flow's business
      // (CLAUDE.md rule 3).
      expect(after.servingOptions, same(before.servingOptions));
    });

    test('and the unit it was authored in survives', () {
      // "24 oz" is the shop's own words. A 1.5-pound jar is the same weight
      // and the wrong answer at a shelf.
      final Food after = aFood(
        'Marinara',
        id: 'f-1',
      ).withPackSize(Quantity.of(24, Units.ounce));

      expect(after.packSize!.preferredUnit, Units.ounce);
    });
  });
}
