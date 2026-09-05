import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What a line says to buy (spec §5.7).
///
/// Three numbers meet here — what the recipes wanted, what Brendan decided to
/// buy, and what is already in the freezer — and only one of them goes to the
/// shop.
void main() {
  ShoppingLine beef({double planned = 2, double? wanted, double? onHand}) =>
      ShoppingLine(
        key: 'ground beef',
        name: 'ground beef',
        planned: <Quantity>[Quantity.of(planned, Units.pound)],
        wanted: wanted == null ? null : Quantity.of(wanted, Units.pound),
        onHand: onHand == null ? null : Quantity.of(onHand, Units.pound),
      );

  group('what goes to the shop', () {
    test('the recipes, when nothing has been said about it', () {
      expect(beef().toBuy!.amountIn(Units.pound), 2);
    });

    test('less what you already have', () {
      // Brendan's example: need 2 lb, have 1 lb, buy 1 lb.
      expect(beef(onHand: 1).toBuy!.amountIn(Units.pound), 1);
    });

    test('an edited amount wins over the recipes', () {
      // 1.5 lb of beef is two packets, and that is a fact about how beef is
      // sold rather than about the recipe.
      expect(beef(planned: 1.5, wanted: 2).toBuy!.amountIn(Units.pound), 2);
    });

    test('and both together', () {
      expect(
        beef(planned: 1.5, wanted: 2, onHand: 1).toBuy!.amountIn(Units.pound),
        1,
      );
    });

    test('having more than enough means buying none, never less than none', () {
      expect(beef(onHand: 5).toBuy!.isZero, isTrue);
    });

    test('and a line that asks for less than none buys none either', () {
      // A meal built with "no lettuce" carries a −1 oz line. Flip its "Ate
      // out" switch off in the editor and the recipe stops being skipped:
      // the consolidator sums the negative, and this getter used to hand it
      // straight on whenever the cupboard had said nothing. Downstream,
      // `CartQuantity` clamps to at least one — so the export ordered one of
      // the very thing being subtracted.
      //
      // The floor belongs here, where this getter has always claimed it was.
      expect(beef(planned: -1).toBuy!.isZero, isTrue);
      expect(beef(planned: 2, wanted: -1).toBuy!.isZero, isTrue);
    });
  });

  group('the tick is the whole-line case of having some', () {
    test('ticking marks it done', () {
      expect(beef().ticked(true).isChecked, isTrue);
    });

    test('having all of it is the same as ticking it', () {
      expect(beef(onHand: 2).isChecked, isTrue);
    });

    test('having some of it is not', () {
      expect(beef(onHand: 1).isChecked, isFalse);
    });

    test('un-ticking a line you had all of clears that too', () {
      // Otherwise the on-hand amount ticks it straight back on and the tap
      // looks broken.
      final ShoppingLine had = beef(onHand: 2);
      expect(had.isChecked, isTrue);
      expect(had.ticked(false).isChecked, isFalse);
      expect(had.ticked(false).onHand, isNull);
    });

    test('but un-ticking leaves a partial amount alone', () {
      // "I have 1 of the 2" is a separate fact, and un-ticking said nothing
      // about it.
      final ShoppingLine some = beef(onHand: 1).ticked(true);
      expect(some.ticked(false).onHand!.amountIn(Units.pound), 1);
    });
  });

  group('a line the recipes could only say two ways', () {
    // 2 tbsp of butter and 50 g of it, with no density known. §5.7 says show
    // both rather than guess, so there is no single number to subtract from.
    ShoppingLine butter() => ShoppingLine(
      key: 'butter',
      name: 'butter',
      planned: <Quantity>[
        Quantity.of(2, Units.tbsp),
        Quantity.of(50, Units.gram),
      ],
    );

    test('has nothing to buy that could be written as one number', () {
      expect(butter().toBuy, isNull);
      expect(butter().isMeasurable, isFalse);
    });

    test('but can still be ticked, which is the whole point of the tick', () {
      // The case that forced the tick to be its own fact rather than derived
      // from on-hand covering the need: there is no single amount here to
      // record as had, and a line you cannot mark done is one you check twice
      // in the shop.
      expect(butter().isChecked, isFalse);
      expect(butter().ticked(true).isChecked, isTrue);
    });

    test('unless the amount is settled by hand', () {
      final ShoppingLine settled = butter().copyWith(
        wanted: Quantity.of(60, Units.gram),
      );

      expect(settled.isMeasurable, isTrue);
      expect(settled.toBuy!.amountIn(Units.gram), 60);
    });
  });
}
