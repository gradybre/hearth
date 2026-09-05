import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/recipes/sketch_icon.dart';
import 'recipe_icon.dart';

/// Drawing a recipe's icon through the `recipe-ai` Edge Function
/// (spec §5.2, §6.1).
///
/// The same function as import and label reading, for the same reason they
/// share one: same key, same model, same budget counter. The icon mode is the
/// one that yields first — the function refuses it well below the ceiling
/// that stops everything else, so a month of pictures can never be why a
/// recipe import is turned away.
///
/// Nothing unvalidated leaves this class. The markup is written by a model
/// and it renders in the app, so [SketchIcon.parse] is the gate and a failure
/// of it is answered the same way a network failure is: no icon.
class EdgeFunctionRecipeIcon implements RecipeIconSource {
  EdgeFunctionRecipeIcon(this._client);

  static const String functionName = 'recipe-ai';

  final SupabaseClient _client;

  @override
  Future<String?> draw({required String title}) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: <String, Object?>{'mode': 'icon', 'title': trimmed},
      );
      data = response.data;
    } on Object {
      // Every failure is the same failure here, including the deliberate one:
      // the function answers 429 once icons have spent their share of the
      // month's budget, and that is a picture not being drawn, not a fault to
      // report. Nothing about a decorative sketch is worth a message.
      return null;
    }

    if (data is! Map) return null;
    if (data['error'] != null) return null;

    return iconFrom(data);
  }

  /// Reads the function's response into markup that is safe to draw, or null.
  ///
  /// Public because it is the seam worth testing: the network cannot be
  /// mocked here without mocking Supabase's client whole, but this can be
  /// exercised against every shape the function might send — including the
  /// hostile ones it should never send, which is the case that matters.
  static String? iconFrom(Map<Object?, Object?> envelope) {
    final Object? svg = envelope['svg'];
    if (svg is! String) return null;

    final String markup = svg.trim();
    return SketchIcon.isValid(markup) ? markup : null;
  }
}
