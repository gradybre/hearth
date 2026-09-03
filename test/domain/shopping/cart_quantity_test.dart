import 'package:hearth/domain/shopping/cart_quantity.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// How many of a product go in the cart (spec §5.7).
void main() {
  ShoppingLine line(List<Quantity> planned, {Quantity? onHand}) => ShoppingLine(
    key: 'k',
    name: 'ground beef',
    planned: planned,
    onHand: onHand,
  );

  int quantity(ShoppingLine l, {Quantity? pack}) =>
      CartQuantity.forLine(line: l, pack: pack);

  group('with a pack size, whole packs rounded up', () {
    test('3 lb against 1 lb packs is three of them', () {
      expect(
        quantity(
          line(<Quantity>[Quantity.of(3, Units.pound)]),
          pack: Quantity.of(1, Units.pound),
        ),
        3,
      );
    });

    test('3 lb against 2 lb packs is two, not one and a half', () {
      // Up, never down: coming home short costs another trip, and a spare
      // pack of something you buy anyway costs nothing.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(3, Units.pound)]),
          pack: Quantity.of(2, Units.pound),
        ),
        2,
      );
    });

    test('and units inside a kind convert on their own', () {
      // 500 g needed, 1 lb packs. A pound is 453.6 g, so one pack is not
      // enough and the answer is two — which is the rounding doing its job
      // across units, with no conversion call and nothing to throw.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(500, Units.gram)]),
          pack: Quantity.of(1, Units.pound),
        ),
        2,
      );

      // And a need that genuinely fits inside one pack asks for one.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(400, Units.gram)]),
          pack: Quantity.of(1, Units.pound),
        ),
        1,
      );
    });

    test('what you already have comes off first', () {
      expect(
        quantity(
          line(<Quantity>[
            Quantity.of(3, Units.pound),
          ], onHand: Quantity.of(1, Units.pound)),
          pack: Quantity.of(1, Units.pound),
        ),
        2,
      );
    });

    test('a pack in the wrong kind is ignored rather than fatal', () {
      // Millilitres of a thing measured in pounds. Quantity.amountIn would
      // raise; this falls through to the plain answer instead.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(3, Units.pound)]),
          pack: Quantity.of(500, Units.millilitre),
        ),
        1,
      );
    });

    test('a mistyped pack size cannot order two hundred packets', () {
      // 0.01 lb packs of a 3 lb need is 300. The cap is the only thing
      // standing between a typo and a delivery.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(3, Units.pound)]),
          pack: Quantity.of(0.01, Units.pound),
        ),
        CartQuantity.cap,
      );
    });
  });

  group('without one', () {
    test('a countable line asks for its count', () {
      expect(quantity(line(<Quantity>[Quantity.of(3, Units.item)])), 3);
    });

    test('a weight cannot be guessed at, so it asks for one', () {
      expect(quantity(line(<Quantity>[Quantity.of(2, Units.pound)])), 1);
    });

    test('and so does a line written two ways at once', () {
      // Unmeasurable — toBuy is null and there is nothing to divide.
      expect(
        quantity(
          line(<Quantity>[
            Quantity.of(2, Units.tbsp),
            Quantity.of(50, Units.gram),
          ]),
        ),
        1,
      );
    });

    test('a line already covered still asks for one, not zero', () {
      // It should not be in the export at all — but if it is, a cart entry of
      // zero is a nonsense Walmart would reject.
      expect(
        quantity(
          line(<Quantity>[
            Quantity.of(1, Units.pound),
          ], onHand: Quantity.of(1, Units.pound)),
        ),
        1,
      );
    });
  });
}
