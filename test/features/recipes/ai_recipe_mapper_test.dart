import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/features/recipes/ai_recipe_mapper.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:test/test.dart';

/// Making the model's answer safe to open in the editor (spec §5.3).
///
/// Nothing here rejects a recipe: §5.3 is explicit that missing data never
/// blocks. A thin import is something the user finishes in the editor, not an
/// error to argue with.
AiSection section(String ingredients, String directions, {String name = ''}) =>
    AiSection(
      name: name,
      ingredientsText: ingredients,
      directionsText: directions,
    );

AiRecipe recipe({
  String title = 'Braised short ribs',
  List<AiSection>? sections,
  double? servings = 4,
  int? prepMinutes,
  int? cookMinutes,
  String? cuisine,
  List<String> tags = const <String>[],
}) => AiRecipe(
  title: title,
  servings: servings,
  prepMinutes: prepMinutes,
  cookMinutes: cookMinutes,
  cuisine: cuisine,
  tags: tags,
  sections:
      sections ?? <AiSection>[section('2 tbsp olive oil', 'Heat the oil.')],
);

void main() {
  test('carries the recipe through as written', () {
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        cuisine: 'Italian',
        tags: <String>['weeknight'],
        prepMinutes: 15,
        cookMinutes: 90,
      ),
    );

    expect(draft.title, 'Braised short ribs');
    expect(draft.servings, 4);
    expect(draft.prepMinutes, 15);
    expect(draft.cookMinutes, 90);
    expect(draft.cuisine, 'Italian');
    expect(draft.tags, <String>['weeknight']);
    expect(draft.sections.single.ingredientsText, '2 tbsp olive oil');
  });

  test('a source with no stated yield opens like a new recipe', () {
    // Four is the editor's own default, so an import with no yield behaves
    // exactly as one typed by hand — and the field is right there to correct.
    expect(AiRecipeMapper.toDraft(recipe(servings: null)).servings, 4);
    expect(AiRecipeMapper.toDraft(recipe(servings: 0)).servings, 4);
  });

  test('an absurd time is dropped rather than shown as fact', () {
    // Beyond a day it is a misread, not a slow cook. Empty invites a correct
    // answer; "1440" invites belief.
    expect(
      AiRecipeMapper.toDraft(recipe(cookMinutes: 5000)).cookMinutes,
      isNull,
    );
    expect(AiRecipeMapper.toDraft(recipe(prepMinutes: -5)).prepMinutes, isNull);
    // An overnight prove is still a real time.
    expect(AiRecipeMapper.toDraft(recipe(prepMinutes: 720)).prepMinutes, 720);
  });

  test('step numbers from the source are stripped', () {
    // Hearth numbers steps itself, so a kept "1." would end up inside the
    // step's own text.
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        sections: <AiSection>[
          section(
            '2 tbsp olive oil',
            '1. Heat the oil.\n2) Add the garlic.\nStep 3: Serve.',
          ),
        ],
      ),
    );

    expect(
      draft.sections.single.directionsText,
      'Heat the oil.\nAdd the garlic.\nServe.',
    );
  });

  test('a quantity at the start of a line is never mistaken for a number', () {
    // The one thing stripping must not touch.
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        sections: <AiSection>[
          section('1 tbsp olive oil\n2 cloves garlic\n12 sage leaves', 'Cook.'),
        ],
      ),
    );

    expect(
      draft.sections.single.ingredientsText,
      '1 tbsp olive oil\n2 cloves garlic\n12 sage leaves',
    );
  });

  test('blank lines and stray whitespace are tidied', () {
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        sections: <AiSection>[
          section(
            '  2 tbsp olive oil  \n\n\n3 cloves garlic\n',
            'Cook.\r\n\r\nServe.',
          ),
        ],
      ),
    );

    expect(
      draft.sections.single.ingredientsText,
      '2 tbsp olive oil\n3 cloves garlic',
    );
    expect(draft.sections.single.directionsText, 'Cook.\nServe.');
  });

  test('an invented empty section is dropped', () {
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        sections: <AiSection>[
          section('2 tbsp olive oil', 'Heat the oil.'),
          section('', '', name: 'For the garnish'),
        ],
      ),
    );

    expect(draft.sections, hasLength(1));
  });

  test('a recipe with no sections still opens', () {
    // The editor must never open section-less, and an empty import is
    // something to finish rather than an error.
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(sections: <AiSection>[]),
    );

    expect(draft.sections, hasLength(1));
    expect(draft.sections.single.ingredientsText, isEmpty);
  });

  test('real sections keep their names and order', () {
    final RecipeDraft draft = AiRecipeMapper.toDraft(
      recipe(
        sections: <AiSection>[
          section('500 g beef', 'Brown it.', name: 'Main'),
          section('2 tbsp soy', 'Whisk.', name: 'Sauce'),
        ],
      ),
    );

    expect(draft.sections.map((DraftSection s) => s.name), <String>[
      'Main',
      'Sauce',
    ]);
  });

  test('an empty title is left empty for the editor to insist on', () {
    // Saving already requires a title; inventing one here would hide that the
    // model never found it.
    expect(AiRecipeMapper.toDraft(recipe(title: '   ')).title, isEmpty);
  });
}
