import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_recipe_ai.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reading what the `recipe-ai` function sends back (spec §9.4).
///
/// The function's own behaviour is covered live, because the key lives there
/// and the seam cannot be exercised any other way. This covers the half that
/// can be: every shape the response might arrive in, including the ones it
/// should never arrive in.
Map<Object?, Object?> envelope({
  Object? recipe = const <Object?, Object?>{
    'title': 'Braised short ribs',
    'servings': 4,
    'sections': <Object?>[
      <Object?, Object?>{
        'name': '',
        'ingredients_text': '2 tbsp olive oil',
        'directions_text': 'Heat the oil.',
      },
    ],
  },
  Object? uncertain,
  Object? reply,
}) => <Object?, Object?>{
  'recipe': recipe,
  'uncertain': uncertain ?? <Object?>[],
  'reply': reply,
};

void main() {
  test('a well-formed response reads through', () {
    final AiRecipe recipe = EdgeFunctionRecipeAi.recipeFrom(envelope());

    expect(recipe.title, 'Braised short ribs');
    expect(recipe.servings, 4);
    expect(recipe.sections.single.ingredientsText, '2 tbsp olive oil');
  });

  test('flagged fields come through so the editor can point at them', () {
    final AiRecipe recipe = EdgeFunctionRecipeAi.recipeFrom(
      envelope(
        uncertain: <Object?>[
          <Object?, Object?>{
            'field': 'salt',
            'note': 'Could be 1/2 tsp or 12 tsp.',
          },
        ],
      ),
    );

    expect(recipe.uncertain.single.field, 'salt');
    expect(recipe.uncertain.single.note, contains('1/2'));
  });

  test('a generation reply is carried; an extraction has none', () {
    expect(
      EdgeFunctionRecipeAi.recipeFrom(envelope(reply: 'Made it spicier.'))
          .reply,
      'Made it spicier.',
    );
    expect(EdgeFunctionRecipeAi.recipeFrom(envelope()).reply, isNull);
  });

  test('a response with no recipe is refused, not half-read', () {
    expect(
      () => EdgeFunctionRecipeAi.recipeFrom(<Object?, Object?>{'reply': 'hi'}),
      throwsA(isA<RecipeAiException>()),
    );
  });

  test('junk in a field is dropped rather than crashing the import', () {
    // The function narrows the shape, so this should never arrive — which is
    // exactly why it is worth being sure it cannot take the app down.
    final AiRecipe recipe = EdgeFunctionRecipeAi.recipeFrom(
      envelope(
        recipe: <Object?, Object?>{
          'title': 42,
          'servings': 'four',
          'prep_minutes': double.nan,
          'tags': 'weeknight',
          'sections': 'not a list',
        },
      ),
    );

    expect(recipe.title, isEmpty);
    expect(recipe.servings, isNull);
    expect(recipe.prepMinutes, isNull);
    expect(recipe.tags, isEmpty);
    expect(recipe.sections, isEmpty);
  });

  test('a missing sections list is empty, not an error', () {
    // §5.3: missing data never blocks. The mapper gives the editor a section
    // to open with; refusing here would turn a thin import into a dead end.
    final AiRecipe recipe = EdgeFunctionRecipeAi.recipeFrom(
      envelope(recipe: <Object?, Object?>{'title': 'Toast'}),
    );

    expect(recipe.title, 'Toast');
    expect(recipe.sections, isEmpty);
  });

  group('asks that cannot be answered never reach the network', () {
    // Built inside a test rather than at declaration: constructing a Supabase
    // client opens an HttpClient, and flutter_test only allows that inside a
    // test zone. It is never actually used — both guards return before any
    // call — and its credentials are placeholders, not a real project's.
    late EdgeFunctionRecipeAi ai;
    setUp(() {
      ai = EdgeFunctionRecipeAi(
        SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_not_a_key',
        ),
      );
    });

    Matcher refusedOutright() => throwsA(
      isA<RecipeAiException>().having(
        (RecipeAiException e) => e.isRetryable,
        'isRetryable',
        isFalse,
      ),
    );

    test('no images and no url', () {
      // No model can answer this, so offering a retry would be a lie.
      expect(ai.extract, refusedOutright());
    });

    test('a generation with nothing said yet', () {
      expect(() => ai.generate(turns: const <AiTurn>[]), refusedOutright());
    });
  });
}
