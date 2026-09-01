import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/food_relevance.dart';

/// What a search result *is*, as against which of the typed words it repeats.
///
/// Every name here came back from a real search. The ones that made the fix
/// necessary are the products: they contain the whole query, often twice, and
/// are still not what anybody was looking for.
void main() {
  FoodRelevance against(String name, String query) =>
      FoodRelevance.of(name, FoodRelevance.termsOf(query));

  group('the kind of thing a name says it is', () {
    test('is the head noun, because English puts it last', () {
      expect(
        FoodRelevance.headOf(FoodRelevance.kindWords('Chicken broth')),
        'broth',
      );
      expect(
        FoodRelevance.headOf(
          FoodRelevance.kindWords('CREAMY RED BELL PEPPER SAUCE'),
        ),
        'sauce',
      );
    });

    test('stops at the comma, where USDA starts qualifying', () {
      // "Peppers, sweet, red, raw" is a pepper. The words after the comma say
      // which pepper and what was done to it.
      expect(FoodRelevance.kindWords('Peppers, sweet, red, raw'), <String>[
        'peppers',
      ]);
      // And the same rule keeps a pasta from passing itself off as produce.
      expect(FoodRelevance.kindWords('FIORI, RED BELL PEPPER'), <String>[
        'fiori',
      ]);
    });

    test('stops at a preposition, because rice with broth is rice', () {
      expect(FoodRelevance.kindWords('Rice with chicken broth'), <String>[
        'rice',
      ]);
    });

    test('a number is not a head noun', () {
      // "96/4" normalises to a bare number and trails the name it describes.
      expect(
        FoodRelevance.headOf(FoodRelevance.termsOf('ground beef 96/4')),
        'beef',
      );
    });
  });

  group('a search for red bell pepper', () {
    const String query = 'red bell pepper';

    test('finds the vegetable, plural and all', () {
      expect(against('Peppers, red, cooked', query).sameKind, isTrue);
      expect(against('Peppers, sweet, red, raw', query).sameKind, isTrue);
    });

    test('does not find chips, hummus, sauce, or couscous', () {
      // Each of these contains all three words — twice, in most cases — which
      // is exactly why ranking on wording alone put them above the pepper.
      for (final String name in <String>[
        'RED BELL PEPPER VEGGIE CHIPS, RED BELL PEPPER',
        'RED BELL PEPPER & BASIL COUSCOUS, RED BELL PEPPER & BASIL',
        'ROASTED RED BELL PEPPER HUMMUS, ROASTED RED BELL PEPPER',
        'CREAMY RED BELL PEPPER SAUCE, CREAMY RED BELL PEPPER',
        "Brad's raw chips, red bell pepper chips",
        'FIORI, RED BELL PEPPER',
      ]) {
        expect(
          against(name, query).sameKind,
          isFalse,
          reason: '$name is not a pepper',
        );
      }
    });

    test('and wording alone would still have put the chips first', () {
      // The bug, pinned. "Red bell pepper veggie chips" says every word that
      // was typed; "Peppers, sweet, red, raw" never says "bell" at all, so no
      // amount of tuning the wording score reaches the right answer. Kind is
      // not a tiebreak here — it is the only thing that separates them.
      expect(
        against('RED BELL PEPPER VEGGIE CHIPS, RED BELL PEPPER', query).score,
        greaterThan(against('Peppers, sweet, red, raw', query).score),
      );
    });
  });

  group('wording still orders things of the same kind', () {
    const String query = 'chicken broth';

    test('the plain name beats the one that adds a word', () {
      expect(
        against('Chicken broth', query).score,
        greaterThan(against('Chicken broth concentrate', query).score),
      );
    });

    test('and adding a word beats being a different food entirely', () {
      // "Rice with chicken broth" spends its whole kind on rice.
      expect(
        against('Chicken broth concentrate', query).score,
        greaterThan(against('Rice with chicken broth', query).score),
      );
    });
  });

  group('naming a brand still finds that brand', () {
    // The mirror of the pepper case, and the reason kind alone cannot decide
    // everything: here the branded product and the generic are the same kind,
    // so the words have to break the tie — and the brand is one of them.
    const String query = 'oikos greek yogurt';

    test('both are yogurt', () {
      expect(
        against('OIKOS TRIPLE ZERO GREEK NONFAT YOGURT', query).sameKind,
        isTrue,
      );
      expect(against('Yogurt, Greek, plain, nonfat', query).sameKind, isTrue);
    });

    test('the one that answers every word wins', () {
      expect(
        against('OIKOS TRIPLE ZERO GREEK NONFAT YOGURT', query).score,
        greaterThan(against('Yogurt, Greek, plain, nonfat', query).score),
      );
    });
  });

  test('an empty query has no opinion', () {
    final FoodRelevance none = against('Anything at all', '');
    expect(none.sameKind, isFalse);
    expect(none.score, 0);
  });
}
