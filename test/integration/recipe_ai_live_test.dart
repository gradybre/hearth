@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_recipe_ai.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/features/recipes/ai_recipe_mapper.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The recipe-ai Edge Function, against the deployed one (spec §9.4).
///
/// A contract test: what the function promises to return is what this adapter
/// knows how to read. It cannot be exercised any other way, because the seam
/// is exactly where the Claude API key lives (§8.1).
///
/// These calls cost money, which is why they are tagged and skipped by
/// default. Run deliberately:
///
///   HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  final ({String url, String key})? config = _hostedConfig();
  final String? skip = config == null
      ? 'needs HEARTH_LIVE=1 and config/hosted.json'
      : null;

  late EdgeFunctionRecipeAi ai;

  setUpAll(() {
    // flutter_test mocks HttpClient and returns 400 for everything unless the
    // override is cleared, which makes every real call look like a rejection.
    HttpOverrides.global = null;
    if (config == null) return;
    ai = EdgeFunctionRecipeAi(SupabaseClient(config.url, config.key));
  });

  test(
    'generation returns a recipe Hearth can open',
    () async {
      final AiRecipe recipe = await ai.generate(
        turns: const <AiTurn>[
          AiTurn(
            fromUser: true,
            text: 'A simple high-protein breakfast for two. No shellfish.',
          ),
        ],
      );

      expect(recipe.title, isNotEmpty);
      expect(recipe.sections, isNotEmpty);
      expect(recipe.sections.first.ingredientsText, isNotEmpty);
      expect(recipe.sections.first.directionsText, isNotEmpty);
      // §5.4: the chat needs something to say back.
      expect(recipe.reply, isNotNull);

      // And it survives the trip into a draft the editor could open.
      final RecipeDraft draft = AiRecipeMapper.toDraft(recipe);
      expect(draft.title, isNotEmpty);
      expect(draft.servings, greaterThan(0));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the food profile is honoured, not just accepted',
    () async {
      // An allergy is a hard constraint (§5.4). Worth an assertion rather than
      // trust: this is the failure that would matter.
      final AiRecipe recipe = await ai.generate(
        turns: const <AiTurn>[
          AiTurn(fromUser: true, text: 'A quick weeknight pasta.'),
        ],
        profile: const <String, Object?>{
          'allergies': <String>['peanuts'],
          'dislikes': <String>['mushrooms'],
        },
      );

      final String text = <String>[
        for (final AiSection section in recipe.sections)
          '${section.ingredientsText}\n${section.directionsText}',
      ].join('\n').toLowerCase();

      expect(text, isNot(contains('peanut')));
      expect(text, isNot(contains('mushroom')));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('an ask with nothing in it never reaches the model', () async {
    // Refused in the adapter, so it costs nothing and offers no retry.
    expect(
      () => ai.extract(),
      throwsA(
        isA<RecipeAiException>().having(
          (RecipeAiException e) => e.isRetryable,
          'isRetryable',
          isFalse,
        ),
      ),
    );
  }, skip: skip);
}

/// The hosted project's URL and publishable key, or null when not set up.
///
/// Read from the gitignored config, never from the repo. The Claude key is not
/// here and never passes through the client — that is the whole reason the
/// function exists.
({String url, String key})? _hostedConfig() {
  if (Platform.environment['HEARTH_LIVE'] != '1') return null;

  final File file = File('config/hosted.json');
  if (!file.existsSync()) return null;

  final String text = file.readAsStringSync();
  final String? url = RegExp('"SUPABASE_URL"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);
  final String? key = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);

  if (url == null || key == null || key.isEmpty) return null;
  return (url: url, key: key);
}
