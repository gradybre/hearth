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

  group('against the pack sizes that actually arrive', () {
    // Until this week no food in the library had a pack size at all, so none
    // of this arithmetic had ever run on real data. Open Food Facts and USDA
    // both supply one now (b3ec3c3, 8763ab3), and these are the shapes their
    // data takes.
    final Quantity jar = Quantity.of(24, Units.ounce);

    test('a ragu wanting 64 oz of a 24 oz jar buys three', () {
      // The complaint the whole pack thread exists for. Two jars is 48 and
      // short; three is 72 and the eight over are shown beside it.
      expect(
        quantity(line(<Quantity>[Quantity.of(64, Units.ounce)]), pack: jar),
        3,
      );
    });

    test('and one that divides exactly buys exactly that, across units', () {
      // A pack is published in the shop's units and a recipe is written in
      // the cook's. 1.5 lb is 24 oz to the gram, and a jar and a half is not
      // a thing you can buy — so this has to come out at one, not two.
      expect(
        quantity(line(<Quantity>[Quantity.of(1.5, Units.pound)]), pack: jar),
        1,
      );
      expect(
        quantity(line(<Quantity>[Quantity.of(48, Units.ounce)]), pack: jar),
        2,
      );
    });

    test('a need that was added up does not buy a spare pack', () {
      // Regression. A line's amount is a *sum* — `IngredientConsolidator`
      // adds every recipe's ask together — and 0.1 lb plus 0.2 lb is
      // 0.30000000000000004 lb. Divided by a 0.3 lb pack that is
      // 1.0000000000000002 packs, and a bare ceil() buys two of them.
      //
      // The list showed the same nonsense: "2 × 0.3 lb · needs 0.3 lb".
      final Quantity summed =
          Quantity.of(0.1, Units.pound) + Quantity.of(0.2, Units.pound);
      expect(
        quantity(line(<Quantity>[summed]), pack: Quantity.of(0.3, Units.pound)),
        1,
      );
    });

    test('nor does one the cupboard was taken off', () {
      // Regression, the same rounding from the other direction:
      // 2.2 lb less 0.2 lb is 2.0000000000000004 lb, which is three 1 lb
      // packs to a bare ceil().
      expect(
        quantity(
          line(<Quantity>[
            Quantity.of(2.2, Units.pound),
          ], onHand: Quantity.of(0.2, Units.pound)),
          pack: Quantity.of(1, Units.pound),
        ),
        2,
      );
    });

    test('but a hair over a whole pack still rounds up', () {
      // The slack is a double's last bits, not a shelf's worth. A gram over
      // two jars is still three jars.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(48 * 28.349523125 + 1, Units.gram)]),
          pack: jar,
        ),
        3,
      );
    });

    test('a countable thing sold by the dozen is one box', () {
      // Six eggs against a twelve-count pack. The kinds match, so the pack
      // branch answers and the count branch never sees it.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(6, Units.item)]),
          pack: Quantity.of(12, Units.item),
        ),
        1,
      );
      expect(
        quantity(
          line(<Quantity>[Quantity.of(18, Units.item)]),
          pack: Quantity.of(12, Units.item),
        ),
        2,
      );
    });

    test('and a weight on a counted line cannot divide it', () {
      // A food whose pack size arrived as a weight, on a line the recipes
      // counted. The kinds disagree, so this falls through to the count —
      // the same answer it gave before any pack size existed.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(6, Units.item)]),
          pack: Quantity.of(680, Units.gram),
        ),
        6,
      );
    });

    test('a line the cupboard already covers asks for one, never zero', () {
      // It should not reach an export at all — `exportableLines` drops it —
      // but a cart entry of zero is a nonsense Walmart would reject, and the
      // pack branch must not be what introduces one.
      expect(
        quantity(
          line(<Quantity>[
            Quantity.of(24, Units.ounce),
          ], onHand: Quantity.of(24, Units.ounce)),
          pack: jar,
        ),
        1,
      );
    });

    test('and a pack size read wrong cannot fill a van', () {
      // A parser that reads "24 oz/680 g" as a fraction of an ounce is a
      // redeploy away, and the cap is what stands between that and a
      // delivery. It holds with the pack arriving from a source rather than
      // from a typing hand.
      expect(
        quantity(
          line(<Quantity>[Quantity.of(64, Units.ounce)]),
          pack: Quantity.of(0.68, Units.gram),
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
