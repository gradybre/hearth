import 'package:meta/meta.dart';

import '../models/macros.dart';
import '../models/recipe.dart';

/// Everything the filter needs to know about one recipe beyond the recipe
/// itself (spec §5.2).
///
/// Favourites are per-user and collections are household-shared, so neither
/// lives on [Recipe] — they are joined in at query time and handed here.
/// Macros are optional because a recipe whose ingredients aren't matched to
/// foods yet has none to filter on.
@immutable
class RecipeContext {
  const RecipeContext({
    this.isFavorite = false,
    this.collectionIds = const <String>{},
    this.perServing,
  });

  final bool isFavorite;
  final Set<String> collectionIds;
  final Macros? perServing;
}

/// The library's combinable filter chips (spec §5.2).
///
/// Dimensions combine with AND — "Italian" *and* "under 30 min" *and*
/// "favourites" narrows. Within one dimension the values are OR — picking two
/// tags widens to either. That is what a chip row does everywhere else, and
/// getting it backwards makes multi-select chips useless.
@immutable
class RecipeFilter {
  const RecipeFilter({
    this.text = '',
    this.favoritesOnly = false,
    this.tags = const <String>{},
    this.cuisines = const <String>{},
    this.collectionIds = const <String>{},
    this.maxTotalTime,
    this.maxKcalPerServing,
    this.minProteinPerServing,
  });

  final String text;
  final bool favoritesOnly;
  final Set<String> tags;
  final Set<String> cuisines;
  final Set<String> collectionIds;
  final Duration? maxTotalTime;
  final double? maxKcalPerServing;
  final double? minProteinPerServing;

  static const RecipeFilter none = RecipeFilter();

  bool get isEmpty =>
      text.trim().isEmpty &&
      !favoritesOnly &&
      tags.isEmpty &&
      cuisines.isEmpty &&
      collectionIds.isEmpty &&
      maxTotalTime == null &&
      maxKcalPerServing == null &&
      minProteinPerServing == null;

  /// How many chips are lit — for the "3 filters" badge and the clear button.
  int get activeCount =>
      (favoritesOnly ? 1 : 0) +
      tags.length +
      cuisines.length +
      collectionIds.length +
      (maxTotalTime == null ? 0 : 1) +
      (maxKcalPerServing == null ? 0 : 1) +
      (minProteinPerServing == null ? 0 : 1);

  RecipeFilter copyWith({
    String? text,
    bool? favoritesOnly,
    Set<String>? tags,
    Set<String>? cuisines,
    Set<String>? collectionIds,
    Duration? maxTotalTime,
    double? maxKcalPerServing,
    double? minProteinPerServing,
    bool clearMaxTotalTime = false,
    bool clearMaxKcal = false,
    bool clearMinProtein = false,
  }) => RecipeFilter(
    text: text ?? this.text,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    tags: tags ?? this.tags,
    cuisines: cuisines ?? this.cuisines,
    collectionIds: collectionIds ?? this.collectionIds,
    maxTotalTime: clearMaxTotalTime
        ? null
        : (maxTotalTime ?? this.maxTotalTime),
    maxKcalPerServing: clearMaxKcal
        ? null
        : (maxKcalPerServing ?? this.maxKcalPerServing),
    minProteinPerServing: clearMinProtein
        ? null
        : (minProteinPerServing ?? this.minProteinPerServing),
  );

  /// Flips one value of a multi-select dimension.
  RecipeFilter toggleTag(String tag) =>
      copyWith(tags: _toggle(tags, RecipeSearch.fold(tag)));

  RecipeFilter toggleCuisine(String cuisine) =>
      copyWith(cuisines: _toggle(cuisines, RecipeSearch.fold(cuisine)));

  RecipeFilter toggleCollection(String id) =>
      copyWith(collectionIds: _toggle(collectionIds, id));

  static Set<String> _toggle(Set<String> values, String value) =>
      values.contains(value)
      ? (<String>{...values}..remove(value))
      : <String>{...values, value};
}

/// Search and filter over the recipe library (spec §5.2).
///
/// Pure and synchronous: the library is a household's worth of recipes, not a
/// search index, so filtering in Dart keeps this testable without a database
/// and keeps offline behaving exactly like online.
abstract final class RecipeSearch {
  /// Normalises for comparison: case-folded, accents stripped, whitespace
  /// collapsed. Without accent folding "jalapeno" would not find "jalapeño",
  /// which is exactly the search a tired cook types.
  static String fold(String value) {
    final StringBuffer out = StringBuffer();
    for (final int rune in value.toLowerCase().runes) {
      out.write(_deaccent[rune] ?? String.fromCharCode(rune));
    }
    return out.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<int, String> _deaccent = <int, String>{
    0xE0: 'a',
    0xE1: 'a',
    0xE2: 'a',
    0xE3: 'a',
    0xE4: 'a',
    0xE5: 'a',
    0xE7: 'c',
    0xE8: 'e',
    0xE9: 'e',
    0xEA: 'e',
    0xEB: 'e',
    0xEC: 'i',
    0xED: 'i',
    0xEE: 'i',
    0xEF: 'i',
    0xF1: 'n',
    0xF2: 'o',
    0xF3: 'o',
    0xF4: 'o',
    0xF5: 'o',
    0xF6: 'o',
    0xF9: 'u',
    0xFA: 'u',
    0xFB: 'u',
    0xFC: 'u',
    0xFD: 'y',
    0xFF: 'y',
  };

  /// The text every search term is matched against.
  ///
  /// Ingredient names are included deliberately: "what can I do with fennel"
  /// is a real question the library should answer, and a title-only search
  /// cannot. Prep notes and step bodies are not — searching for "chopped"
  /// would return most of the library.
  static String haystack(Recipe recipe) => fold(
    <String>[
      recipe.title,
      ...recipe.tags,
      if (recipe.cuisine != null) recipe.cuisine!,
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        ingredient.name,
    ].join(' '),
  );

  /// True when every whitespace-separated term appears somewhere.
  ///
  /// Terms are ANDed so typing more narrows rather than widens — "chicken
  /// thai" should find the one Thai chicken dish, not every chicken recipe.
  static bool matchesText(Recipe recipe, String query) {
    final String needle = fold(query);
    if (needle.isEmpty) return true;
    final String hay = haystack(recipe);
    return needle.split(' ').every(hay.contains);
  }

  static bool matches(
    Recipe recipe,
    RecipeFilter filter, {
    RecipeContext context = const RecipeContext(),
  }) {
    if (recipe.isDeleted) return false;
    if (filter.favoritesOnly && !context.isFavorite) return false;
    if (!matchesText(recipe, filter.text)) return false;

    if (filter.tags.isNotEmpty) {
      final Set<String> tags = recipe.tags.map(fold).toSet();
      if (!filter.tags.any(tags.contains)) return false;
    }

    if (filter.cuisines.isNotEmpty) {
      final String? cuisine = recipe.cuisine == null
          ? null
          : fold(recipe.cuisine!);
      if (cuisine == null || !filter.cuisines.contains(cuisine)) return false;
    }

    if (filter.collectionIds.isNotEmpty &&
        !filter.collectionIds.any(context.collectionIds.contains)) {
      return false;
    }

    if (filter.maxTotalTime != null) {
      // A recipe with no times recorded is excluded from a time filter rather
      // than assumed quick: "under 30 minutes" must not hand back something
      // that turns out to be a four-hour braise.
      final Duration? total = recipe.totalTime;
      if (total == null || total > filter.maxTotalTime!) return false;
    }

    // Same reasoning for macros: unknown is not "passes".
    if (filter.maxKcalPerServing != null) {
      final Macros? macros = context.perServing;
      if (macros == null || macros.kcal > filter.maxKcalPerServing!) {
        return false;
      }
    }
    if (filter.minProteinPerServing != null) {
      final Macros? macros = context.perServing;
      if (macros == null || macros.proteinG < filter.minProteinPerServing!) {
        return false;
      }
    }

    return true;
  }

  /// Applies [filter] across the library, keeping favourites first.
  ///
  /// Ordering is favourites, then title. Sorting by title alone buries the
  /// handful of recipes actually cooked every week under an alphabet of ones
  /// tried once.
  static List<Recipe> apply(
    Iterable<Recipe> recipes,
    RecipeFilter filter, {
    RecipeContext Function(Recipe)? contextOf,
  }) {
    final List<Recipe> kept = <Recipe>[
      for (final Recipe recipe in recipes)
        if (matches(
          recipe,
          filter,
          context: contextOf?.call(recipe) ?? const RecipeContext(),
        ))
          recipe,
    ];

    kept.sort((Recipe a, Recipe b) {
      final bool aFav = contextOf?.call(a).isFavorite ?? false;
      final bool bFav = contextOf?.call(b).isFavorite ?? false;
      if (aFav != bFav) return aFav ? -1 : 1;
      return fold(a.title).compareTo(fold(b.title));
    });
    return kept;
  }

  /// Every tag in the library, folded and sorted — the tag chips on offer.
  static List<String> tagsIn(Iterable<Recipe> recipes) => _sortedFolded(
    recipes.where((Recipe r) => !r.isDeleted).expand((Recipe r) => r.tags),
  );

  static List<String> cuisinesIn(Iterable<Recipe> recipes) => _sortedFolded(
    recipes
        .where((Recipe r) => !r.isDeleted && r.cuisine != null)
        .map((Recipe r) => r.cuisine!),
  );

  static List<String> _sortedFolded(Iterable<String> values) {
    final Set<String> unique = <String>{
      for (final String value in values)
        if (fold(value).isNotEmpty) fold(value),
    };
    return unique.toList()..sort();
  }
}
