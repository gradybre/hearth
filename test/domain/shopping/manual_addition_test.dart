import 'package:hearth/domain/parsing/amount_parser.dart';
import 'package:hearth/domain/shopping/manual_addition.dart';
import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_list_merge.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('literal pasted lines', () {
    test('trims each nonempty line without interpreting its wording', () {
      final List<ManualListItem> items = ManualAdditions.fromText(
        '  Coffee 500g  \r\n\n  - 2 cans tomatoes\r'
        '1/2 cup rice\n\tMilk or oat milk\nPaper  towels  \n',
      );

      expect(items.map((ManualListItem item) => item.name), <String>[
        'Coffee 500g',
        '- 2 cans tomatoes',
        '1/2 cup rice',
        'Milk or oat milk',
        'Paper  towels',
      ]);
      expect(
        items.every((ManualListItem item) => item.quantity == null),
        isTrue,
      );
    });

    test('blank input has no items', () {
      expect(ManualAdditions.fromText(' \t\n\r\n  '), isEmpty);
    });

    test('keeps repeats for the editable review to explain', () {
      expect(
        ManualAdditions.fromText('Coffee\ncoffee')
            .map((ManualListItem item) => item.name),
        <String>['Coffee', 'coffee'],
      );
    });
  });

  group('plain additions', () {
    test('retains an explicit fractional quantity and its authored unit', () {
      final Quantity quantity = Quantity.of(parseAmount('1 1/3')!, Units.cup);
      final ManualAdditionResult result = ManualAdditions.apply(
        const <ShoppingLine>[],
        <ManualListItem>[ManualListItem(name: 'Rice', quantity: quantity)],
      );
      final ShoppingLine line = result.lines.single;

      expect(line.key, 'rice');
      expect(line.isManual, isTrue);
      expect(line.planned.single.canonicalAmount, quantity.canonicalAmount);
      expect(line.planned.single.preferredUnit, Units.cup);
      expect(line.wanted, isNull);
      expect(line.onHand, isNull);
      expect(line.hasUnquantified, isFalse);
      expect(line.contributions.single.kind, ShoppingSourceKind.manual);
      expect(line.contributions.single.quantities.single, quantity);
      expect(result.skipped, isEmpty);
    });

    test('name-only has an unmeasured manual ask, never a guessed count', () {
      final ShoppingLine line = ManualAdditions.apply(
        const <ShoppingLine>[],
        const <ManualListItem>[ManualListItem(name: 'Paper towels')],
      ).lines.single;

      expect(line.planned, isEmpty);
      expect(line.wanted, isNull);
      expect(line.onHand, isNull);
      expect(line.toBuy, isNull);
      expect(line.hasUnquantified, isTrue);
      expect(line.isChecked, isFalse);
      expect(line.contributions.single.kind, ShoppingSourceKind.manual);
      expect(line.contributions.single.quantities, isEmpty);
      expect(line.contributions.single.hasUnquantified, isTrue);
    });

    test('trims outer name whitespace, keeping interior wording intact', () {
      final ShoppingLine line = ManualAdditions.apply(
        const <ShoppingLine>[],
        const <ManualListItem>[ManualListItem(name: '  Coffee  500g  ')],
      ).lines.single;

      expect(line.name, 'Coffee  500g');
      expect(line.planned, isEmpty);
    });

    test('keeps current sequence and appends after the highest sort order', () {
      final List<ShoppingLine> current = <ShoppingLine>[
        ShoppingLine.manual(key: 'coffee', name: 'Coffee', sortOrder: 27),
        ShoppingLine.manual(key: 'milk', name: 'Milk', sortOrder: 4),
      ];
      final ManualAdditionResult result = ManualAdditions.apply(
        current,
        const <ManualListItem>[
          ManualListItem(name: 'Rice'),
          ManualListItem(name: 'Tea'),
        ],
      );

      expect(result.lines.take(2), current);
      expect(result.lines.map((ShoppingLine line) => line.sortOrder), <int>[
        27,
        4,
        28,
        29,
      ]);
      expect(current, hasLength(2));
    });

    test('measured and unmeasured manual asks survive a plan rebuild', () {
      final List<ShoppingLine> added = ManualAdditions.apply(
        const <ShoppingLine>[],
        <ManualListItem>[
          ManualListItem(name: 'Rice', quantity: Quantity.of(0.5, Units.pound)),
          const ManualListItem(name: 'Coffee'),
        ],
      ).lines;

      expect(ShoppingListMerge.into(added, const <ShoppingLine>[]), added);
    });
  });

  group('exact duplicate decisions', () {
    test('first request wins and each later duplicate retains its index', () {
      final List<ManualListItem> items = <ManualListItem>[
        ManualListItem(name: 'Coffee', quantity: Quantity.of(2, Units.item)),
        const ManualListItem(name: 'Milk'),
        ManualListItem(name: ' coffee ', quantity: Quantity.of(5, Units.item)),
        const ManualListItem(name: 'COFFEE'),
        const ManualListItem(name: ' milk '),
      ];
      final ManualAdditionResult result = ManualAdditions.apply(
        const <ShoppingLine>[],
        items,
      );

      expect(result.added, items.take(2));
      expect(result.lines, hasLength(2));
      expect(result.lines.first.planned.single.amountIn(Units.item), 2);
      expect(result.skipped.map((ManualAdditionSkip skip) => skip.index), <int>[
        2,
        3,
        4,
      ]);
      expect(
        result.skipped.every(
          (ManualAdditionSkip skip) =>
              skip.reason == ManualAdditionSkipReason.duplicateInBatch,
        ),
        isTrue,
      );
      expect(result.skipped.first.item, same(items[2]));
    });

    test('recognizes a food-backed row by its normalized visible name', () {
      final ShoppingLine existing = ShoppingLine(
        key: 'food-123',
        name: 'Sun-dried  Tomatoes',
        foodId: 'food-123',
        planned: <Quantity>[Quantity.of(1, Units.pound)],
        wanted: Quantity.of(2, Units.pound),
        onHand: Quantity.of(0.5, Units.pound),
        checked: true,
        storeTag: 'Costco',
        sortOrder: 18,
        sourceRecipeIds: const <String>['recipe-1'],
        contributions: <ShoppingContribution>[
          ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'recipe-1',
            label: 'Dinner',
            servings: 3,
            quantities: <Quantity>[Quantity.of(1, Units.pound)],
          ),
        ],
      );
      final ManualAdditionResult result = ManualAdditions.apply(
        <ShoppingLine>[existing],
        <ManualListItem>[
          ManualListItem(
            name: 'sun dried tomatoes',
            quantity: Quantity.of(5, Units.pound),
          ),
          const ManualListItem(name: 'Paper towels'),
        ],
      );

      expect(result.lines.first, same(existing));
      expect(result.skipped.single.index, 0);
      expect(
        result.skipped.single.reason,
        ManualAdditionSkipReason.alreadyOnList,
      );
      expect(result.added.single.name, 'Paper towels');
    });

    test('does not merge names that only share words', () {
      final ManualAdditionResult result = ManualAdditions.apply(
        <ShoppingLine>[ShoppingLine.manual(key: 'milk', name: 'Milk')],
        const <ManualListItem>[
          ManualListItem(name: 'Oat milk'),
          ManualListItem(name: 'Milk chocolate'),
        ],
      );

      expect(result.added, hasLength(2));
      expect(result.skipped, isEmpty);
      expect(result.lines, hasLength(3));
    });
  });

  group('whole-batch validation', () {
    for (final String name in <String>['', ' \t\r\n ']) {
      test('rejects a blank name ${name.length} characters long', () {
        expect(
          () => ManualAdditions.apply(const <ShoppingLine>[], <ManualListItem>[
            const ManualListItem(name: 'Valid first'),
            ManualListItem(name: name),
          ]),
          throwsArgumentError,
        );
      });
    }

    for (final double amount in <double>[
      0,
      -0.5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test(
        'rejects explicit $amount even when that request is a duplicate',
        () {
          final List<ShoppingLine> current = <ShoppingLine>[
            ShoppingLine.manual(key: 'coffee', name: 'Coffee'),
          ];
          expect(
            () => ManualAdditions.apply(current, <ManualListItem>[
              const ManualListItem(name: 'Paper towels'),
              ManualListItem(
                name: 'Coffee',
                quantity: Quantity.of(amount, Units.item),
              ),
            ]),
            throwsArgumentError,
          );
          expect(current, hasLength(1));
        },
      );
    }
  });

  test('result lists are immutable copies', () {
    final List<ShoppingLine> lines = <ShoppingLine>[];
    final List<ManualListItem> items = <ManualListItem>[
      const ManualListItem(name: 'Coffee'),
    ];
    final List<ManualAdditionSkip> skipped = <ManualAdditionSkip>[];
    final ManualAdditionResult result = ManualAdditionResult(
      lines: lines,
      added: items,
      skipped: skipped,
    );
    lines.add(ShoppingLine.manual(key: 'milk', name: 'Milk'));
    items.clear();
    skipped.add(
      const ManualAdditionSkip(
        index: 0,
        item: ManualListItem(name: 'Milk'),
        reason: ManualAdditionSkipReason.alreadyOnList,
      ),
    );

    expect(result.lines, isEmpty);
    expect(result.added.single.name, 'Coffee');
    expect(result.skipped, isEmpty);
    expect(() => result.lines.clear(), throwsUnsupportedError);
    expect(() => result.added.clear(), throwsUnsupportedError);
    expect(() => result.skipped.clear(), throwsUnsupportedError);
  });
}
