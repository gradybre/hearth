import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_edit.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What a sentence does to the list (spec §5.7).
///
/// Operations rather than a rewritten list: a model handed the whole thing
/// back could drop a line by forgetting it, and a shopping list that quietly
/// loses an item is worse than one that refuses an instruction — you find out
/// about the refusal in the app and about the loss in the shop.
void main() {
  ShoppingLine beef() => ShoppingLine(
    key: 'ground beef',
    name: 'ground beef',
    planned: <Quantity>[Quantity.of(2, Units.pound)],
  );

  List<ShoppingLine> apply(ShoppingEdit edit, [List<ShoppingLine>? lines]) =>
      ShoppingEdits.apply(lines ?? <ShoppingLine>[beef()], <ShoppingEdit>[
        edit,
      ]);

  group('adding', () {
    test('something new arrives as a manual line', () {
      // Manual, so a rebuild cannot take it away again.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      );

      expect(lines.last.name, 'Coffee');
      expect(lines.last.isManual, isTrue);
    });

    test('with an amount, if one was given', () {
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.add,
          name: 'Rice',
          amount: 2,
          unitId: 'lb',
        ),
      );

      expect(lines.last.planned.single.amountIn(Units.pound), 2);
    });

    test('something already there is not listed twice', () {
      // "Add another two pounds of beef" is about the beef.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.add,
          name: 'ground beef',
          amount: 3,
          unitId: 'lb',
        ),
      );

      expect(lines, hasLength(1));
      expect(lines.single.toBuy!.amountIn(Units.pound), 3);
    });
  });

  group('changing a line', () {
    test('an amount asked for is the shopper\'s, not the recipes\'', () {
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.setAmount,
          name: 'ground beef',
          amount: 3,
          unitId: 'lb',
        ),
      );

      expect(lines.single.isEdited, isTrue);
      expect(lines.single.planned.single.amountIn(Units.pound), 2);
    });

    test('"I have some already" subtracts rather than ticking', () {
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.setOnHand,
          name: 'ground beef',
          amount: 1,
          unitId: 'lb',
        ),
      );

      expect(lines.single.toBuy!.amountIn(Units.pound), closeTo(1, 1e-9));
      expect(lines.single.isChecked, isFalse);
    });

    test('ticking and un-ticking', () {
      expect(
        apply(
          const ShoppingEdit(kind: ShoppingEditKind.check, name: 'ground beef'),
        ).single.isChecked,
        isTrue,
      );
    });

    test('removing takes it off', () {
      expect(
        apply(
          const ShoppingEdit(
            kind: ShoppingEditKind.remove,
            name: 'ground beef',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('finding the line somebody meant', () {
    test('"beef" finds the ground beef', () {
      // The model repeats what was said rather than quoting the list, and
      // nobody says "ground beef" twice in one conversation.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(kind: ShoppingEditKind.remove, name: 'beef'),
      );

      expect(lines, isEmpty);
    });

    test('and so does "the beef", which is how anybody says it', () {
      // What the live model actually sent back, asked "I already have a pound
      // of the beef": it echoes the sentence, article and all. A substring
      // check in either direction misses that, so the instruction silently
      // did nothing.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(kind: ShoppingEditKind.remove, name: 'the beef'),
      );

      expect(lines, isEmpty);
    });

    test('a plural finds the singular', () {
      // "Take the apples off" against a line called "Honeycrisp Apple".
      final List<ShoppingLine> lines = ShoppingEdits.apply(
        <ShoppingLine>[beef().copyWith(name: 'Honeycrisp Apple')],
        const <ShoppingEdit>[
          ShoppingEdit(kind: ShoppingEditKind.remove, name: 'apples'),
        ],
      );

      expect(lines, isEmpty);
    });

    test('filler words alone match nothing', () {
      // "Remove that" names no line, and picking one at random would be
      // worse than doing nothing.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(kind: ShoppingEditKind.remove, name: 'the'),
      );

      expect(lines, hasLength(1));
    });

    test('a line that is not there is not an error', () {
      // Inventing a line to delete, or failing the whole batch, are both
      // worse than a sentence quietly doing nothing.
      final List<ShoppingLine> lines = apply(
        const ShoppingEdit(kind: ShoppingEditKind.remove, name: 'saffron'),
      );

      expect(lines, hasLength(1));
    });
  });

  test('several instructions apply in order', () {
    final List<ShoppingLine> lines = ShoppingEdits.apply(
      <ShoppingLine>[beef()],
      const <ShoppingEdit>[
        ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
        ShoppingEdit(kind: ShoppingEditKind.check, name: 'Coffee'),
        ShoppingEdit(kind: ShoppingEditKind.remove, name: 'beef'),
      ],
    );

    expect(lines.single.name, 'Coffee');
    expect(lines.single.isChecked, isTrue);
  });

  group('an amount set on a typed-in line is recorded as an ask', () {
    // `planned` is the sum of a line's contributions and nothing else may
    // set it (see ShoppingContributions). Writing the amount straight into
    // `planned` leaves the two disagreeing — the line says two pounds and
    // nobody asked for any — and the next thing to settle the line would
    // recompute the total back to nothing.
    test('so the line can still say where its amount came from', () {
      final List<ShoppingLine> after = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.setAmount,
          name: 'Coffee',
          amount: 2,
          unitId: 'lb',
        ),
        <ShoppingLine>[ShoppingLine.manual(key: 'coffee', name: 'Coffee')],
      );

      expect(after.single.planned.single.amountIn(Units.pound), 2);
      expect(after.single.contributions.single.kind, ShoppingSourceKind.manual);
      expect(
        after.single.contributions.single.quantities.single.amountIn(
          Units.pound,
        ),
        2,
      );
    });

    test('and settling it again does not lose the amount', () {
      final List<ShoppingLine> after = apply(
        const ShoppingEdit(
          kind: ShoppingEditKind.setAmount,
          name: 'Coffee',
          amount: 2,
          unitId: 'lb',
        ),
        <ShoppingLine>[ShoppingLine.manual(key: 'coffee', name: 'Coffee')],
      );
      final ShoppingLine resettled = ShoppingContributions.settle(
        after.single,
        contributions: after.single.contributions,
      );
      expect(resettled.planned.single.amountIn(Units.pound), 2);
    });
  });
}
