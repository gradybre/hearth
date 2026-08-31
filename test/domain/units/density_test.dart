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

    test('a different food is not its head noun', () {
      // Brendan's report, found while chasing it: "cauliflower rice" took
      // white rice's 0.85 g/ml through a plain substring match — about five
      // times its real weight, silently, inside a macro total. A missing
      // density is flagged; a wrong one is not.
      expect(DensityTable.lookup('cauliflower rice'), isNull);
      expect(DensityTable.lookup('frozen cauliflower rice'), isNull);
      expect(DensityTable.lookup('almond flour'), isNull);
      expect(DensityTable.lookup('coconut milk'), isNull);
      expect(DensityTable.lookup('oat milk'), isNull);
    });

    test('a qualified form of a known food still resolves', () {
      // The other half of the same rule: the words in front must not stop a
      // real match, or every recipe's "finely grated parmesan" goes unknown.
      expect(DensityTable.lookup('boiling water'), 1.0);
      expect(DensityTable.lookup('finely grated parmesan'), 0.4);
      expect(DensityTable.lookup('melted unsalted butter'), 0.911);
      expect(DensityTable.lookup('sifted all-purpose flour'), 0.528);
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
