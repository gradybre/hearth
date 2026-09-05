import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';

/// Revising a draft without losing what the model was never asked about
/// (spec §5.4).
///
/// The chat hands the model the recipe as words and gets a whole recipe back.
/// What comes back is content; what stays is identity — and getting that wrong
/// is how "swap steps 2 and 3" quietly saves a second copy of your recipe with
/// none of its foods attached.
void main() {
  RecipeDraft original() => const RecipeDraft(
    title: 'Beef ragu',
    servings: 4,
    prepMinutes: 15,
    cookMinutes: 90,
    cuisine: 'Italian',
    tags: <String>['dinner'],
    notes: 'Doubles well. Freeze half.',
    existingId: 'recipe-1',
    matches: <String, String>{
      'ground beef': 'food-beef',
      'tinned tomatoes': 'food-tomatoes',
    },
    noMatch: <String>{'salt'},
    sections: <DraftSection>[
      DraftSection(
        name: 'Sauce',
        ingredientsText: '500 g ground beef\n2 tins tinned tomatoes\nsalt',
        directionsText: 'Brown the beef.\nAdd the tomatoes.',
      ),
    ],
  );

  RecipeDraft reordered() => const RecipeDraft(
    title: 'Beef ragu',
    servings: 4,
    prepMinutes: 15,
    cookMinutes: 90,
    cuisine: 'Italian',
    tags: <String>['dinner'],
    sections: <DraftSection>[
      DraftSection(
        name: 'Sauce',
        ingredientsText: '500 g ground beef\n2 tins tinned tomatoes\nsalt',
        directionsText: 'Add the tomatoes.\nBrown the beef.',
      ),
    ],
  );

  group('what a revision replaces', () {
    test('the content, which is what was asked for', () {
      final RecipeDraft revised = original().revisedWith(reordered());

      expect(
        revised.sections.single.directionsText,
        'Add the tomatoes.\nBrown the beef.',
      );
    });
  });

  group('what a revision must never touch', () {
    test('the recipe it is, or an edit becomes a second copy', () {
      expect(original().revisedWith(reordered()).existingId, 'recipe-1');
    });

    test('the foods already attached to it', () {
      // Keyed by name, so a reorder of the steps costs nothing. Losing these
      // would make every revision a re-match of the whole recipe.
      final RecipeDraft revised = original().revisedWith(reordered());

      expect(revised.matches, <String, String>{
        'ground beef': 'food-beef',
        'tinned tomatoes': 'food-tomatoes',
      });
      expect(revised.noMatch, <String>{'salt'});
    });

    test('the notes, which it was never shown', () {
      // The model is not asked about these, so it must not be able to delete
      // them by failing to mention them.
      expect(
        original().revisedWith(reordered()).notes,
        'Doubles well. Freeze half.',
      );
    });
  });

  group('a deduction across the round trip (spec §5.2, §5.4)', () {
    // The one thing in a recipe that a lossy round trip can invert rather
    // than lose. `toPrompt` writes "−1 oz Lettuce" with the real minus; a
    // model that types the keyboard's hyphen instead sends back
    // "-1 oz Lettuce", the parser reads that leading hyphen as the bullet it
    // usually is and strips it, and one ounce of lettuce is *added* to a meal
    // somebody ordered without any. On screen the two characters are the same
    // width and nearly the same glyph, so the review screen cannot catch it.
    RecipeDraft noLettuce({String sign = '−'}) => RecipeDraft(
      title: 'Burger, no salad',
      servings: 1,
      sections: <DraftSection>[
        DraftSection(
          ingredientsText: '1 Single Steakburger\n${sign}1 oz Lettuce',
          directionsText: 'Order it.',
        ),
      ],
    );

    test('survives the model writing it back with a plain hyphen', () {
      final RecipeDraft revised = noLettuce().revisedWith(noLettuce(sign: '-'));

      expect(
        revised.sections.single.ingredientsText,
        contains('−1 oz Lettuce'),
      );
      final ParsedIngredient lettuce = revised.parsedIngredients.last;
      expect(lettuce.name, 'Lettuce');
      expect(lettuce.quantity!.canonicalAmount, lessThan(0));
    });

    test('and survives it being written back with no sign at all', () {
      final RecipeDraft revised = noLettuce().revisedWith(noLettuce(sign: ''));

      expect(
        revised.parsedIngredients.last.quantity!.canonicalAmount,
        lessThan(0),
      );
    });

    test('a line nobody took out is left exactly as it was written', () {
      // The other half of the rule, and the reason a hyphen can never be read
      // as a minus: every pasted ingredient list in the world is bulleted with
      // one, and a model answering in bullets writes them by the dozen.
      final RecipeDraft plain = const RecipeDraft(
        title: 'Omelette',
        servings: 1,
        sections: <DraftSection>[
          DraftSection(ingredientsText: '2 eggs\n1 oz Lettuce'),
        ],
      );
      final RecipeDraft revised = plain.revisedWith(
        const RecipeDraft(
          title: 'Omelette',
          servings: 1,
          sections: <DraftSection>[
            DraftSection(ingredientsText: '- 3 eggs\n- 1 oz Lettuce'),
          ],
        ),
      );

      expect(
        revised.sections.single.ingredientsText,
        '- 3 eggs\n- 1 oz Lettuce',
      );
      for (final ParsedIngredient line in revised.parsedIngredients) {
        expect(line.quantity!.canonicalAmount, greaterThan(0));
      }
    });

    test('and a name the model genuinely changed keeps its own sign', () {
      // Same rule the food matches follow: what the model renamed is the
      // model's, because the old line is no longer the thing it said.
      final RecipeDraft revised = noLettuce().revisedWith(
        const RecipeDraft(
          title: 'Burger, no salad',
          servings: 1,
          sections: <DraftSection>[
            DraftSection(ingredientsText: '1 Single Steakburger\n1 oz Tomato'),
          ],
        ),
      );

      expect(
        revised.parsedIngredients.last.quantity!.canonicalAmount,
        greaterThan(0),
      );
    });
  });

  group('the recipe as the model sees it', () {
    test('carries the fields a revision needs to preserve', () {
      final String prompt = original().toPrompt();

      expect(prompt, contains('Beef ragu'));
      expect(prompt, contains('Serves 4'));
      expect(prompt, contains('## Sauce'));
      expect(prompt, contains('500 g ground beef'));
      expect(prompt, contains('Brown the beef.'));
    });

    test('is the draft as it stands, not as it was imported', () {
      // The point of sending the current draft: a hand edit made before
      // asking for a change must not be silently undone by the answer.
      final RecipeDraft edited = original().copyWith(
        sections: <DraftSection>[
          original().sections.single.copyWith(
            ingredientsText: '600 g ground beef\n2 tins tinned tomatoes\nsalt',
          ),
        ],
      );

      expect(edited.toPrompt(), contains('600 g ground beef'));
      expect(edited.toPrompt(), isNot(contains('500 g')));
    });
  });
}
