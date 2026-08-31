import 'package:hearth/domain/foods/food_query.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

Food loggable(
  String name, {
  String? id,
  String? barcode,
  FoodSource source = FoodSource.manual,
  DateTime? updatedAt,
}) => aFood(
  name,
  id: id,
  barcode: barcode,
  source: source,
  updatedAt: updatedAt,
  servingOptions: <ServingOption>[
    aServing(
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 120, proteinG: 8),
    ),
  ],
);

void main() {
  group('needsAttention', () {
    test('a food with no serving at all cannot be logged', () {
      expect(aFood('Mystery').needsAttention, isTrue);
    });

    test('a food whose only serving is all zeroes cannot either', () {
      // Half-filled crowd-sourced imports look like real entries in a list
      // while contributing nothing to a day.
      final Food empty = aFood(
        'Empty',
        servingOptions: <ServingOption>[
          aServing(amount: 100, unit: Units.gram, macros: Macros.zero),
        ],
      );
      expect(empty.needsAttention, isTrue);
    });

    test('a food with real numbers does not need attention', () {
      expect(loggable('Chicken').needsAttention, isFalse);
    });

    test('one usable serving is enough, even beside an empty one', () {
      final Food mixed = aFood(
        'Mixed',
        servingOptions: <ServingOption>[
          aServing(amount: 1, unit: Units.item, macros: Macros.zero),
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 90),
          ),
        ],
      );
      expect(mixed.needsAttention, isFalse);
    });
  });

  group('filtering', () {
    test('text matches name and brand, both directions', () {
      final Food onion = aFood('White onion', id: 'onion');
      expect(
        FoodSearch.matches(onion, const FoodFilter(text: 'onion')),
        isTrue,
      );
      // The library entry is the plainer of the two — the same case the
      // ingredient picker had to handle.
      expect(
        FoodSearch.matches(onion, const FoodFilter(text: 'diced white onion')),
        isTrue,
      );
      expect(
        FoodSearch.matches(onion, const FoodFilter(text: 'chicken')),
        isFalse,
      );
    });

    test('source keeps only the chosen ones', () {
      const FoodFilter mine = FoodFilter(
        sources: <FoodSource>{FoodSource.manual},
      );
      expect(FoodSearch.matches(loggable('Mine'), mine), isTrue);
      expect(
        FoodSearch.matches(
          loggable('Theirs', source: FoodSource.openFoodFacts),
          mine,
        ),
        isFalse,
      );
    });

    test('needs-attention keeps only the unloggable', () {
      const FoodFilter filter = FoodFilter(needsAttention: true);
      expect(FoodSearch.matches(aFood('Broken'), filter), isTrue);
      expect(FoodSearch.matches(loggable('Fine'), filter), isFalse);
    });

    test('has-barcode separates scanned packets from generics', () {
      const FoodFilter filter = FoodFilter(hasBarcode: true);
      expect(
        FoodSearch.matches(loggable('Beans', barcode: '5000157024671'), filter),
        isTrue,
      );
      expect(FoodSearch.matches(loggable('White onion'), filter), isFalse);
    });

    test('a store tag matches case-insensitively', () {
      final Food costco = aFood('Bulk rice').withStoreTag('Costco');
      expect(
        FoodSearch.matches(
          costco,
          const FoodFilter(storeTags: <String>{'costco'}),
        ),
        isTrue,
      );
      expect(
        FoodSearch.matches(
          loggable('Untagged'),
          const FoodFilter(storeTags: <String>{'costco'}),
        ),
        isFalse,
      );
    });

    test('dimensions AND together, narrowing', () {
      const FoodFilter filter = FoodFilter(
        sources: <FoodSource>{FoodSource.openFoodFacts},
        hasBarcode: true,
      );
      expect(
        FoodSearch.matches(
          loggable('Beans', barcode: '1', source: FoodSource.openFoodFacts),
          filter,
        ),
        isTrue,
      );
      // Right source, no barcode — excluded.
      expect(
        FoodSearch.matches(
          loggable('Loose', source: FoodSource.openFoodFacts),
          filter,
        ),
        isFalse,
      );
    });

    test('soft-deleted foods never appear', () {
      // Kept forever so old logs resolve (§4) — the library is not where they
      // belong.
      final Food gone = aFood('Removed', id: 'gone').withDeleted();
      expect(FoodSearch.apply(<Food>[gone], FoodFilter.none), isEmpty);
    });
  });

  group('sorting', () {
    DateTime at(int day) => DateTime.utc(2026, 8, day);

    test('most recent first is the default', () {
      final List<Food> library = <Food>[
        loggable('Aaa', id: 'old', updatedAt: at(1)),
        loggable('Zzz', id: 'new', updatedAt: at(3)),
        loggable('Mmm', id: 'mid', updatedAt: at(2)),
      ];

      expect(
        FoodSearch.apply(library, FoodFilter.none).map((Food f) => f.id),
        <String>['new', 'mid', 'old'],
      );
    });

    test('an undated food sorts last, not first', () {
      final List<Food> library = <Food>[
        loggable('Aaa', id: 'undated'),
        loggable('Zzz', id: 'dated', updatedAt: at(1)),
      ];

      expect(
        FoodSearch.apply(library, FoodFilter.none).map((Food f) => f.id),
        <String>['dated', 'undated'],
      );
    });

    test('A–Z ignores the timestamps entirely', () {
      final List<Food> library = <Food>[
        loggable('Ziti', id: 'z', updatedAt: at(9)),
        loggable('Aubergine', id: 'a', updatedAt: at(1)),
      ];

      expect(
        FoodSearch.apply(
          library,
          const FoodFilter(sort: FoodSort.nameAsc),
        ).map((Food f) => f.id),
        <String>['a', 'z'],
      );
    });

    test('a tie on the sort falls back to name', () {
      final List<Food> library = <Food>[
        loggable('Ziti', id: 'z', updatedAt: at(1)),
        loggable('Aubergine', id: 'a', updatedAt: at(1)),
      ];

      expect(
        FoodSearch.apply(library, FoodFilter.none).map((Food f) => f.id),
        <String>['a', 'z'],
      );
    });

    test('the sort is not counted as an active filter', () {
      const FoodFilter sorted = FoodFilter(sort: FoodSort.nameAsc);
      expect(sorted.activeCount, 0);
      expect(sorted.isEmpty, isTrue);
    });
  });

  group('the chips on offer', () {
    test('store tags are folded and de-duplicated', () {
      final List<Food> library = <Food>[
        aFood('A').withStoreTag('Costco'),
        aFood('B').withStoreTag('costco'),
        aFood('C').withStoreTag('Publix'),
        aFood('D'),
      ];
      expect(FoodSearch.storeTagsIn(library), <String>['costco', 'publix']);
    });

    test('sources come back in a stable order, not library order', () {
      // Declaration order, so the chip row does not reshuffle itself as foods
      // are added — the library here is deliberately in the other order.
      final List<Food> library = <Food>[
        loggable('B', source: FoodSource.manual),
        loggable('A', source: FoodSource.usda),
      ];
      expect(FoodSearch.sourcesIn(library), <FoodSource>[
        FoodSource.usda,
        FoodSource.manual,
      ]);
    });
  });
}
