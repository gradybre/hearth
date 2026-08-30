import 'package:hearth/domain/text/text_normaliser.dart';
import 'package:test/test.dart';

void main() {
  group('normaliseKey', () {
    test('lowercases, strips punctuation, and collapses whitespace', () {
      expect(normaliseKey('  EVOO.  '), 'evoo');
      expect(normaliseKey('96/4 Ground Beef'), '964 ground beef');
    });
  });

  group('wordCoverage', () {
    test('every word present scores 1', () {
      expect(
        wordCoverage('96/4 Ground Beef', '96/4 Ground Beef Maverick Ranch'),
        1,
      );
    });

    test('word order does not matter', () {
      // The bug this exists to fix: neither string contains the other, but
      // every meaningful word is shared.
      expect(
        wordCoverage('lean ground beef', '96/4 Ground Beef'),
        closeTo(2 / 3, 1e-12),
      );
    });

    test('no shared words scores 0', () {
      expect(wordCoverage('chicken breast', 'Olive oil'), 0);
    });

    test('short words are not required to appear', () {
      // "of" and "la" carry no meaning a food name is obliged to repeat.
      expect(wordCoverage('leg of lamb', 'Lamb leg'), 1);
    });

    test('a query with only short words has nothing to require', () {
      expect(wordCoverage('of la', 'anything at all'), 0);
    });

    test('an empty haystack scores 0 when the query has real words', () {
      expect(wordCoverage('ground beef', ''), 0);
    });
  });
}
