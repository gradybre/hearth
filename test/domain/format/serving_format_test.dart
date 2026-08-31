import 'package:hearth/domain/format/serving_format.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

ServingOption serving({
  required String label,
  required double amount,
  Unit unit = Units.gram,
  bool isReference = false,
}) => ServingOption(
  id: 'serving-1',
  label: label,
  amount: Quantity.of(amount, unit),
  macros: const Macros(kcal: 100),
  isReference: isReference,
);

void main() {
  group("the packet's own words lead", () {
    test('a container, however the source abbreviated it', () {
      // Open Food Facts' US yogurt entries carry all three of these for what
      // is the same pot on the same shelf.
      for (final String label in <String>[
        '1 CONTAINER (150 g)',
        '1 container (150 g)',
        '1 con (150 g)',
      ]) {
        expect(
          ServingFormat.describe(serving(label: label, amount: 150)),
          '1 container',
          reason: label,
        );
      }
    });

    test('a household volume, read back as a cook would write it', () {
      expect(
        ServingFormat.describe(serving(label: '0.5 cup (89 g)', amount: 89)),
        '½ cup',
      );
    });

    test('more than one of something is pluralised', () {
      expect(
        ServingFormat.describe(serving(label: '2 pieces (40 g)', amount: 40)),
        '2 pieces',
      );
      expect(ServingFormat.packetPhrase('2 patty (110 g)'), '2 patties');
      expect(ServingFormat.packetPhrase('2 ea (30 g)'), '2 each');
    });

    test('a portion that says nothing is not a phrase', () {
      // "1 serving" is technically a portion and tells nobody anything.
      expect(ServingFormat.packetPhrase('1 serving (28 g)'), isNull);
      expect(ServingFormat.packetPhrase('about a handful'), isNull);
      expect(ServingFormat.packetPhrase(''), isNull);
    });
  });

  group('a metric figure becomes imperial', () {
    test('a weight the packet only gave in grams', () {
      // Every source reports metrically however the box is written.
      expect(
        ServingFormat.describe(serving(label: '150 g', amount: 150)),
        '5.3 oz',
      );
    });

    test('a volume the source only gave in millilitres', () {
      expect(
        ServingFormat.describe(
          serving(label: '240 ml', amount: 240, unit: Units.millilitre),
        ),
        '1 cup',
      );
    });
  });

  group('a reference is left as a reference', () {
    test('100 g is not re-expressed as a serving', () {
      // Brendan's report: every Oikos yogurt in the search list claimed
      // "3.5 oz". None of them said so — that is 100 g in ounces, which is
      // the figure nutrition is quoted against, not a pot anybody eats.
      expect(
        ServingFormat.describe(
          serving(label: '100 g', amount: 100, isReference: true),
        ),
        '100 g',
      );
    });
  });
}
