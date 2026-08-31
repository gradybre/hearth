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

    test('undated recipes fall through to title, as they always did', () {
      // The library above has no timestamps, so with the default recency sort
      // every comparison is a tie and the title tiebreaker decides — which is
      // exactly the ordering this had before sorting was configurable. Stated
      // outright because it is what keeps the test above honest rather than
      // accidentally passing.
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'c', title: 'Chili'),
        aRecipe(id: 'a', title: 'Aubergine bake'),
      ];

      expect(
        RecipeSearch.apply(library, RecipeFilter.none).map((Recipe r) => r.id),
        <String>['a', 'c'],
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

  group('sorting', () {
    DateTime at(int day) => DateTime.utc(2026, 8, day);

    test('most recent first is the default', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'old', title: 'Aaa', updatedAt: at(1)),
        aRecipe(id: 'new', title: 'Zzz', updatedAt: at(3)),
        aRecipe(id: 'mid', title: 'Mmm', updatedAt: at(2)),
      ];

      expect(
        RecipeSearch.apply(library, RecipeFilter.none).map((Recipe r) => r.id),
        <String>['new', 'mid', 'old'],
      );
    });

    test('an undated recipe sorts last, not first', () {
      // Not "just now" and not the epoch — simply unknown, which belongs at
      // the end rather than at either extreme.
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'undated', title: 'Aaa'),
        aRecipe(id: 'dated', title: 'Zzz', updatedAt: at(1)),
      ];

      expect(
        RecipeSearch.apply(library, RecipeFilter.none).map((Recipe r) => r.id),
        <String>['dated', 'undated'],
      );
    });

    test('favourites stay pinned above whatever the sort is', () {
      // Brendan's call: the sort orders each group, it does not get to bury
      // the handful of recipes actually cooked every week.
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'newest', title: 'Newest', updatedAt: at(9)),
        aRecipe(id: 'fav', title: 'Old favourite', updatedAt: at(1)),
      ];

      expect(
        RecipeSearch.apply(
          library,
          RecipeFilter.none,
          contextOf: (Recipe r) => RecipeContext(isFavorite: r.id == 'fav'),
        ).map((Recipe r) => r.id),
        <String>['fav', 'newest'],
      );
    });

    test('A–Z ignores the timestamps entirely', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'z', title: 'Ziti', updatedAt: at(9)),
        aRecipe(id: 'a', title: 'Aubergine', updatedAt: at(1)),
      ];

      expect(
        RecipeSearch.apply(
          library,
          const RecipeFilter(sort: RecipeSort.nameAsc),
        ).map((Recipe r) => r.id),
        <String>['a', 'z'],
      );
    });

    test('calories sorts low to high, with unknowns last', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'high', title: 'High'),
        aRecipe(id: 'unknown', title: 'Unknown'),
        aRecipe(id: 'low', title: 'Low'),
      ];
      const Map<String, double?> kcal = <String, double?>{
        'high': 800,
        'low': 300,
        'unknown': null,
      };

      expect(
        RecipeSearch.apply(
          library,
          const RecipeFilter(sort: RecipeSort.caloriesAsc),
          contextOf: (Recipe r) => RecipeContext(
            perServing: kcal[r.id] == null ? null : Macros(kcal: kcal[r.id]!),
          ),
        ).map((Recipe r) => r.id),
        // An incomplete recipe has no calories — not the lowest in the
        // library, which is what sorting it as zero would have claimed.
        <String>['low', 'high', 'unknown'],
      );
    });

    test('protein sorts high to low, with unknowns last', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'lean', title: 'Lean'),
        aRecipe(id: 'unknown', title: 'Unknown'),
        aRecipe(id: 'protein', title: 'Protein'),
      ];
      const Map<String, double?> protein = <String, double?>{
        'lean': 8,
        'protein': 42,
        'unknown': null,
      };

      expect(
        RecipeSearch.apply(
          library,
          const RecipeFilter(sort: RecipeSort.proteinDesc),
          contextOf: (Recipe r) => RecipeContext(
            perServing: protein[r.id] == null
                ? null
                : Macros(kcal: 0, proteinG: protein[r.id]!),
          ),
        ).map((Recipe r) => r.id),
        <String>['protein', 'lean', 'unknown'],
      );
    });

    test('a tie on the sort falls back to title', () {
      final List<Recipe> library = <Recipe>[
        aRecipe(id: 'z', title: 'Ziti', updatedAt: at(1)),
        aRecipe(id: 'a', title: 'Aubergine', updatedAt: at(1)),
      ];

      expect(
        RecipeSearch.apply(library, RecipeFilter.none).map((Recipe r) => r.id),
        <String>['a', 'z'],
      );
    });

    test('the sort is not counted as an active filter', () {
      // It never hides anything, so a lit sort must not show up as "1 filter"
      // with a clear button offering to undo it.
      const RecipeFilter sorted = RecipeFilter(sort: RecipeSort.nameAsc);
      expect(sorted.activeCount, 0);
      expect(sorted.isEmpty, isTrue);
    });
  });
}
