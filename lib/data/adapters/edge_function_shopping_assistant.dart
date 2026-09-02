import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/shopping/shopping_edit.dart';
import '../../domain/shopping/shopping_line.dart';
import 'recipe_ai.dart';
import 'shopping_assistant.dart';

/// Editing the shopping list through the same Edge Function everything else
/// AI-shaped goes through (spec §5.7, §8.1).
///
/// The same function and the same key, so the monthly ceiling counts this too
/// — which matters more here than anywhere else, because a chat is the one
/// surface somebody can sit and hammer.
class EdgeFunctionShoppingAssistant implements ShoppingAssistant {
  EdgeFunctionShoppingAssistant(this._client);

  static const String functionName = 'recipe-ai';

  final SupabaseClient _client;

  @override
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  }) async {
    if (turns.isEmpty) {
      throw const RecipeAiException(
        'Say what you would like changed first.',
        isRetryable: false,
      );
    }

    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: <String, Object?>{
          'mode': 'shopping',
          'messages': <Map<String, Object?>>[
            for (final ShoppingTurn turn in turns)
              <String, Object?>{
                'role': turn.fromUser ? 'user' : 'assistant',
                'text': turn.text,
              },
          ],
          'list': shoppingListAsText(lines),
        },
      );
      data = response.data;
    } on FunctionException catch (error) {
      throw RecipeAiException(
        _messageFrom(error.details) ?? 'That did not go through.',
        // A refused call is a 4xx and asking again cannot help — the monthly
        // ceiling being one of them.
        isRetryable: error.status >= 500,
      );
    } on Object {
      throw const RecipeAiException('Could not reach the list assistant.');
    }

    if (data is! Map) {
      throw const RecipeAiException(
        'That came back in a shape Hearth cannot read.',
      );
    }
    if (data['error'] case final Object error) {
      throw RecipeAiException('$error');
    }

    return answerFrom(data);
  }

  /// Reads the function's response.
  ///
  /// Public because it is the seam worth testing: the network cannot be mocked
  /// without mocking Supabase's client whole, but the parse can be exercised
  /// against every shape the function might send.
  static ShoppingAnswer answerFrom(Map<Object?, Object?> envelope) {
    final Object? raw = envelope['operations'];
    return ShoppingAnswer(
      reply: _textOrNull(envelope['reply']),
      edits: <ShoppingEdit>[
        if (raw is List<Object?>)
          for (final Object? item in raw)
            if (item is Map)
              if (_edit(item) case final ShoppingEdit edit) edit,
      ],
    );
  }

  static ShoppingEdit? _edit(Map<Object?, Object?> json) {
    final String name = '${json['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;

    final ShoppingEditKind? kind = switch ('${json['op'] ?? ''}') {
      'add' => ShoppingEditKind.add,
      'remove' => ShoppingEditKind.remove,
      'set_amount' => ShoppingEditKind.setAmount,
      'set_on_hand' => ShoppingEditKind.setOnHand,
      'check' => ShoppingEditKind.check,
      'uncheck' => ShoppingEditKind.uncheck,
      _ => null,
    };
    if (kind == null) return null;

    return ShoppingEdit(
      kind: kind,
      name: name,
      amount: _number(json['amount']),
      unitId: _textOrNull(json['unit']),
      // A shop, or nothing. "Anywhere" is Hearth's word for having no store
      // tag, and the model will happily hand it back as though it were one.
      storeTag: storeTagFrom(json['store_tag']),
    );
  }

  static String? _messageFrom(Object? details) {
    if (details is Map && details['error'] != null) {
      return '${details['error']}';
    }
    final String text = '${details ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static String? _textOrNull(Object? value) {
    final String text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}
