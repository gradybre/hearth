import 'package:hearth/domain/units/density.dart';
import 'package:test/test.dart';

void main() {
  group('normalise', () {
    test('lowercases, strips punctuation, collapses whitespace', () {
      expect(DensityTable.normalise('  Olive   Oil, '), 'olive oil');
      expect(DensityTable.normalise('All-Purpose Flour'), 'all-purpose flour');
    });
  });

  group('lookup', () {
    test('finds exact table entries', () {
      expect(DensityTable.lookup('all-purpose flour'), 0.528);
      expect(DensityTable.lookup('honey'), 1.42);
    });

    test('resolves aliases', () {
      expect(DensityTable.lookup('flour'), 0.528);
      expect(DensityTable.lookup('evoo'), 0.918);
      expect(DensityTable.lookup('sugar'), 0.845);
      expect(DensityTable.lookup('icing sugar'), 0.53);
    });

    test('matches the longest key inside a descriptive name', () {
      expect(DensityTable.lookup('extra virgin olive oil, divided'), 0.918);
      expect(DensityTable.lookup('freshly grated parmesan'), 0.4);
      expect(DensityTable.lookup('2 cups warm water'), 1.0);
    });

    test('returns null rather than guessing an unknown ingredient', () {
      expect(DensityTable.lookup('chopped fennel fronds'), isNull);
      expect(DensityTable.lookup(''), isNull);
      expect(DensityTable.knows('chicken thighs'), isFalse);
      expect(DensityTable.knows('butter'), isTrue);
    });
  });

  test('every alias points at a real table entry', () {
    // Guards against a typo silently disabling an alias.
    for (final String alias in <String>[
      'flour',
      'sugar',
      'evoo',
      'salt',
      'oats',
      'rice',
      'cocoa',
      'parmesan',
    ]) {
      expect(DensityTable.lookup(alias), isNotNull, reason: 'alias "$alias"');
    }
  });
}
