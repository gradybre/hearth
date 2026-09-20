import 'dart:convert';
import 'dart:typed_data';

import 'package:hearth/data/adapters/edge_function_label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

const link = {
  'status': 'found',
  'url': 'https://www.walmart.com/ip/10450479',
  'source': 'screenshot',
};
void main() {
  test(
    'standalone read sends exactly one screenshot with dedicated mode',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'EXAMPLE_PUBLIC_KEY',
        httpClient: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'walmart_link': link}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await EdgeFunctionLabelReader(client).readWalmartLink([
        AiImage(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/png'),
      ]);
      expect(result.url, link['url']);
      expect(requests, [
        {
          'mode': 'walmart',
          'images': ['data:image/png;base64,AQID'],
        },
      ]);
    },
  );
  test(
    'link-only response needs no nutrition and old responses still parse',
    () {
      final reader = EdgeFunctionLabelReader.readingFrom({
        'walmart_link': link,
      });
      expect(reader.isEmpty, isFalse);
      expect(reader.servings, isEmpty);
      expect(reader.walmartLink.url, link['url']);
      final old = EdgeFunctionLabelReader.readingFrom({
        'servings': [
          {'amount': 30, 'unit': 'g', 'kcal': 90},
        ],
      });
      expect(old.walmartLink.status, WalmartLinkStatus.notFound);
      expect(old.servings.single.kcal, 90);
      expect(
        () => EdgeFunctionLabelReader.readingFrom({'servings': []}),
        throwsA(isA<RecipeAiException>()),
      );
    },
  );
}
