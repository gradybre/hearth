// Tests for the imperial mass display policy (D1 core): MassDisplayMode's
// three states, the automatic precedence between pack size, package unit,
// and an authored ounce reading, metric always overriding back to its own
// ladder, and the order-independent mass-hint priority used when shopping
// list lines get combined.
import 'package:hearth/domain/format/quantity_format.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'mass display preserves hundredths below ten and tiny nonzero values',
    () {
      expect(QuantityFormat.format(Quantity.of(1.75, Units.pound)), '1.75 lb');
      expect(
        QuantityFormat.format(Quantity.of(0.00001, Units.ounce)),
        '0.00001 oz',
      );
      expect(
        QuantityFormat.formatAsAuthored(Quantity.of(3.125, Units.ounce)),
        '3.125 oz',
      );
    },
  );

  group('MassDisplayMode.automatic (the default)', () {
    test('preserves an authored ounce reading without promoting to pounds', () {
      expect(QuantityFormat.format(Quantity.of(28, Units.ounce)), '28 oz');
    });

    test('a compatible mass pack size overrides an authored ounce reading', () {
      final Quantity q = Quantity.of(24, Units.ounce);
      expect(
        QuantityFormat.format(q, packSize: Quantity.of(5, Units.pound)),
        '1.5 lb',
      );
    });

    test('a pack size in ounces overrides a pound-authored hint', () {
      final Quantity q = Quantity.of(1.5, Units.pound);
      expect(
        QuantityFormat.format(q, packSize: Quantity.of(28, Units.ounce)),
        '24 oz',
      );
    });

    test('an explicit packageUnit is used when no packSize is given', () {
      final Quantity q = Quantity.of(1.5, Units.pound);
      expect(QuantityFormat.format(q, packageUnit: Units.ounce), '24 oz');
    });

    test(
      'with no hints at all, the ordinary promote/demote ladder decides',
      () {
        // 1.5 lb worth of grams, authored in neither oz nor lb.
        final Quantity q = const Quantity.canonical(
          canonicalAmount: 680.388555,
          kind: UnitKind.mass,
        );
        expect(QuantityFormat.format(q), '1.5 lb');
      },
    );
  });

  group('MassDisplayMode.weight ignores authored-ounce preservation', () {
    test('24 oz becomes 1.5 lb', () {
      expect(
        QuantityFormat.format(
          Quantity.of(24, Units.ounce),
          massDisplayMode: MassDisplayMode.weight,
        ),
        '1.5 lb',
      );
    });
  });

  group('MassDisplayMode.ounces pins ounces regardless of magnitude', () {
    test('2 lb becomes 32 oz', () {
      expect(
        QuantityFormat.format(
          Quantity.of(2, Units.pound),
          massDisplayMode: MassDisplayMode.ounces,
        ),
        '32 oz',
      );
    });
  });

  group('a metric system always overrides the imperial policy', () {
    test('an ounces override is ignored under the metric ladder', () {
      expect(
        QuantityFormat.format(
          Quantity.of(2, Units.pound),
          massDisplayMode: MassDisplayMode.ounces,
          system: UnitSystem.metric,
        ),
        '907 g',
      );
    });
  });

  group(
    'IngredientConsolidator.combine mass-hint priority is order-independent',
    () {
      test('a pound source wins over a gram source, either way round', () {
        final List<Quantity> forward = IngredientConsolidator.combine(
          <Quantity>[Quantity.of(500, Units.gram), Quantity.of(1, Units.pound)],
        );
        final List<Quantity> reversed = IngredientConsolidator.combine(
          <Quantity>[Quantity.of(1, Units.pound), Quantity.of(500, Units.gram)],
        );

        expect(forward, hasLength(1));
        expect(reversed, hasLength(1));
        expect(forward.single.preferredUnit, Units.pound);
        expect(reversed.single.preferredUnit, Units.pound);
        expect(forward.single.canonicalAmount, reversed.single.canonicalAmount);
      });
    },
  );

  group('small signed imperial mass amounts never round away to nothing', () {
    test('a tiny negative ounce amount keeps a visible magnitude', () {
      expect(
        QuantityFormat.formatIn(Quantity.of(-0.03, Units.ounce), Units.ounce),
        '−0.03 oz',
      );
    });
  });

  group(
    'authorship survives scaling; the ladder still applies at display time',
    () {
      test('a pound quantity scaled down demotes to ounces on screen', () {
        final Quantity authored = Quantity.of(2, Units.pound);
        final Quantity scaled = authored.scaledBy(0.1); // 0.2 lb
        // Scaling never overwrites the authored hint.
        expect(scaled.preferredUnit, Units.pound);
        // But the display ladder still demotes it below a quarter-pound.
        expect(QuantityFormat.format(scaled), '3.2 oz');
      });
    },
  );

  group(
    'fractional package amounts print exactly, never rounded to a whole',
    () {
      test('14.5 oz', () {
        expect(
          QuantityFormat.format(Quantity.of(14.5, Units.ounce)),
          '14.5 oz',
        );
      });

      test('15.25 oz', () {
        expect(
          QuantityFormat.format(Quantity.of(15.25, Units.ounce)),
          '15.25 oz',
        );
      });
    },
  );
}
