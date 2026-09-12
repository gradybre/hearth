import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/menu_provenance.dart';

/// What a menu is worth depends on facts the menu does not carry (review N08).
void main() {
  MenuProvenance from({
    String? source,
    DateTime? documentDate,
    int itemCount = 44,
    DateTime? importedAt,
  }) => MenuProvenance(
    restaurant: 'Chopt',
    source: source,
    documentDate: documentDate,
    itemCount: itemCount,
    importedAt: importedAt ?? DateTime(2026, 9, 11),
  );

  group('how old the numbers are', () {
    test('measured from the document when there is one', () {
      // The date the restaurant stands behind. Reading an old sheet today
      // does not make it new, and this is the only field that can say so.
      final Duration age = from(documentDate: DateTime(2026, 3, 1))
          .ageAt(DateTime(2026, 9, 11));

      expect(age.inDays, greaterThan(190));
    });

    test('and from the reading when there is not', () {
      final Duration age = from(importedAt: DateTime(2026, 9, 1))
          .ageAt(DateTime(2026, 9, 11));

      expect(age.inDays, 10);
    });
  });

  group('the line under the name', () {
    test('says only what is known', () {
      // A menu with no source and no document date still has a count and a
      // date it was read, and saying those plainly beats padding with
      // "unknown".
      final String line = from().describe(DateTime(2026, 9, 11));

      expect(line, contains('44 items'));
      expect(line, contains('read 11 September'));
      expect(line.toLowerCase(), isNot(contains('unknown')));
    });

    test('and leads with the document date over the reading', () {
      final String line = from(
        source: 'chopt.com',
        documentDate: DateTime(2026, 3, 4),
      ).describe(DateTime(2026, 9, 11));

      expect(line, contains('chopt.com'));
      expect(line, contains('dated 4 March'));
      expect(
        line,
        isNot(contains('read')),
        reason: 'the date it was published is the one that matters',
      );
    });

    test('counts one item in the singular', () {
      expect(
        from(itemCount: 1).describe(DateTime(2026, 9, 11)),
        contains('1 item'),
      );
    });
  });
}
