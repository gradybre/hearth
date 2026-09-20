import 'dart:typed_data';

import 'package:hearth/data/adapters/edge_function_label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The function's response, read into a [WalmartLinkReading].
///
/// The companion request test exercises the HTTP boundary with a fake client.
/// Here the parser is checked against every shape
/// the function might send, including the malformed and non-Walmart ones it
/// should never send. The client re-validates even a shaped server envelope
/// rather than trusting it outright.
Map<Object?, Object?> envelopeWith(Object? walmartLink) => <Object?, Object?>{
  'walmart_link': walmartLink,
};

void main() {
  group('WalmartLinkReading parsed off the function envelope', () {
    test('an old response with no walmart_link key at all is not found', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        <Object?, Object?>{},
      );
      expect(reading.status, WalmartLinkStatus.notFound);
      expect(reading.hasLink, isFalse);
    });

    test('a clean found link is trusted', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/123456',
          'source': 'nutrition',
        }),
      );
      expect(reading.hasLink, isTrue);
      expect(reading.url, 'https://www.walmart.com/ip/123456');
      expect(reading.source, 'nutrition');
    });

    test('ambiguous and not_found statuses carry no link', () {
      expect(
        EdgeFunctionLabelReader.walmartLinkFrom(
          envelopeWith(<String, Object?>{'status': 'ambiguous'}),
        ).status,
        WalmartLinkStatus.ambiguous,
      );
      expect(
        EdgeFunctionLabelReader.walmartLinkFrom(
          envelopeWith(<String, Object?>{'status': 'not_found'}),
        ).status,
        WalmartLinkStatus.notFound,
      );
    });

    test('a non-Walmart URL is unreadable, not trusted', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{
          'status': 'found',
          'url': 'https://www.target.com/p/123456',
          'source': 'nutrition',
        }),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
      expect(reading.hasLink, isFalse);
    });

    test('a found status whose URL is not already exactly canonical is '
        'unreadable', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/123456/',
          'source': 'nutrition',
        }),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('a found status missing its source is unreadable', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/123456',
        }),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('a malformed envelope shape is unreadable rather than thrown', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith('not a map'),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('an unrecognised status string is unreadable', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{'status': 'sort_of'}),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });

    test('a not_found status carrying a stray url is unreadable', () {
      final reading = EdgeFunctionLabelReader.walmartLinkFrom(
        envelopeWith(<String, Object?>{
          'status': 'not_found',
          'url': 'https://www.walmart.com/ip/123456',
        }),
      );
      expect(reading.status, WalmartLinkStatus.unreadable);
    });
  });

  group('readWalmartLink input validation, before any request is sent', () {
    late SupabaseClient client;
    late EdgeFunctionLabelReader reader;
    setUp(() {
      client = SupabaseClient(
        'https://example.supabase.co',
        'EXAMPLE_PUBLIC_KEY',
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected request'),
        ),
      );
      reader = EdgeFunctionLabelReader(client);
    });
    tearDown(() => client.dispose());

    AiImage imageOf(int bytes, {String mediaType = 'image/jpeg'}) =>
        AiImage(bytes: Uint8List(bytes), mediaType: mediaType);

    test('no images is rejected without a request', () {
      expect(
        () => reader.readWalmartLink(const <AiImage>[]),
        throwsA(
          isA<RecipeAiException>().having(
            (RecipeAiException e) => e.isRetryable,
            'isRetryable',
            isFalse,
          ),
        ),
      );
    });

    test('more than one image is rejected without a request', () {
      expect(
        () => reader.readWalmartLink(<AiImage>[imageOf(10), imageOf(10)]),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('an empty image is rejected without a request', () {
      expect(
        () => reader.readWalmartLink(<AiImage>[imageOf(0)]),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('an oversize image is rejected without a request', () {
      expect(
        () => reader.readWalmartLink(<AiImage>[imageOf(6 * 1024 * 1024)]),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('an unsupported media type is rejected without a request', () {
      expect(
        () => reader.readWalmartLink(<AiImage>[
          imageOf(10, mediaType: 'image/heic'),
        ]),
        throwsA(isA<RecipeAiException>()),
      );
    });
  });
}
