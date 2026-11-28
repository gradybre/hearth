import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/recipes/recipe_artwork.dart';

/// Which drawing a recipe wears, and when it wears none (spec §5.2).
///
/// The matching is the part of the artwork that can be wrong, and every
/// interesting case is a string — so this is pure Dart and costs nothing to
/// run (spec §9.1). A wrong picture is worse than no picture: a lentil dal
/// drawn as a lentil *packet*, or a pear tart drawn as a pear, is the app
/// telling you something false about your own recipe.
void main() {
  group('it finds the dish before the ingredient', () {
    for (final (String title, String expected) in <(String, String)>[
      ('Chicken pot pie stew', 'pot-pie'),
      ('Weeknight chilli', 'chilli-bowl'),
      ('Blueberry overnight oats', 'porridge-jar'),
      ('Pear and almond tart', 'tart'),
      ('Red lentil dal', 'curry-bowl'),
      ('Slow cooker beef stew', 'stew-pot'),
      ('Roast chicken with lemon', 'roast-chicken'),
      ('Spaghetti bolognese', 'pasta-plate'),
      ('Classic lasagne', 'lasagne'),
      ('Mushroom risotto', 'risotto'),
      ('Fish tacos', 'taco'),
      ('Banana bread', 'bread-loaf'),
      ('Chocolate brownies', 'brownie'),
      ('Tomato soup', 'soup-bowl'),
    ]) {
      test('"$title" is $expected', () {
        expect(pickRecipeArtwork(title: title), expected);
      });
    }
  });

  group('and nothing at all rather than something wrong', () {
    for (final String title in <String>[
      'Tuesday',
      "Mum's thing",
      'Leftovers',
      '',
    ]) {
      test('"$title" gets no drawing', () {
        expect(pickRecipeArtwork(title: title), isNull);
      });
    }
  });

  test('a longer phrase beats the word inside it', () {
    // "ice cream" is not a cream, and "pot pie" is not a pie dish. Registry
    // order cannot be relied on for this: the specific entry may be written
    // after the general one.
    expect(pickRecipeArtwork(title: 'Vanilla ice cream'), 'ice-cream');
    expect(pickRecipeArtwork(title: 'Sweet potato mash'), 'sweet-potato');
  });

  test('a word is a word, not a run of letters', () {
    // The trap a substring match walks into: "pear" inside "appeared",
    // "ham" inside "hammer", "fig" inside "figs" is fine but "fig" inside
    // "configure" is not.
    expect(pickRecipeArtwork(title: 'Dish that appeared on Tuesday'), isNull);
    expect(pickRecipeArtwork(title: 'Hammered flat'), isNull);
  });

  test('the title outranks a tag', () {
    // A soup filed under "batch" is a soup. The title is what the dish is
    // called; a tag is how it was filed.
    expect(
      pickRecipeArtwork(title: 'Tomato soup', tags: <String>['pizza']),
      'soup-bowl',
    );
  });

  test('but a tag and a cuisine can answer on their own', () {
    expect(
      pickRecipeArtwork(title: 'Tuesday dinner', tags: <String>['curry']),
      'curry-bowl',
    );
    expect(
      pickRecipeArtwork(title: 'Tuesday dinner', cuisine: 'Sushi'),
      'sushi',
    );
  });

  group('the registry itself', () {
    test('has no id twice', () {
      final Set<String> seen = <String>{};
      for (final RecipeArtwork art in kRecipeArtwork) {
        expect(seen.add(art.id), isTrue, reason: '${art.id} is listed twice');
      }
    });

    test('has ids that can be file names', () {
      for (final RecipeArtwork art in kRecipeArtwork) {
        expect(
          art.id,
          matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')),
          reason: '${art.id} is not a lower-case hyphenated name',
        );
      }
    });

    test('has no keyword twice across two drawings', () {
      // Two drawings answering to the same word is a coin toss decided by
      // registry order, which is not a decision anybody made.
      final Map<String, String> owner = <String, String>{};
      for (final RecipeArtwork art in kRecipeArtwork) {
        for (final String keyword in art.keywords) {
          final String? already = owner[keyword];
          expect(
            already,
            isNull,
            reason: '"$keyword" is claimed by both $already and ${art.id}',
          );
          owner[keyword] = art.id;
        }
      }
    });

    test('has no empty keyword', () {
      for (final RecipeArtwork art in kRecipeArtwork) {
        expect(art.keywords, isNotEmpty, reason: '${art.id} has no words');
        for (final String keyword in art.keywords) {
          expect(recipeWords(keyword), isNotEmpty, reason: art.id);
        }
      }
    });
  });
}
