import 'package:hearth/domain/format/quantity_format.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('imperial volume reads as cooking fractions (spec §5.2)', () {
    test('whole numbers stay whole', () {
      expect(QuantityFormat.format(Quantity.of(1, Units.cup)), '1 cup');
      expect(QuantityFormat.format(Quantity.of(2, Units.cup)), '2 cups');
      expect(QuantityFormat.format(Quantity.of(3, Units.tbsp)), '3 tbsp');
    });

    test('fractions below one take the singular label', () {
      // Regression: '1/2 cups' read as broken English.
      expect(QuantityFormat.format(Quantity.of(0.5, Units.cup)), '½ cup');
      expect(QuantityFormat.format(Quantity.of(0.75, Units.cup)), '¾ cup');
      expect(QuantityFormat.format(Quantity.of(1.5, Units.cup)), '1½ cups');
      expect(QuantityFormat.format(Quantity.of(0, Units.cup)), '0 cups');
    });

    test('common fractions get glyphs', () {
      expect(QuantityFormat.format(Quantity.of(0.5, Units.cup)), '½ cup');
      expect(QuantityFormat.format(Quantity.of(0.25, Units.tsp)), '¼ tsp');
      expect(QuantityFormat.format(Quantity.of(0.75, Units.cup)), '¾ cup');
    });

    test('mixed numbers combine whole and fraction', () {
      // The spec's own example: 4 tsp normalises to 1 1/3 tbsp.
      expect(QuantityFormat.format(Quantity.of(4, Units.tsp)), '1⅓ tbsp');
      expect(QuantityFormat.format(Quantity.of(1.5, Units.cup)), '1½ cups');
    });

    test('values with no nearby fraction fall back to a short decimal', () {
      expect(QuantityFormat.format(Quantity.of(1.4, Units.tbsp)), '1.4 tbsp');
    });

    test('zero is zero', () {
      expect(QuantityFormat.format(Quantity.of(0, Units.cup)), '0 cups');
    });
  });

  group('weight reads as decimals', () {
    test('grams round to whole numbers above ten', () {
      expect(
        QuantityFormat.format(
          Quantity.of(50, Units.gram),
          system: UnitSystem.metric,
        ),
        '50 g',
      );
      expect(
        QuantityFormat.format(
          Quantity.of(124.9, Units.gram),
          system: UnitSystem.metric,
        ),
        '125 g',
      );
    });

    test('small weights keep one decimal place', () {
      expect(
        QuantityFormat.format(
          Quantity.of(2.5, Units.gram),
          system: UnitSystem.metric,
        ),
        '2.5 g',
      );
      expect(
        QuantityFormat.format(
          Quantity.of(2, Units.gram),
          system: UnitSystem.metric,
        ),
        '2 g',
      );
    });

    test('kilograms are never fractions', () {
      expect(
        QuantityFormat.format(
          Quantity.of(1.5, Units.kilogram),
          system: UnitSystem.metric,
        ),
        '1.5 kg',
      );
    });

    test('an imperial reader sees the same stored grams as ounces', () {
      // Per-user display preference (spec §4) — one stored value, two readings.
      final Quantity q = Quantity.of(50, Units.gram);
      expect(QuantityFormat.format(q), '1.8 oz');
      expect(QuantityFormat.format(q, system: UnitSystem.metric), '50 g');
    });

    test('formatIn pins the unit regardless of reader preference', () {
      // Nutrition surfaces show grams to everyone; they ask for the unit
      // explicitly rather than letting the ladder choose.
      expect(
        QuantityFormat.formatIn(Quantity.of(50, Units.gram), Units.gram),
        '50 g',
      );
    });
  });

  group('metric volume reads as decimals too', () {
    test('nobody writes one and a third millilitres', () {
      expect(
        QuantityFormat.format(
          Quantity.of(1, Units.cup),
          system: UnitSystem.metric,
        ),
        '237 ml',
      );
      expect(
        QuantityFormat.format(
          Quantity.of(1500, Units.millilitre),
          system: UnitSystem.metric,
        ),
        '1.5 L',
      );
    });
  });

  group('counts', () {
    test('keep their authored word and pluralise', () {
      expect(QuantityFormat.format(Quantity.of(2, Units.clove)), '2 cloves');
      expect(QuantityFormat.format(Quantity.of(1, Units.clove)), '1 clove');
      expect(QuantityFormat.format(Quantity.of(3, Units.slice)), '3 slices');
    });

    test('bare items show only the number', () {
      expect(QuantityFormat.format(Quantity.of(2, Units.item)), '2');
    });
  });

  group('formatAsAuthored', () {
    test('echoes the unit the value was written in', () {
      // An editor preview exists to confirm a parse. Typing "1.5 kg" and
      // being shown "3.3 lb" makes that harder, not easier.
      final Quantity q = Quantity.of(1.5, Units.kilogram);
      expect(QuantityFormat.formatAsAuthored(q), '1.5 kg');
      expect(QuantityFormat.format(q), '3.3 lb');
    });

    test('keeps imperial units as authored too', () {
      expect(
        QuantityFormat.formatAsAuthored(Quantity.of(2, Units.tbsp)),
        '2 tbsp',
      );
      expect(
        QuantityFormat.formatAsAuthored(Quantity.of(0.5, Units.cup)),
        '½ cup',
      );
    });

    test('falls back to the reader preference with no authored unit', () {
      const Quantity bare = Quantity.canonical(
        canonicalAmount: 1000,
        kind: UnitKind.mass,
      );
      expect(
        QuantityFormat.formatAsAuthored(bare, system: UnitSystem.metric),
        '1 kg',
      );
    });
  });

  test('formatting never changes the stored value', () {
    final Quantity q = Quantity.of(124.9, Units.gram);
    QuantityFormat.format(q);
    expect(q.canonicalAmount, 124.9);
  });

  group('bare counts', () {
    test('reads a half as a fraction, not a decimal', () {
      // "0.5x" is spreadsheet language; a cook reads a half.
      expect(QuantityFormat.count(0.5), '\u00bd');
      expect(QuantityFormat.count(1.5), '1\u00bd');
    });

    test('leaves whole counts whole', () {
      expect(QuantityFormat.count(6), '6');
      expect(QuantityFormat.count(2), '2');
    });
  });
}
