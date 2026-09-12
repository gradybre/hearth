import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_list_merge.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What each source asked for, and what adding them up means (spec §5.7).
void main() {
  ShoppingContribution plan(double pounds) => ShoppingContribution(
    kind: ShoppingSourceKind.plan,
    quantities: <Quantity>[Quantity.of(pounds, Units.pound)],
  );

  ShoppingContribution recipe(
    String id,
    double pounds, {
    String? label,
    double? servings,
  }) => ShoppingContribution(
    kind: ShoppingSourceKind.recipe,
    refId: id,
    label: label,
    servings: servings,
    quantities: <Quantity>[Quantity.of(pounds, Units.pound)],
  );

  ShoppingLine beef({
    List<ShoppingContribution> contributions = const <ShoppingContribution>[],
  }) => ShoppingContributions.settle(
    const ShoppingLine(
      key: 'f-beef',
      name: 'ground beef',
      planned: <Quantity>[],
      foodId: 'f-beef',
    ),
    contributions: contributions,
  );

  double poundsOf(ShoppingLine line) =>
      line.planned.single.amountIn(Units.pound);

  group('a line is the sum of what was asked for', () {
    test('one ask is the whole of it', () {
      expect(poundsOf(beef(contributions: <ShoppingContribution>[plan(1)])), 1);
    });

    test('two asks add up', () {
      final ShoppingLine line = beef(
        contributions: <ShoppingContribution>[plan(1), recipe('r-bol', 0.5)],
      );
      expect(poundsOf(line), 1.5);
      expect(line.contributions, hasLength(2));
    });

    test('and the total is recomputed, never carried', () {
      // The invariant the whole type exists for: `planned` is not a number
      // anybody sets, it is what the asks come to. A line that could hold a
      // stale total is a line that can disagree with its own arithmetic.
      final ShoppingLine wrong = ShoppingContributions.settle(
        ShoppingLine(
          key: 'f-beef',
          name: 'ground beef',
          planned: <Quantity>[Quantity.of(99, Units.pound)],
        ),
        contributions: <ShoppingContribution>[plan(1)],
      );
      expect(poundsOf(wrong), 1);
    });

    test('an ask with nothing in it is not kept', () {
      final ShoppingLine line = beef(
        contributions: <ShoppingContribution>[
          plan(1),
          const ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'r-empty',
            quantities: <Quantity>[],
          ),
        ],
      );
      expect(line.contributions, hasLength(1));
    });

    test('and "to taste" anywhere marks the whole line', () {
      // One unquantified contributor understates the total, which is what
      // the flag is for. It has to survive being one ask among several.
      final ShoppingLine line = beef(
        contributions: <ShoppingContribution>[
          plan(1),
          const ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'r-salt',
            quantities: <Quantity>[],
            hasUnquantified: true,
          ),
        ],
      );
      expect(line.hasUnquantified, isTrue);
    });
  });

  group('adding the same thing twice', () {
    test('is one ask for the total, not two to disentangle later', () {
      final List<ShoppingContribution> merged = ShoppingContributions.merge(
        <ShoppingContribution>[recipe('r-chilli', 1, servings: 4)],
        <ShoppingContribution>[recipe('r-chilli', 1, servings: 4)],
      );

      expect(merged, hasLength(1));
      expect(merged.single.servings, 8);
      expect(merged.single.quantities.single.amountIn(Units.pound), 2);
    });

    test('while a different recipe is its own ask', () {
      final List<ShoppingContribution> merged = ShoppingContributions.merge(
        <ShoppingContribution>[recipe('r-chilli', 1)],
        <ShoppingContribution>[recipe('r-bol', 1)],
      );
      expect(merged, hasLength(2));
    });

    test('and one ask can be taken back off', () {
      final List<ShoppingContribution> merged = ShoppingContributions.merge(
        <ShoppingContribution>[plan(1)],
        <ShoppingContribution>[recipe('r-bol', 2)],
      );
      final List<ShoppingContribution> without = ShoppingContributions.without(
        merged,
        'recipe:r-bol',
      );

      expect(without, hasLength(1));
      expect(without.single.kind, ShoppingSourceKind.plan);
    });
  });

  group('a rebuild owns the plan and nothing else', () {
    test('the plan\'s share is replaced, the rest is left alone', () {
      final List<ShoppingContribution> after =
          ShoppingContributions.replacePlan(<ShoppingContribution>[
            plan(1),
            recipe('r-bol', 2),
          ], plan(5));

      expect(after, hasLength(2));
      expect(
        after
            .firstWhere(
              (ShoppingContribution c) => c.kind == ShoppingSourceKind.plan,
            )
            .quantities
            .single
            .amountIn(Units.pound),
        5,
      );
      expect(
        after
            .firstWhere(
              (ShoppingContribution c) => c.kind == ShoppingSourceKind.recipe,
            )
            .quantities
            .single
            .amountIn(Units.pound),
        2,
      );
    });

    test('and a plan that no longer wants it drops only its own share', () {
      final List<ShoppingContribution> after =
          ShoppingContributions.replacePlan(<ShoppingContribution>[
            plan(1),
            recipe('r-bol', 2),
          ], null);
      expect(after, hasLength(1));
      expect(after.single.kind, ShoppingSourceKind.recipe);
    });
  });

  group('a list written before any of this existed', () {
    test('reads as the plan having asked for the whole line', () {
      // Which is exactly what it was: the plan owned every number on the
      // list, so a rebuild is still entitled to replace the lot.
      final ShoppingLine old = ShoppingLine(
        key: 'f-beef',
        name: 'ground beef',
        planned: <Quantity>[Quantity.of(2, Units.pound)],
      );
      final List<ShoppingContribution> read = ShoppingContributions.legacy(old);

      expect(read.single.kind, ShoppingSourceKind.plan);
      expect(read.single.quantities.single.amountIn(Units.pound), 2);
    });

    test('but a typed-in line reads as typed in, so a rebuild cannot take '
        'it', () {
      // Reading a manual line as the plan's would hand the plan a vote on
      // something it never put there — and the first rebuild after an update
      // would quietly clear the coffee off the list.
      final ShoppingLine coffee = ShoppingLine.manual(
        key: 'coffee',
        name: 'Coffee',
      );
      final List<ShoppingContribution> read = ShoppingContributions.legacy(
        coffee.copyWith(planned: <Quantity>[Quantity.of(1, Units.item)]),
      );
      expect(read.single.kind, ShoppingSourceKind.manual);
    });

    test('and an empty line reads as nobody having asked', () {
      const ShoppingLine blank = ShoppingLine(
        key: 'x',
        name: 'x',
        planned: <Quantity>[],
      );
      expect(ShoppingContributions.legacy(blank), isEmpty);
    });
  });

  group('the whole point: a rebuild does not undo what you added', () {
    ShoppingLine planned(double pounds) =>
        ShoppingContributions.settle(
          const ShoppingLine(
            key: 'f-beef',
            name: 'ground beef',
            planned: <Quantity>[],
            foodId: 'f-beef',
          ),
          contributions: <ShoppingContribution>[],
        ).copyWith(
          contributions: <ShoppingContribution>[plan(pounds)],
          planned: <Quantity>[Quantity.of(pounds, Units.pound)],
        );

    test('a recipe added by hand survives, and both still count', () {
      // Brendan adds bolognese for 4 on Saturday; the plan already wanted a
      // pound for Tuesday's chilli. Rebuilding the plan must not halve the
      // beef, and must not double it either.
      final ShoppingLine onTheList = ShoppingContributions.settle(
        planned(1),
        contributions: <ShoppingContribution>[
          plan(1),
          recipe('r-bol', 2, label: 'Bolognese', servings: 4),
        ],
      );
      expect(poundsOf(onTheList), 3);

      final List<ShoppingLine> after = ShoppingListMerge.into(
        <ShoppingLine>[onTheList],
        <ShoppingLine>[planned(1)],
      );

      expect(after, hasLength(1));
      expect(poundsOf(after.single), 3, reason: 'the bolognese was forgotten');
      expect(
        after.single.contributions.map((ShoppingContribution c) => c.sourceKey),
        <String>['plan', 'recipe:r-bol'],
      );
    });

    test('and when the plan stops wanting it, what you added remains', () {
      final ShoppingLine onTheList = ShoppingContributions.settle(
        planned(1),
        contributions: <ShoppingContribution>[
          plan(1),
          recipe('r-bol', 2, label: 'Bolognese'),
        ],
      );

      final List<ShoppingLine> after = ShoppingListMerge.into(<ShoppingLine>[
        onTheList,
      ], const <ShoppingLine>[]);

      expect(after, hasLength(1));
      expect(poundsOf(after.single), 2, reason: 'only the plan should go');
    });

    test('and a line that was only ever the plan\'s still goes', () {
      final List<ShoppingLine> after = ShoppingListMerge.into(<ShoppingLine>[
        planned(1),
      ], const <ShoppingLine>[]);
      expect(after, isEmpty);
    });
  });
}
