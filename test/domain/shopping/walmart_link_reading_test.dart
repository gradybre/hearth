import 'package:test/test.dart';

import 'package:hearth/domain/shopping/walmart_link_reading.dart';

// Regression tests for D-WALMART-001 (plan P-HEARTH-WALMART-001).
// Includes two Astra findings that the current canonicalUrl implementation
// is expected to fail until repaired:
//  1. Non-default scheme/port pairs (https on :80, http on :443, and an
//     omitted (https-default) scheme paired with :80) must be rejected.
//  2. Percent-escapes, ellipsis, and whitespace-lookalikes appearing only
//     after the query delimiter must NOT cause rejection, since only the
//     pre-query authority/path is validated.

void main() {
  group('WalmartLinkReading.canonicalUrl - corpus accept (D-WALMART-001)', () {
    final Map<String, String> accepted = <String, String>{
      'https://www.walmart.com/ip/10450479':
          'https://www.walmart.com/ip/10450479',
      'walmart.com/ip/Goldfish-30/10450479':
          'https://www.walmart.com/ip/10450479',
      'http://m.walmart.com:80/ip/123/': 'https://www.walmart.com/ip/123',
      'HTTPS://WWW.WALMART.COM:443/ip/000123?tracking=anything#x':
          'https://www.walmart.com/ip/000123',
      ' www.walmart.com/ip/12345678901234567890 ':
          'https://www.walmart.com/ip/12345678901234567890',
    };

    accepted.forEach((String input, String expected) {
      test('accepts "$input"', () {
        expect(WalmartLinkReading.canonicalUrl(input), expected);
      });
    });
  });

  group('WalmartLinkReading.canonicalUrl - corpus reject (D-WALMART-001)', () {
    final List<String> rejected = <String>[
      '10450479',
      'https://evil.com/ip/10450479',
      'https://walmart.com.evil.com/ip/123',
      'https://user@walmart.com/ip/123',
      'https://walmart.com:444/ip/123',
      '//walmart.com/ip/123',
      'https://walmart.com/search/123',
      'https://walmart.com/ip/12',
      'https://walmart.com/ip/123456789012345678901',
      'https://walmart.com/ip/a/b/123',
      'https://walmart.com/ip/Slug\u2026/123',
      'https://walmart.com/ip/%31%32%33',
      'https://walmart.com/ip/abc/../123',
      'https://walmart.com/ip/123/more',
      'https://walmart.com/ip/12 3',
      'https://w\u0430lmart.com/ip/123',
      'https://walmrt.us/abc',
      'https://walmart.com/ip/\uff11\uff12\uff13',
    ];

    for (final String input in rejected) {
      test('rejects "$input"', () {
        expect(WalmartLinkReading.canonicalUrl(input), isNull);
      });
    }
  });

  group('WalmartLinkReading.canonicalUrl - non-default scheme/port must reject (Astra finding)', () {
    test('rejects https scheme with explicit port 80 (http default port)', () {
      expect(
        WalmartLinkReading.canonicalUrl('https://walmart.com:80/ip/123'),
        isNull,
        reason: 'Port 80 is only valid for http, not https; must not silently accept.',
      );
    });

    test('rejects http scheme with explicit port 443 (https default port)', () {
      expect(
        WalmartLinkReading.canonicalUrl('http://walmart.com:443/ip/123'),
        isNull,
        reason: 'Port 443 is only valid for https, not http; must not silently accept.',
      );
    });

    test(
      'rejects omitted-scheme (implicit https) URL with explicit port 80',
      () {
        expect(
          WalmartLinkReading.canonicalUrl('walmart.com:80/ip/123'),
          isNull,
          reason: 'Omitted scheme defaults to https; port 80 does not match the default scheme.',
        );
      },
    );

    test('still accepts https with explicit correct port 443', () {
      expect(
        WalmartLinkReading.canonicalUrl('https://walmart.com:443/ip/123'),
        'https://www.walmart.com/ip/123',
      );
    });

    test('still accepts http with explicit correct port 80', () {
      expect(
        WalmartLinkReading.canonicalUrl('http://walmart.com:80/ip/123'),
        'https://www.walmart.com/ip/123',
      );
    });
  });

  group('WalmartLinkReading.canonicalUrl - query/fragment must not be validated (Astra finding)', () {
    test('accepts percent-escapes and ellipsis appearing only after the query delimiter', () {
      expect(
        WalmartLinkReading.canonicalUrl(
          'walmart.com/ip/123?x=%2F...#encoded%20',
        ),
        'https://www.walmart.com/ip/123',
        reason: 'Only the pre-query authority/path is validated; query and fragment are ignored verbatim.',
      );
    });

    test('accepts control-like percent escapes and unicode ellipsis in query with a clean path', () {
      expect(
        WalmartLinkReading.canonicalUrl(
          'https://www.walmart.com/ip/999?a=%00...\u2026#frag',
        ),
        'https://www.walmart.com/ip/999',
      );
    });

    test('still rejects percent sign appearing in the pre-query path', () {
      expect(
        WalmartLinkReading.canonicalUrl('walmart.com/ip/1%202?tracking=abc'),
        isNull,
      );
    });

    test(
      'still rejects interior whitespace appearing in the pre-query authority',
      () {
        expect(
          WalmartLinkReading.canonicalUrl('walmart .com/ip/123?tracking=abc'),
          isNull,
        );
      },
    );

    test('still rejects backslash appearing in the pre-query path even with a clean query', () {
      expect(
        WalmartLinkReading.canonicalUrl('walmart.com/ip\\/123?tracking=abc'),
        isNull,
      );
    });
  });

  group('WalmartLinkReading.canonicalUrl - misc type/length guards', () {
    test('rejects non-string input', () {
      expect(WalmartLinkReading.canonicalUrl(12345), isNull);
      expect(WalmartLinkReading.canonicalUrl(null), isNull);
    });

    test('rejects overlong input beyond 2048 characters', () {
      final String longInput = 'https://walmart.com/ip/${'1' * 3000}';
      expect(WalmartLinkReading.canonicalUrl(longInput), isNull);
    });
  });

  group('WalmartLinkReading.fromJson - envelope shaping', () {
    test('null envelope is notFound', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(null);
      expect(reading.status, WalmartLinkStatus.notFound);
      expect(reading.hasLink, isFalse);
      expect(reading.url, isNull);
      expect(reading.source, isNull);
    });

    test('const notFound() constructor matches fromJson(null)', () {
      const WalmartLinkReading reading = WalmartLinkReading.notFound();
      expect(reading.status, WalmartLinkStatus.notFound);
      expect(reading.hasLink, isFalse);
    });

    test('non-map envelope is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        'not a map',
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status not_found with no url/source is notFound', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'not_found'},
      );
      expect(reading.status, WalmartLinkStatus.notFound);
    });

    test('status not_found with an unexpected url is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{
          'status': 'not_found',
          'url': 'https://www.walmart.com/ip/123',
        },
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status ambiguous with no url/source is ambiguous', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'ambiguous'},
      );
      expect(reading.status, WalmartLinkStatus.ambiguous);
      expect(reading.url, isNull);
      expect(reading.source, isNull);
    });

    test('status ambiguous with an unexpected source is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'ambiguous', 'source': 'nutrition'},
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status unreadable maps straight through', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'unreadable'},
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('unrecognized status string is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'weird'},
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status found with a non-string url is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{'status': 'found', 'url': 12345, 'source': 'package'},
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status found with a non-canonical url (e.g. carrying a query string) is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/123?tracking=x',
          'source': 'package',
        },
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('status found with an invalid source is unreadable', () {
      final WalmartLinkReading reading = WalmartLinkReading.fromJson(
        <String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/123',
          'source': 'unknown',
        },
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    for (final String source in <String>[
      'nutrition',
      'package',
      'both',
      'screenshot',
    ]) {
      test(
        'status found with source "$source" and an exactly canonical url is trusted',
        () {
          final WalmartLinkReading reading = WalmartLinkReading.fromJson(
            <String, Object?>{
              'status': 'found',
              'url': 'https://www.walmart.com/ip/123',
              'source': source,
            },
          );
          expect(reading.status, WalmartLinkStatus.found);
          expect(reading.hasLink, isTrue);
          expect(reading.url, 'https://www.walmart.com/ip/123');
          expect(reading.source, source);
        },
      );
    }
  });
}
