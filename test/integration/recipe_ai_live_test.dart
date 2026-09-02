@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_recipe_ai.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/features/recipes/ai_recipe_mapper.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/live_config.dart';

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
  final ({String url, String key})? config = liveConfig();
  final String? skip = liveSkipReason();

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

  test(
    'a note overrides what the source appears to say',
    () async {
      // The upload page's notes field. The reader cannot know from the page
      // which end of a range was meant, or that the printed yield is wrong.
      final AiRecipe recipe = await ai.extract(
        text:
            'Garlic butter pasta. Serves 2-4. '
            '200-300g spaghetti, 2 cloves garlic, 50g butter. '
            'Boil pasta. Melt butter with garlic. Toss.',
        notes: 'Take the higher number in any range, and this serves 6.',
      );

      expect(recipe.servings, 6);
      expect(
        recipe.sections.map((AiSection s) => s.ingredientsText).join(),
        contains('300'),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a revision changes what was asked and says what it changed',
    () async {
      // The editor's chat. The whole recipe comes back, not a diff, and the
      // reply is the only thing that saves the user diffing two recipes by eye.
      final AiRecipe revised = await ai.generate(
        turns: <AiTurn>[
          const AiTurn(fromUser: true, text: 'Swap steps 1 and 2.'),
        ],
        recipe:
            'Garlic butter pasta\nServes 4\n\n## Main\nIngredients:\n'
            '300g spaghetti\n50g butter\nDirections:\n'
            'Boil the pasta.\nMelt the butter.',
      );

      expect(revised.sections, isNotEmpty);
      expect(revised.reply, isNotNull);
      expect(revised.reply, isNotEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'every answer says where the month budget stands',
    () async {
      // §3, §8.1: the ceiling is enforced server-side, and the app is told so it
      // can warn before it is refused.
      final AiRecipe recipe = await ai.extract(text: 'Toast. 1 slice bread.');

      expect(recipe.usage, isNotNull);
      expect(recipe.usage!.ceilingUsd, greaterThan(0));
      expect(recipe.usage!.fraction, greaterThanOrEqualTo(0));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
