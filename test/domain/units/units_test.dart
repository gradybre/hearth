import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('Units.parse', () {
    test('resolves ids, labels, and aliases case-insensitively', () {
      expect(Units.parse('tbsp'), Units.tbsp);
      expect(Units.parse('Tablespoons'), Units.tbsp);
      expect(Units.parse('  TBS '), Units.tbsp);
      expect(Units.parse('grams'), Units.gram);
      expect(Units.parse('KG'), Units.kilogram);
      expect(Units.parse('cups'), Units.cup);
    });

    test('honours the t / T recipe convention', () {
      expect(Units.parse('t'), Units.tsp);
      expect(Units.parse('T'), Units.tbsp);
      expect(Units.parse('t.'), Units.tsp);
    });

    test('returns null for unknown or empty tokens', () {
      expect(Units.parse(''), isNull);
      expect(Units.parse('   '), isNull);
      expect(Units.parse('handful'), isNull);
    });
  });

  test('every unit id is unique and resolvable', () {
    final Set<String> ids = Units.all.map((Unit u) => u.id).toSet();
    expect(ids.length, Units.all.length);
    for (final Unit u in Units.all) {
      expect(Units.byId(u.id), u);
    }
  });

  test('canonical units are the identity of their kind', () {
    for (final UnitKind kind in UnitKind.values) {
      expect(Units.canonicalFor(kind).toCanonical, 1.0);
      expect(Units.canonicalFor(kind).kind, kind);
    }
  });

  test('imperial volume factors chain exactly', () {
    expect(Units.tbsp.toCanonical, 3 * Units.tsp.toCanonical);
    expect(Units.cup.toCanonical, 16 * Units.tbsp.toCanonical);
    expect(Units.flOz.toCanonical, 2 * Units.tbsp.toCanonical);
  });
}
