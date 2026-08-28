import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/recipe_query.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('text search', () {
    test('finds a recipe by its title, case-insensitively', () {
      final Recipe recipe = aRecipe(title: 'Braised Short Ribs');
      expect(RecipeSearch.matchesText(recipe, 'short ribs'), isTrue);
      expect(RecipeSearch.matchesText(recipe, 'BRAISED'), isTrue);
    });

    test('finds a recipe by an ingredient it contains', () {
      final Recipe recipe = aRecipe(
        title: 'Sunday roast',
        ingredients: <RecipeIngredient>[
          anIngredient('fennel bulb', amount: 1, unit: Units.item),
        ],
      );
      expect(RecipeSearch.matchesText(recipe, 'fennel'), isTrue);
    });

    test('finds a recipe by tag and by cuisine', () {
      final Recipe recipe = aRecipe(
        title: 'Pad see ew',
        tags: <String>['weeknight'],
        cuisine: 'Thai',
      );
      expect(RecipeSearch.matchesText(recipe, 'thai'), isTrue);
      expect(RecipeSearch.matchesText(recipe, 'weeknight'), isTrue);
    });

    test('ignores accents in both the query and the recipe', () {
      final Recipe recipe = aRecipe(title: 'Jalapeño poppers');
      expect(RecipeSearch.matchesText(recipe, 'jalapeno'), isTrue);

      final Recipe plain = aRecipe(title: 'Jalapeno poppers');
      expect(RecipeSearch.matchesText(plain, 'jalapeño'), isTrue);
    });

    test('every term must match, so more typing narrows', () {
      final Recipe thai = aRecipe(title: 'Thai chicken curry');
      final Recipe roast = aRecipe(title: 'Roast chicken');

      expect(RecipeSearch.matchesText(thai, 'chicken thai'), isTrue);
      expect(RecipeSearch.matchesText(roast, 'chicken thai'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(RecipeSearch.matchesText(aRecipe(), '   '), isTrue);
    });

    test('does not search step text — "chopped" would match the library', () {
      final Recipe recipe = aRecipe(
        title: 'Soup',
        steps: <RecipeStep>[aStep('Chop the onion finely')],
      );
      expect(RecipeSearch.matchesText(recipe, 'chop'), isFalse);
    });
  });

  group('chips combine', () {
    Recipe thaiWeeknight() => aRecipe(
      id: 'thai',
      title: 'Pad see ew',
      tags: <String>['weeknight'],
      cuisine: 'Thai',
      cookTime: const Duration(minutes: 20),
    );
    Recipe italianSlow() => aRecipe(
      id: 'ragu',
      title: 'Ragu',
      tags: <String>['sunday'],
      cuisine: 'Italian',
      cookTime: const Duration(hours: 4),
    );

    test('different dimensions AND together, narrowing', () {
      const RecipeFilter filter = RecipeFilter(
        cuisines: <String>{'thai'},
        maxTotalTime: Duration(minutes: 30),
      );
      expect(RecipeSearch.matches(thaiWeeknight(), filter), isTrue);
      expect(RecipeSearch.matches(italianSlow(), filter), isFalse);
    });

    test('values within one dimension OR together, widening', () {
      const RecipeFilter filter = RecipeFilter(
        cuisines: <String>{'thai', 'italian'},
      );
      expect(RecipeSearch.matches(thaiWeeknight(), filter), isTrue);
      expect(RecipeSearch.matches(italianSlow(), filter), isTrue);
    });

    test('tags match any of the chosen tags', () {
      const RecipeFilter filter = RecipeFilter(tags: <String>{'weeknight'});
      expect(RecipeSearch.matches(thaiWeeknight(), filter), isTrue);
      expect(RecipeSearch.matches(italianSlow(), filter), isFalse);
    });

    test('activeCount counts every lit chip, not every dimension', () {
      const RecipeFilter filter = RecipeFilter(
        favoritesOnly: true,
        tags: <String>{'a', 'b'},
        maxTotalTime: Duration(minutes: 30),
      );
      expect(filter.activeCount, 4);
      expect(filter.isEmpty, isFalse);
      expect(RecipeFilter.none.isEmpty, isTrue);
    });

    test('toggling a chip twice returns to where it started', () {
      final RecipeFilter once = RecipeFilter.none.toggleTag('Weeknight');
      expect(once.tags, <String>{'weeknight'});
      expect(once.toggleTag('Weeknight').tags, isEmpty);
    });
  });

  group('unknown is never treated as passing', () {
    test('a recipe with no times is excluded by a time filter', () {
      // "Under 30 minutes" handing back an untimed four-hour braise is worse
      // than handing back nothing.
      final Recipe untimed = aRecipe(title: 'Mystery');
      expect(
        RecipeSearch.matches(
          untimed,
          const RecipeFilter(maxTotalTime: Duration(minutes: 30)),
        ),
        isFalse,
      );
    });

    test('a recipe with no macros is excluded by a macro filter', () {
      expect(
        RecipeSearch.matches(
          aRecipe(),
          const RecipeFilter(maxKcalPerServing: 600),
        ),
        isFalse,
      );
    });

    test('prep and cook time add up for the time filter', () {
      final Recipe recipe = aRecipe(
        prepTime: const Duration(minutes: 20),
        cookTime: const Duration(minutes: 20),
      );
      expect(
        RecipeSearch.matches(
          recipe,
          const RecipeFilter(maxTotalTime: Duration(minutes: 30)),
        ),
        isFalse,
      );
      expect(
        RecipeSearch.matches(
          recipe,
          const RecipeFilter(maxTotalTime: Duration(minutes: 45)),
        ),
        isTrue,
      );
    });
  });

  group('favourites and collections', () {
    test('favourites-only hides everything not favourited', () {
      const RecipeFilter filter = RecipeFilter(favoritesOnly: true);
      expect(
        RecipeSearch.matches(
          aRecipe(),
          filter,
          context: const RecipeContext(isFavorite: true),
        ),
        isTrue,
      );
      expect(RecipeSearch.matches(aRecipe(), filter), isFalse);
    });

    test('a collection chip keeps only that collection', () {
      const RecipeFilter filter = RecipeFilter(
        collectionIds: <String>{'weeknight'},
      );
      expect(
        RecipeSearch.matches(
          aRecipe(),
          filter,
          context: const RecipeContext(collectionIds: <String>{'weeknight'}),
        ),
        isTrue,
      );
      expect(
        RecipeSearch.matches(
          aRecipe(),
          filter,
          context: const RecipeContext(collectionIds: <String>{'sunday'}),
        ),
        isFalse,
      );
    });

    test('macro chips read the per-serving macros handed in', () {
      const RecipeContext lean = RecipeContext(
        perServing: Macros(kcal: 420, proteinG: 45),
      );
      expect(
        RecipeSearch.matches(
          aRecipe(),
          const RecipeFilter(maxKcalPerServing: 500),
          context: lean,
        ),
        isTrue,
      );
      expect(
        RecipeSearch.matches(
          aRecipe(),
          const RecipeFilter(minProteinPerServing: 50),
          context: lean,
        ),
        isFalse,
      );
    });
  });

  group('applying to a library', () {
    test('favourites sort first, then title', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'c', title: 'Chili'),
        aRecipe(id: 'a', title: 'Aubergine bake'),
        aRecipe(id: 'z', title: 'Ziti'),
      ];

      final List<Recipe> result = RecipeSearch.apply(
        library,
        RecipeFilter.none,
        contextOf: (Recipe r) => RecipeContext(isFavorite: r.id == 'z'),
      );

      expect(
        result.map((Recipe r) => r.id),
        <String>['z', 'a', 'c'],
        reason: 'the weekly favourite should not be buried under the alphabet',
      );
    });

    test('soft-deleted recipes never appear', () {
      // They are kept forever so old logs resolve (§4) — the library is not
      // where they belong.
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'gone', title: 'Removed', isDeleted: true),
        aRecipe(id: 'here', title: 'Kept'),
      ];
      expect(
        RecipeSearch.apply(library, RecipeFilter.none).map((Recipe r) => r.id),
        <String>['here'],
      );
    });

    test('offers the tags and cuisines the library actually has', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(tags: <String>['Weeknight', 'quick'], cuisine: 'Thai'),
        aRecipe(tags: <String>['weeknight'], cuisine: 'thai'),
        aRecipe(tags: <String>['sunday'], cuisine: 'Italian', isDeleted: true),
      ];

      expect(RecipeSearch.tagsIn(library), <String>['quick', 'weeknight']);
      expect(RecipeSearch.cuisinesIn(library), <String>['thai']);
    });
  });
}
