import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/foods/menu_import.dart';
import '../../domain/models/macros.dart';
import 'menu_reader.dart';
import 'recipe_ai.dart';

/// [MenuReader] through the `recipe-ai` Edge Function (spec §5.2, §8.1).
///
/// The same function as the label reader and for the same reasons: one key,
/// one model, one set of size caps, and a change to what the model is asked
/// for is a redeploy rather than an App Store release. The key stays
/// server-side (§8.1); nothing here has it.
class EdgeFunctionMenuReader implements MenuReader {
  EdgeFunctionMenuReader(this._client);

  static const String functionName = 'recipe-ai';

  final SupabaseClient _client;

  @override
  Future<MenuReading> read(List<AiImage> images) async {
    if (images.isEmpty) {
      throw const RecipeAiException(
        'Add a picture of the menu first.',
        isRetryable: false,
      );
    }

    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: <String, Object?>{
          'mode': 'menu',
          'images': <String>[
            for (final AiImage image in images)
              'data:${image.mediaType};base64,${base64Encode(image.bytes)}',
          ],
        },
      );
      data = response.data;
    } on FunctionException catch (error) {
      throw RecipeAiException(
        _messageFrom(error.details) ?? 'That did not go through.',
        isRetryable: error.status >= 500,
      );
    } on Object {
      throw const RecipeAiException('Could not reach the menu reader.');
    }

    if (data is! Map) {
      throw const RecipeAiException(
        'That came back in a shape Hearth cannot read.',
      );
    }

    final Object? error = data['error'];
    if (error != null) throw RecipeAiException('$error');

    return readingFrom(data);
  }

  /// Reads the function's response into a [MenuReading].
  ///
  /// Public because it is the seam worth testing: the parse can be exercised
  /// against every shape the function might send, including the malformed ones
  /// it should never send.
  static MenuReading readingFrom(Map<Object?, Object?> envelope) {
    final Object? rows = envelope['rows'];
    if (rows is! List) {
      throw const RecipeAiException('No menu could be read from that.');
    }

    final List<MenuRow> read = <MenuRow>[
      for (final Object? row in rows)
        if (row is Map<Object?, Object?>)
          if (_row(row) case final MenuRow item) item,
    ];

    if (read.isEmpty) {
      throw const RecipeAiException(
        'Nothing on that page looked like a nutrition table.',
        isRetryable: false,
      );
    }

    return MenuReading(
      rows: read,
      restaurant: _text(envelope['restaurant']),
      uncertain: <AiUncertainty>[
        // A pattern rather than a cast: a response whose `uncertain` came
        // back as a string would otherwise throw a TypeError, which is not
        // the exception the screen knows how to show.
        if (envelope['uncertain'] case final List<Object?> notes)
          for (final Object? note in notes)
            if (note is Map<Object?, Object?>)
              AiUncertainty(
                field: '${note['field'] ?? ''}',
                note: '${note['note'] ?? ''}',
              ),
      ],
    );
  }

  /// One row, or null for one that cannot be used.
  ///
  /// A row with no name or no calories is dropped rather than carried: the
  /// function already filters these, so anything arriving here is a shape it
  /// promised not to send, and a nameless row would land in the review as a
  /// line nobody could act on.
  static MenuRow? _row(Map<Object?, Object?> row) {
    final String? name = _text(row['name']);
    final double? kcal = _number(row['kcal']);
    if (name == null || kcal == null) return null;

    return MenuRow(
      name: name,
      // The function defaults this, but a response that skipped it would
      // otherwise produce a row with no portion at all — which the parser
      // would then refuse, blaming the user's picture for a gap upstream.
      portion: _text(row['portion']) ?? '1 serving',
      section: _text(row['section']),
      macros: Macros(
        kcal: kcal,
        proteinG: _number(row['protein_g']) ?? 0,
        carbG: _number(row['carb_g']) ?? 0,
        fatG: _number(row['fat_g']) ?? 0,
        // No fallback. A column the sheet never printed is unknown, and the
        // whole of §5.6 rests on that not becoming a zero.
        fiberG: _number(row['fiber_g']),
        sodiumMg: _number(row['sodium_mg']),
        cholesterolMg: _number(row['cholesterol_mg']),
      ),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s.trim()),
    _ => null,
  };

  /// The sentence the function put in its error body, when it sent one.
  static String? _messageFrom(Object? details) {
    if (details is Map && details['error'] != null) {
      return '${details['error']}';
    }
    if (details is String && details.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(details);
        if (decoded is Map && decoded['error'] != null) {
          return '${decoded['error']}';
        }
      } on FormatException {
        return details.trim();
      }
      // Decoded, but with no sentence in it: showing the raw JSON would put a
      // gateway's internals in front of the user.
      return null;
    }
    return null;
  }
}
