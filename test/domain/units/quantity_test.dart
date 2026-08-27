import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('round trips', () {
    test('an amount survives conversion out and back', () {
      final Quantity q = Quantity.of(2.5, Units.cup);
      expect(q.amountIn(Units.cup), 2.5);
      expect(q.amountIn(Units.tbsp), closeTo(40, 1e-9));
      expect(q.amountIn(Units.tsp), closeTo(120, 1e-9));
    });

    test('g <-> kg is exact', () {
      expect(Quantity.of(1.5, Units.kilogram).amountIn(Units.gram), 1500);
      expect(Quantity.of(250, Units.gram).amountIn(Units.kilogram), 0.25);
    });
  });

  group('no stored drift (spec §9.1)', () {
    test('four quarter-cups sum to exactly one cup', () {
      final Quantity quarter = Quantity.of(0.25, Units.cup);
      final Quantity total = quarter + quarter + quarter + quarter;
      expect(total.amountIn(Units.cup), 1.0);
      expect(total, Quantity.of(1, Units.cup));
    });

    test('scaling by 4 then by 0.25 returns the original value', () {
      final Quantity q = Quantity.of(0.25, Units.cup);
      expect(q.scaledBy(4).scaledBy(0.25), q);
    });

    test('three thirds of a cup sum to one cup', () {
      final Quantity third = Quantity.of(1, Units.cup).scaledBy(1 / 3);
      expect((third + third + third).amountIn(Units.cup), closeTo(1.0, 1e-12));
    });
  });

  group('arithmetic', () {
    test('addition keeps the left operand display unit', () {
      final Quantity sum =
          Quantity.of(2, Units.tbsp) + Quantity.of(30, Units.millilitre);
      expect(sum.preferredUnit, Units.tbsp);
      expect(sum.canonicalAmount, closeTo(59.5735295625, 1e-9));
    });

    test('addition adopts the right operand unit when the left has none', () {
      const Quantity bare = Quantity.canonical(
        canonicalAmount: 100,
        kind: UnitKind.volume,
      );
      expect((bare + Quantity.of(1, Units.cup)).preferredUnit, Units.cup);
    });

    test('scaling never rounds', () {
      expect(
        Quantity.of(1, Units.tsp).scaledBy(1 / 3).canonicalAmount,
        Units.tsp.toCanonical / 3,
      );
    });
  });

  group('kind safety', () {
    test('reading volume in a mass unit throws', () {
      expect(
        () => Quantity.of(1, Units.cup).amountIn(Units.gram),
        throwsArgumentError,
      );
    });

    test('adding across kinds throws', () {
      expect(
        () => Quantity.of(1, Units.cup) + Quantity.of(1, Units.gram),
        throwsArgumentError,
      );
    });
  });
}
