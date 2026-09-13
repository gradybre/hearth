import 'package:hearth/domain/shopping/pack_display.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What a line says when the thing is sold in packs (spec §5.7).
void main() {
  ShoppingLine line(Quantity planned, {Quantity? onHand}) => ShoppingLine(
    key: 'f-sauce',
    name: 'Marinara Sauce',
    planned: <Quantity>[planned],
    onHand: onHand,
    foodId: 'f-sauce',
  );

  final Quantity jar = Quantity.of(24, Units.ounce);

  group('a thing sold in jars', () {
    test('says how many jars, not how many pounds', () {
      // The complaint this exists for: a ragu wanting sixty-four ounces of
      // Rao's read "4 lb", which is arithmetically perfect and useless at a
      // shelf stacked with 24-ounce jars.
      expect(
        PackDisplay.forLine(
          line: line(Quantity.of(64, Units.ounce)),
          pack: jar,
        ),
        '3 × 24 oz',
      );
    });

    test('and rounds up, because coming home short costs another trip', () {
      expect(
        PackDisplay.forLine(
          line: line(Quantity.of(25, Units.ounce)),
          pack: jar,
        ),
        '2 × 24 oz',
      );
    });

    test('one pack is not a multiplication', () {
      // "1 × 24 oz" reads as arithmetic somebody forgot to finish.
      expect(
        PackDisplay.forLine(
          line: line(Quantity.of(20, Units.ounce)),
          pack: jar,
        ),
        '24 oz',
      );
    });

    test('and what the recipes asked for is still said, where it differs', () {
      // Three jars is seventy-two ounces and the ragu wants sixty-four. A
      // line that only shows the packs has quietly rounded up, and a shopper
      // who cannot see the rounding cannot judge it.
      expect(
        PackDisplay.shortfall(
          line: line(Quantity.of(64, Units.ounce)),
          pack: jar,
        ),
        'needs 64 oz',
      );
    });

    test('but not when the packs come to exactly what is needed', () {
      expect(
        PackDisplay.shortfall(
          line: line(Quantity.of(48, Units.ounce)),
          pack: jar,
        ),
        isNull,
      );
    });

    test('and what is already in the cupboard comes off first', () {
      // Forty-eight needed less twenty-four had is one jar, not two.
      expect(
        PackDisplay.forLine(
          line: line(
            Quantity.of(48, Units.ounce),
            onHand: Quantity.of(24, Units.ounce),
          ),
          pack: jar,
        ),
        '24 oz',
      );
    });
  });

  group('and everything else is left alone', () {
    test('a food with no pack size keeps its weight', () {
      // Null rather than a fallback, so the caller goes on showing what it
      // already had. This only ever replaces an answer that was correct.
      expect(
        PackDisplay.forLine(line: line(Quantity.of(2, Units.pound))),
        isNull,
      );
    });

    test('a pack measured in a different kind cannot divide the need', () {
      // Six of something counted does not go into a jar of sauce, and asking
      // would throw rather than answer.
      expect(
        PackDisplay.forLine(
          line: line(Quantity.of(64, Units.ounce)),
          pack: Quantity.of(1, Units.item),
        ),
        isNull,
      );
    });

    test('a line already covered by the cupboard has nothing to pick up', () {
      // A *ticked* line is different: it keeps its amount on screen, and this
      // only decides how that amount reads.
      expect(
        PackDisplay.forLine(
          line: line(
            Quantity.of(24, Units.ounce),
            onHand: Quantity.of(24, Units.ounce),
          ),
          pack: jar,
        ),
        isNull,
      );
    });

    test('and a line the recipes said two ways has no single amount to '
        'divide', () {
      final ShoppingLine mixed = ShoppingLine(
        key: 'f-butter',
        name: 'Butter',
        planned: <Quantity>[
          Quantity.of(2, Units.tbsp),
          Quantity.of(50, Units.gram),
        ],
      );
      expect(PackDisplay.forLine(line: mixed, pack: jar), isNull);
    });
  });
}
