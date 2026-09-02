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

  group('a plural is the same word (Brendan\'s report)', () {
    // A recipe line says "apples" and the food is called "Honeycrisp Apple".
    // Matching on substrings, "honeycrisp apple" does not contain "apples",
    // so the food picker filtered out the very food the line was already
    // matched to and said "None of your foods match".
    test('a plural query finds a singular name', () {
      expect(wordCoverage('apples', 'Honeycrisp Apple'), 1.0);
      expect(wordCoverage('eggs', 'Large Egg'), 1.0);
      expect(wordCoverage('tomatoes', 'Tinned Tomato'), 1.0);
    });

    test('and a singular query still finds a plural name', () {
      expect(wordCoverage('apple', 'Honeycrisp Apples'), 1.0);
      expect(wordCoverage('berry', 'Mixed Berries'), 1.0);
    });

    test('without making unrelated words match', () {
      // Stemming that is too eager is worse than none: it would quietly
      // attach the wrong food, which is the one failure a review screen
      // cannot catch because it looks right.
      expect(wordCoverage('grass', 'Gras'), 0.0);
      expect(wordCoverage('bass', 'Bas'), 0.0);
      expect(wordCoverage('beans', 'Beef'), 0.0);
    });
  });
}
