import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/domain/units/unit_converter.dart';
import 'package:test/test.dart';

/// The words that are actually printed on packets.
///
/// A tub of protein powder is sold by the scoop and a cereal box by the bar.
/// Offering only `item` meant a serving was either labelled with a word nobody
/// uses or lost the word altogether — and with it, the serving.
void packetUnitTests() {
  group('counted units for things sold in packets', () {
    test('the words on the packet are units', () {
      for (final String id in <String>[
        'scoop',
        'bar',
        'package',
        'packet',
        'container',
        'bottle',
        'can',
        'piece',
        'patty',
        'stick',
        'square',
        'tortilla',
      ]) {
        final Unit? unit = Units.byId(id);
        expect(unit, isNotNull, reason: '$id should be a unit');
        expect(unit!.kind, UnitKind.count);
      }
    });

    test('"serving" is deliberately not one of them', () {
      // Every other word here names something you can hold. "1 serving" names
      // only itself, and the label formatter already refuses it as a phrase.
      expect(Units.byId('serving'), isNull);
    });

    test('plurals parse, because that is how a label writes them', () {
      expect(Units.parse('scoops'), Units.scoop);
      expect(Units.parse('patties'), Units.patty);
      expect(Units.parse('tubs'), Units.container);
      expect(Units.parse('pkg'), Units.package);
    });

    test('a scoop is not an item, however alike they look', () {
      // Both canonicalise to one, and that is exactly the trap: a food
      // measured in scoops must never be added to one measured in bars.
      // Conversion across count is refused, which is what keeps them apart.
      expect(Units.scoop == Units.item, isFalse);
      expect(
        UnitConverter.crossKind(
          Quantity.of(1, Units.scoop),
          UnitKind.mass,
        ).densityMissing,
        isTrue,
      );
    });
  });
}

void main() {
  packetUnitTests();
}
