import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/domain/units/unit_converter.dart';
import 'package:test/test.dart';

void main() {
  group('same-kind conversion', () {
    test('tsp <-> tbsp <-> cup', () {
      expect(
        UnitConverter.convert(3, Units.tsp, Units.tbsp),
        closeTo(1, 1e-12),
      );
      expect(
        UnitConverter.convert(1, Units.cup, Units.tbsp),
        closeTo(16, 1e-12),
      );
      expect(
        UnitConverter.convert(1, Units.cup, Units.tsp),
        closeTo(48, 1e-12),
      );
      expect(
        UnitConverter.convert(2, Units.tbsp, Units.flOz),
        closeTo(1, 1e-12),
      );
    });

    test('g <-> kg', () {
      expect(UnitConverter.convert(1500, Units.gram, Units.kilogram), 1.5);
      expect(UnitConverter.convert(0.25, Units.kilogram, Units.gram), 250);
    });

    test('refuses to cross kinds', () {
      expect(
        () => UnitConverter.convert(1, Units.cup, Units.gram),
        throwsArgumentError,
      );
    });
  });

  group('cross-kind conversion (spec §5.2)', () {
    test('volume -> weight uses the density table', () {
      final ConversionResult result = UnitConverter.crossKind(
        Quantity.of(1, Units.cup),
        UnitKind.mass,
        ingredient: 'all-purpose flour',
      );
      expect(result.isExact, isTrue);
      // 1 cup of AP flour is the standard 125 g.
      expect(result.quantity.amountIn(Units.gram), closeTo(125, 0.5));
    });

    test('weight -> volume inverts cleanly', () {
      final ConversionResult result = UnitConverter.crossKind(
        Quantity.of(125, Units.gram),
        UnitKind.volume,
        ingredient: 'all-purpose flour',
      );
      expect(result.isExact, isTrue);
      expect(result.quantity.amountIn(Units.cup), closeTo(1, 0.01));
    });

    test('an explicit density overrides the table', () {
      final ConversionResult result = UnitConverter.crossKind(
        Quantity.of(100, Units.millilitre),
        UnitKind.mass,
        ingredient: 'water',
        gramsPerMillilitre: 2,
      );
      expect(result.quantity.amountIn(Units.gram), 200);
    });

    test('unknown density flags instead of guessing', () {
      final ConversionResult result = UnitConverter.crossKind(
        Quantity.of(1, Units.cup),
        UnitKind.mass,
        ingredient: 'chopped fennel fronds',
      );
      expect(result.densityMissing, isTrue);
      expect(result.isExact, isFalse);
      // The value comes back untouched — no invented number.
      expect(result.quantity, Quantity.of(1, Units.cup));
    });

    test('counts never convert to weight', () {
      final ConversionResult result = UnitConverter.crossKind(
        Quantity.of(3, Units.item),
        UnitKind.mass,
        ingredient: 'egg',
      );
      expect(result.densityMissing, isTrue);
    });

    test('same-kind requests pass straight through', () {
      final Quantity q = Quantity.of(2, Units.cup);
      final ConversionResult result = UnitConverter.crossKind(
        q,
        UnitKind.volume,
      );
      expect(result.isExact, isTrue);
      expect(result.quantity, q);
    });
  });

  group('display unit selection', () {
    test('promotes 3 tsp to 1 tbsp (spec §5.2)', () {
      final Quantity q = Quantity.of(3, Units.tsp);
      expect(UnitConverter.displayUnitFor(q), Units.tbsp);
      expect(
        UnitConverter.normalise(q).amountIn(Units.tbsp),
        closeTo(1, 1e-12),
      );
    });

    test('promotes 16 tbsp to 1 cup', () {
      expect(
        UnitConverter.displayUnitFor(Quantity.of(16, Units.tbsp)),
        Units.cup,
      );
    });

    test('keeps half a cup as a cup rather than 8 tbsp', () {
      expect(
        UnitConverter.displayUnitFor(Quantity.of(0.5, Units.cup)),
        Units.cup,
      );
    });

    test('demotes an eighth of a cup to tbsp', () {
      expect(
        UnitConverter.displayUnitFor(Quantity.of(0.125, Units.cup)),
        Units.tbsp,
      );
    });

    test('leaves a single teaspoon alone', () {
      expect(
        UnitConverter.displayUnitFor(Quantity.of(1, Units.tsp)),
        Units.tsp,
      );
      expect(
        UnitConverter.displayUnitFor(Quantity.of(0.5, Units.tsp)),
        Units.tsp,
      );
    });

    test('metric readers get the metric ladder', () {
      expect(
        UnitConverter.displayUnitFor(
          Quantity.of(1, Units.cup),
          system: UnitSystem.metric,
        ),
        Units.millilitre,
      );
      expect(
        UnitConverter.displayUnitFor(
          Quantity.of(1500, Units.millilitre),
          system: UnitSystem.metric,
        ),
        Units.litre,
      );
    });

    test('mass follows the same walk', () {
      expect(
        UnitConverter.displayUnitFor(
          Quantity.of(50, Units.gram),
          system: UnitSystem.metric,
        ),
        Units.gram,
      );
      expect(
        UnitConverter.displayUnitFor(
          Quantity.of(2000, Units.gram),
          system: UnitSystem.metric,
        ),
        Units.kilogram,
      );
    });

    test('count units keep the word they were authored with', () {
      expect(
        UnitConverter.displayUnitFor(Quantity.of(2, Units.clove)),
        Units.clove,
      );
    });

    test('normalise moves the display unit but never the stored value', () {
      final Quantity q = Quantity.of(3, Units.tsp);
      final Quantity n = UnitConverter.normalise(q);
      expect(n.canonicalAmount, q.canonicalAmount);
      expect(n.preferredUnit, Units.tbsp);
    });
  });
}
