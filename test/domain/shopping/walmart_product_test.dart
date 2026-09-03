import 'package:hearth/domain/shopping/walmart_product.dart';
import 'package:test/test.dart';

/// Reading an item id out of a paste (spec §5.7).
void main() {
  group('what a person actually pastes', () {
    test('a product link from the Walmart app', () {
      expect(
        WalmartProduct.idFrom(
          'https://www.walmart.com/ip/Goldfish-Baby-Cheddar-Crackers/10450479',
        ),
        '10450479',
      );
    });

    test('the same link with the tracking junk on the end', () {
      // Share → Copy Link does not hand over a clean URL.
      expect(
        WalmartProduct.idFrom(
          'https://www.walmart.com/ip/Goldfish/10450479?athbdg=L1600&from=/search',
        ),
        '10450479',
      );
    });

    test('a bare id, once you know what they look like', () {
      expect(WalmartProduct.idFrom('10450479'), '10450479');
      expect(WalmartProduct.idFrom('  10450479  '), '10450479');
    });

    test('the slug is ignored even when it is full of numbers', () {
      // Verified against the live site: this exact URL — an apple juice slug
      // with a crackers id — serves the crackers. Only the number identifies
      // anything, so a slug's digits must never win.
      expect(
        WalmartProduct.idFrom(
          'https://www.walmart.com/ip/Great-Value-100-Apple-Juice-96-fl-oz/10450479',
        ),
        '10450479',
      );
    });

    test('a link with no id at all', () {
      expect(
        WalmartProduct.idFrom('https://www.walmart.com/search?q=ground+beef'),
        isNull,
      );
    });
  });

  group('what it refuses', () {
    test('nothing, and nonsense', () {
      // Null rather than a best guess: a wrong id fails silently, in a basket
      // somebody is standing over. The paste is the only place to say so.
      for (final String raw in <String>[
        '',
        '   ',
        'ground beef',
        'abc123def',
      ]) {
        expect(WalmartProduct.idFrom(raw), isNull, reason: raw);
      }
    });

    test('a number too short to be an id', () {
      expect(WalmartProduct.idFrom('42'), isNull);
    });

    test('and looksValid agrees with idFrom', () {
      expect(WalmartProduct.looksValid('10450479'), isTrue);
      expect(WalmartProduct.looksValid('ground beef'), isFalse);
    });
  });
}
