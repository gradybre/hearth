import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'label_reader.dart';
import 'recipe_ai.dart';

/// Reading a nutrition label through the `recipe-ai` Edge Function
/// (spec §5.5).
///
/// The same function as recipe import, and for the plainest of reasons: same
/// key, same model, same image plumbing, same size caps. Splitting it would
/// mean maintaining two of each so that a name could stay accurate.
///
/// The key is why any of this is server-side. `ANTHROPIC_API_KEY` in the
/// client is a key anyone can pull out of the app bundle and spend
/// (CLAUDE.md §8.1). The response is narrowed to a small stable shape there
/// too, so a change in what the model returns is a redeploy rather than an App
/// Store release — the same reasoning as [EdgeFunctionRecipeAi].
class EdgeFunctionLabelReader implements LabelReader {
  EdgeFunctionLabelReader(this._client);

  static const String functionName = 'recipe-ai';

  final SupabaseClient _client;

  @override
  Future<LabelReading> read(List<AiImage> images) async {
    if (images.isEmpty) {
      throw const RecipeAiException(
        'Take a photo of the label first.',
        isRetryable: false,
      );
    }

    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: <String, Object?>{
          'mode': 'label',
          'images': <String>[
            for (final AiImage image in images)
              'data:${image.mediaType};base64,${base64Encode(image.bytes)}',
          ],
        },
      );
      data = response.data;
    } on FunctionException catch (error) {
      // The function says what went wrong and whether asking again could
      // help; both are worth more to the user than a status code.
      throw RecipeAiException(
        _messageFrom(error.details) ?? 'That did not go through.',
        isRetryable: error.status >= 500,
      );
    } on Object {
      throw const RecipeAiException('Could not reach the label reader.');
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

  /// Reads the function's response into a [LabelReading].
  ///
  /// Public because it is the seam worth testing: the parse can be exercised
  /// against every shape the function might send, including the malformed ones
  /// it should never send.
  static LabelReading readingFrom(Map<Object?, Object?> envelope) {
    final Object? servings = envelope['servings'];
    if (servings is! List) {
      throw const RecipeAiException('No label could be read from that.');
    }

    final LabelReading reading = LabelReading(
      name: _textOrNull(envelope['name']),
      brand: _textOrNull(envelope['brand']),
      servings: <LabelServing>[
        for (final Object? item in servings)
          if (item is Map)
            if (_serving(item) case final LabelServing serving) serving,
      ],
      uncertain: <AiUncertainty>[
        if (envelope['uncertain'] case final List<Object?> flagged)
          for (final Object? item in flagged)
            if (item is Map)
              AiUncertainty(
                field: _text(item['field']),
                note: _text(item['note']),
              ),
      ],
    );

    if (reading.isEmpty) {
      // A photo of a hand, or a panel too dark to read. Saying so beats
      // opening an editor full of blanks and letting the user work out why.
      throw const RecipeAiException(
        'No serving sizes could be read off that. Try again with the '
        'Nutrition Facts panel filling the frame.',
      );
    }
    return reading;
  }

  /// One serving row, or null when it is not one.
  ///
  /// A row with no positive amount, or a unit this app has no conversion for,
  /// is dropped rather than defaulted. A portion silently reinterpreted as a
  /// weight it is not would put a wrong number into a day, and that is the one
  /// failure a review screen cannot catch, because it looks correct.
  static LabelServing? _serving(Map<Object?, Object?> json) {
    final double? amount = _number(json['amount']);
    final String unitId = _text(json['unit']);
    if (amount == null || amount <= 0 || unitId.isEmpty) return null;

    return LabelServing(
      amount: amount,
      unitId: unitId,
      kcal: _number(json['kcal']) ?? 0,
      proteinG: _number(json['protein_g']) ?? 0,
      carbG: _number(json['carb_g']) ?? 0,
      fatG: _number(json['fat_g']) ?? 0,
      fiberG: _number(json['fiber_g']),
      sodiumMg: _number(json['sodium_mg']),
      cholesterolMg: _number(json['cholesterol_mg']),
    );
  }

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
    }
    return null;
  }

  static String _text(Object? value) => '${value ?? ''}'.trim();

  static String? _textOrNull(Object? value) {
    final String text = _text(value);
    return text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => switch (value) {
    final num n when n.isFinite => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}
