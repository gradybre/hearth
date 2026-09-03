import 'package:hearth/domain/text/text_normaliser.dart';
import 'package:test/test.dart';

void main() {
  group('normaliseKey', () {
    test('lowercases, strips punctuation, and collapses whitespace', () {
      expect(normaliseKey('  EVOO.  '), 'evoo');
      // This used to assert '964 ground beef', which pinned a bug rather than
      // a behaviour: the slash was being deleted, fusing two numbers into one
      // that means nothing. It is a separator now — see the group below.
      expect(normaliseKey('96/4 Ground Beef'), '96 4 ground beef');
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

  group('a hyphen is a separator, not a character', () {
    // Hyphenated ingredients are ordinary — sun-dried, extra-virgin, low-fat,
    // all-purpose, bone-in — and recipes spell them both ways. Keeping the
    // hyphen made the two spellings different keys, which split a shopping
    // line in two, hid a duplicate food, and forgot a remembered match.
    test('the two spellings of the same thing agree', () {
      for (final (String, String) pair in <(String, String)>[
        ('Sun-dried tomatoes', 'sun dried tomatoes'),
        ('Extra-virgin olive oil', 'extra virgin olive oil'),
        ('Low-fat Greek yoghurt', 'low fat greek yoghurt'),
        ('All-purpose flour', 'all purpose flour'),
        ('Half-and-half', 'half and half'),
      ]) {
        expect(
          normaliseKey(pair.$1),
          normaliseKey(pair.$2),
          reason: '${pair.$1} vs ${pair.$2}',
        );
      }
    });

    test('and a slash is too', () {
      // "96/4 Ground Beef" is this file's own worked example, and it used to
      // normalise to "964 ground beef" — the digits fused.
      expect(normaliseKey('96/4 Ground Beef'), '96 4 ground beef');
      expect(
        normaliseKey('96/4 Ground Beef'),
        normaliseKey('96 4 ground beef'),
      );
    });

    test('a run of separators still collapses to one space', () {
      expect(normaliseKey('beef  --  ground'), 'beef ground');
      expect(normaliseKey('half - and - half'), 'half and half');
    });

    test('and one at either end leaves no stray space', () {
      expect(normaliseKey('-beef-'), 'beef');
      expect(normaliseKey('/beef/'), 'beef');
    });
  });

  group('matching stops depending on which side has the hyphen', () {
    test('coverage is the same in both directions', () {
      // It used to be 0.5 one way and 1.0 the other, because _sameWord asks
      // whether the found word *contains* the wanted one — so "sun-dried"
      // swallowed "sun" and "dried", while "sun-dried" matched neither.
      expect(
        wordCoverage('sun-dried tomatoes', 'Sun Dried Tomatoes'),
        wordCoverage('sun dried tomatoes', 'Sun-Dried Tomatoes'),
      );
      expect(wordCoverage('sun-dried tomatoes', 'Sun Dried Tomatoes'), 1.0);
    });
  });
}
