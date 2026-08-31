import 'package:hearth/domain/parsing/amount_parser.dart';
import 'package:test/test.dart';

void main() {
  group('the numbers people write for amounts', () {
    test('a plain whole number', () {
      expect(parseAmount('100'), 100);
    });

    test('a decimal', () {
      // Brendan's report: 1.5 tsp could not be entered at all.
      expect(parseAmount('1.5'), closeTo(1.5, 1e-12));
    });

    test('a plain fraction', () {
      // The other half of it: a measuring cup is marked ⅔, not 0.667.
      expect(parseAmount('2/3'), closeTo(2 / 3, 1e-12));
      expect(parseAmount('1/2'), closeTo(0.5, 1e-12));
    });

    test('a mixed number', () {
      expect(parseAmount('1 1/2'), closeTo(1.5, 1e-12));
      expect(parseAmount('2 1/3'), closeTo(2 + 1 / 3, 1e-12));
    });

    test('a vulgar fraction, alone and after a whole number', () {
      expect(parseAmount('½'), closeTo(0.5, 1e-12));
      expect(parseAmount('⅔'), closeTo(2 / 3, 1e-12));
      expect(parseAmount('1½'), closeTo(1.5, 1e-12));
    });

    test('surrounding whitespace is ignored', () {
      expect(parseAmount('  2/3  '), closeTo(2 / 3, 1e-12));
    });

    test('spaces around the slash are tolerated', () {
      expect(parseAmount('2 / 3'), closeTo(2 / 3, 1e-12));
    });
  });

  group('what is not a number stays not a number', () {
    test('empty and blank', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('   '), isNull);
    });

    test('a divide by zero is refused rather than made infinite', () {
      expect(parseAmount('1/0'), isNull);
      expect(parseAmount('1 1/0'), isNull);
    });

    test('words are not amounts', () {
      // A serving nobody can read back is better left empty than turned into
      // a number the user never meant.
      expect(parseAmount('a couple'), isNull);
      expect(parseAmount('2 cups'), isNull);
    });
  });

  group('the character filter behind the amount field', () {
    test('accepts everything an amount can contain', () {
      for (final String character in <String>[
        '0',
        '9',
        '.',
        '/',
        ' ',
        '½',
        '⅔',
      ]) {
        expect(
          amountCharacters.hasMatch(character),
          isTrue,
          reason: '"$character" belongs in an amount',
        );
      }
    });

    test('rejects the letters a full keyboard also offers', () {
      // The field takes the full keyboard because no numeric pad on iOS
      // carries both "." and "/", so this is what keeps it a number field.
      for (final String character in <String>['a', 'Z', '-', ',']) {
        expect(amountCharacters.hasMatch(character), isFalse);
      }
    });
  });
}
