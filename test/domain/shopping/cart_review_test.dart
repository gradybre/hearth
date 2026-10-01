import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/cart_quantity.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  ShoppingLine line(Quantity need, {Quantity? have, bool unresolved = false}) =>
      ShoppingLine(
        key: 'sauce',
        name: 'sauce',
        foodId: 'sauce',
        planned: <Quantity>[need],
        onHand: have,
        hasUnquantified: unresolved,
      );
  Food food({
    Quantity? pack,
    String id = '123456789',
    String name = 'Sauce',
    String? brand,
    DateTime? updatedAt,
    double? density,
  }) => Food(
    id: 'sauce',
    householdId: 'home',
    name: name,
    brand: brand,
    source: FoodSource.manual,
    servingOptions: const <ServingOption>[],
    packSize: pack,
    walmartItemId: id,
    updatedAt: updatedAt,
    gramsPerMillilitre: density,
  );

  test('review prefills known whole packs after on-hand subtraction', () {
    final CartQuantityEstimate result = CartQuantity.forReview(
      line: line(
        Quantity.of(1000, Units.gram),
        have: Quantity.of(400, Units.gram),
      ),
      pack: Quantity.of(400, Units.gram),
    )!;
    expect(result.count, 2);
    expect(result.wasCapped, isFalse);
  });

  test('floating-point tails do not invent a second pack', () {
    final CartQuantityEstimate result = CartQuantity.forReview(
      line: line(Quantity.of(.1 + .2, Units.pound)),
      pack: Quantity.of(.3, Units.pound),
    )!;
    expect(result.count, 1);
  });

  test('review never treats a scoop as a retail container', () {
    expect(
      CartQuantity.forReview(
        line: line(Quantity.of(3, Units.scoop)),
        pack: Quantity.of(1, Units.container),
      ),
      isNull,
    );
    expect(
      CartQuantity.forReview(
        line: line(Quantity.of(18, Units.item)),
        pack: Quantity.of(12, Units.item),
      )!.count,
      2,
    );
  });

  test('review cannot subtract containers from scoops', () {
    expect(
      CartQuantity.forReview(
        line: line(
          Quantity.of(12, Units.scoop),
          have: Quantity.of(1, Units.container),
        ),
        pack: Quantity.of(12, Units.scoop),
      ),
      isNull,
    );
  });

  test('cap is explicit, including an overflowing but positive ratio', () {
    for (final double need in <double>[24.01, 1e308]) {
      final CartQuantityEstimate result = CartQuantity.forReview(
        line: line(Quantity.of(need, Units.gram)),
        pack: Quantity.of(need > 100 ? 1e-308 : 1, Units.gram),
      )!;
      expect(result.count, 24);
      expect(result.wasCapped, isTrue);
    }
    expect(
      CartQuantity.forReview(
        line: line(Quantity.of(24, Units.gram)),
        pack: Quantity.of(1, Units.gram),
      )!.wasCapped,
      isFalse,
    );
  });

  test('unknown, invalid and incomplete amounts have no suggested count', () {
    final ShoppingLine measured = line(Quantity.of(600, Units.gram));
    for (final Quantity? pack in <Quantity?>[
      null,
      Quantity.of(1, Units.cup),
      Quantity.of(0, Units.gram),
      Quantity.of(-1, Units.gram),
      Quantity.of(double.nan, Units.gram),
      Quantity.of(double.infinity, Units.gram),
    ]) {
      expect(CartQuantity.forReview(line: measured, pack: pack), isNull);
    }
    expect(
      CartQuantity.forReview(line: line(Quantity.of(6, Units.item))),
      isNull,
      reason: 'six servings do not prove six retail products',
    );
    expect(
      CartQuantity.forReview(
        line: line(Quantity.of(600, Units.gram), unresolved: true),
        pack: Quantity.of(400, Units.gram),
      ),
      isNull,
    );
    expect(
      CartQuantity.forReview(
        line: line(Quantity.of(0, Units.gram)),
        pack: Quantity.of(400, Units.gram),
      ),
      isNull,
    );
  });

  test(
    'review evidence binds exact amounts, authored units and saved product',
    () {
      String evidence(ShoppingLine item, Food saved) => ShoppingExportSource(
        lines: <ShoppingLine>[item],
        foods: <String, Food>{'sauce': saved},
      ).fingerprint;
      final ShoppingLine original = line(Quantity.of(600, Units.gram));
      final Food saved = food(pack: Quantity.of(400, Units.gram));
      final String before = evidence(original, saved);
      expect(
        evidence(
          original,
          food(pack: Quantity.of(400, Units.gram), updatedAt: DateTime(2026)),
        ),
        before,
      );
      for (final Food changed in <Food>[
        food(pack: Quantity.of(401, Units.gram)),
        food(pack: saved.packSize, id: '987654321'),
        food(pack: saved.packSize, name: 'New sauce'),
        food(pack: saved.packSize, brand: 'New brand'),
        food(pack: saved.packSize, density: 1.2),
      ]) {
        expect(evidence(original, changed), isNot(before));
      }
      for (final ShoppingLine changed in <ShoppingLine>[
        line(Quantity.of(600.000001, Units.gram)),
        line(Quantity.of(.6, Units.kilogram)),
        original.ticked(true),
        original.copyWith(onHand: Quantity.of(1, Units.gram)),
      ]) {
        expect(evidence(changed, saved), isNot(before));
      }
    },
  );

  test('captured collection membership and evidence cannot be mutated', () {
    final List<ShoppingLine> lines = <ShoppingLine>[
      line(Quantity.of(600, Units.gram)),
    ];
    final Map<String, Food> foods = <String, Food>{'sauce': food()};
    final ShoppingExportSource captured = ShoppingExportSource(
      lines: lines,
      foods: foods,
    );
    final String evidence = captured.fingerprint;
    lines.clear();
    foods.clear();
    expect(captured.lines, hasLength(1));
    expect(captured.foods, hasLength(1));
    expect(captured.fingerprint, evidence);
    expect(() => captured.lines.clear(), throwsUnsupportedError);
    expect(() => captured.foods.clear(), throwsUnsupportedError);
  });
}
