import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'recipe_ai.dart';

/// Recipe import and generation through the `recipe-ai` Edge Function
/// (spec §5.3, §5.4).
///
/// The function holds `ANTHROPIC_API_KEY`; a key in the client is a key anyone
/// can pull out of the app bundle (CLAUDE.md §8.1). It also narrows Claude's
/// response to a small stable shape server-side, so a change there is a
/// redeploy rather than an App Store release — the same reasoning as
/// [UsdaNutritionSource].
class EdgeFunctionRecipeAi implements RecipeAiSource {
  EdgeFunctionRecipeAi(this._client);

  static const String functionName = 'recipe-ai';

  final SupabaseClient _client;

  @override
  Future<AiRecipe> extract({
    List<AiImage> images = const <AiImage>[],
    String? url,
    String? text,
    String? notes,
  }) {
    final String trimmed = (url ?? '').trim();
    final String words = (text ?? '').trim();
    if (images.isEmpty && trimmed.isEmpty && words.isEmpty) {
      throw const RecipeAiException(
        'Choose a photo, paste a link, or share the recipe text first.',
        isRetryable: false,
      );
    }

    return _invoke(<String, Object?>{
      'mode': 'extract',
      if (images.isNotEmpty)
        'images': <String>[
          for (final AiImage image in images)
            'data:${image.mediaType};base64,${base64Encode(image.bytes)}',
        ],
      if (trimmed.isNotEmpty) 'url': trimmed,
      if (words.isNotEmpty) 'text': words,
      if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
    });
  }

  @override
  Future<AiRecipe> generate({
    required List<AiTurn> turns,
    Map<String, Object?> profile = const <String, Object?>{},
    String? recipe,
  }) {
    if (turns.isEmpty) {
      throw const RecipeAiException(
        'Say what you would like first.',
        isRetryable: false,
      );
    }

    return _invoke(<String, Object?>{
      'mode': 'generate',
      'messages': <Map<String, Object?>>[
        for (final AiTurn turn in turns)
          <String, Object?>{
            'role': turn.fromUser ? 'user' : 'assistant',
            'text': turn.text,
          },
      ],
      if (profile.isNotEmpty) 'profile': profile,
      if ((recipe ?? '').trim().isNotEmpty) 'recipe': recipe!.trim(),
    });
  }

  Future<AiRecipe> _invoke(Map<String, Object?> body) async {
    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: body,
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
      throw const RecipeAiException('Could not reach the recipe reader.');
    }

    if (data is! Map) {
      throw const RecipeAiException(
        'That came back in a shape Hearth cannot read.',
      );
    }

    final Object? error = data['error'];
    if (error != null) throw RecipeAiException('$error');

    return recipeFrom(data);
  }

  /// Reads the function's response into an [AiRecipe].
  ///
  /// Public because it is the seam worth testing: the network cannot be
  /// mocked here without mocking Supabase's client whole, but the parse can be
  /// exercised directly against every shape the function might send —
  /// including the malformed ones it should never send.
  static AiRecipe recipeFrom(Map<Object?, Object?> envelope) {
    final Object? recipe = envelope['recipe'];
    if (recipe is! Map) {
      throw const RecipeAiException('No recipe could be read from that.');
    }
    return _toRecipe(recipe, envelope);
  }

  static AiUsage? _usage(Object? raw) {
    if (raw is! Map) return null;
    final double? ceiling = _number(raw['ceiling_usd']);
    if (ceiling == null) return null;
    return AiUsage(
      spentUsd: _number(raw['spent_usd']) ?? 0,
      ceilingUsd: ceiling,
      fraction: _number(raw['fraction']) ?? 0,
      warn: raw['warn'] == true,
    );
  }

  static AiRecipe _toRecipe(
    Map<Object?, Object?> recipe,
    Map<Object?, Object?> envelope,
  ) {
    final Object? sections = recipe['sections'];

    return AiRecipe(
      title: _text(recipe['title']),
      servings: _number(recipe['servings']),
      prepMinutes: _number(recipe['prep_minutes'])?.round(),
      cookMinutes: _number(recipe['cook_minutes'])?.round(),
      cuisine: _textOrNull(recipe['cuisine']),
      tags: <String>[
        if (recipe['tags'] case final List<Object?> tags)
          for (final Object? tag in tags)
            if (_text(tag).isNotEmpty) _text(tag),
      ],
      sections: <AiSection>[
        if (sections is List<Object?>)
          for (final Object? section in sections)
            if (section is Map)
              AiSection(
                name: _text(section['name']),
                ingredientsText: _text(section['ingredients_text']),
                directionsText: _text(section['directions_text']),
              ),
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
      estimates: <AiEstimate>[
        if (envelope['estimates'] case final List<Object?> estimates)
          for (final Object? item in estimates)
            if (item is Map && _text(item['ingredient']).isNotEmpty)
              AiEstimate(
                ingredient: _text(item['ingredient']),
                kcal: _number(item['kcal']) ?? 0,
                proteinG: _number(item['protein_g']) ?? 0,
                carbG: _number(item['carb_g']) ?? 0,
                fatG: _number(item['fat_g']) ?? 0,
              ),
      ],
      reply: _textOrNull(envelope['reply']),
      usage: _usage(envelope['usage']),
    );
  }

  /// Pulls the sentence out of whatever the function put in the body.
  static String? _messageFrom(Object? details) {
    if (details is Map && details['error'] != null) {
      return '${details['error']}';
    }
    if (details is String && details.trim().isNotEmpty) return details.trim();
    return null;
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static String? _textOrNull(Object? value) {
    final String text = _text(value);
    return text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => switch (value) {
    final num n when n.isFinite => n.toDouble(),
    _ => null,
  };
}
