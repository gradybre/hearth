import 'package:meta/meta.dart';

import '../models/food.dart';
import '../text/text_normaliser.dart';

/// How the food library is ordered.
///
/// Deliberately shorter than the recipe list's: a food has no cook time, and
/// its calories belong to a serving rather than to the food, so sorting a
/// library of mixed servings by them would compare a teaspoon against a tin.
enum FoodSort {
  /// Most recently added or edited first — the default, because the food you
  /// want next is usually one you just scanned or corrected.
  recent('Recent'),

  nameAsc('A–Z');

  const FoodSort(this.label);

  /// What the sort control shows.
  final String label;
}

/// The food library's filter chips.
///
/// Same combining rule as the recipe library (spec §5.2): dimensions AND
/// together, values within a dimension OR together.
@immutable
class FoodFilter {
  const FoodFilter({
    this.text = '',
    this.sources = const <FoodSource>{},
    this.storeTags = const <String>{},
    this.needsAttention = false,
    this.hasBarcode = false,
    this.isDefault = false,
    this.sort = FoodSort.recent,
  });

  final String text;

  /// Where the numbers came from. Worth filtering on because it separates
  /// entries this household vouched for from a stranger's (spec §5.5).
  final Set<FoodSource> sources;

  final Set<String> storeTags;

  /// Only foods that cannot actually be logged — see [Food.needsAttention].
  final bool needsAttention;

  /// Only foods with a barcode: scanned packets, as against hand-entered
  /// generics like "white onion".
  final bool hasBarcode;

  /// Only the household's standing choices (spec §5.3).
  final bool isDefault;

  /// Ordering. Not a filter — it hides nothing — so it stays out of
  /// [activeCount] and survives a "clear filters".
  final FoodSort sort;

  static const FoodFilter none = FoodFilter();

  bool get isEmpty =>
      text.trim().isEmpty &&
      sources.isEmpty &&
      storeTags.isEmpty &&
      !needsAttention &&
      !hasBarcode &&
      !isDefault;

  int get activeCount =>
      sources.length +
      storeTags.length +
      (needsAttention ? 1 : 0) +
      (hasBarcode ? 1 : 0) +
      (isDefault ? 1 : 0);

  FoodFilter copyWith({
    String? text,
    Set<FoodSource>? sources,
    Set<String>? storeTags,
    bool? needsAttention,
    bool? hasBarcode,
    bool? isDefault,
    FoodSort? sort,
  }) => FoodFilter(
    text: text ?? this.text,
    sources: sources ?? this.sources,
    storeTags: storeTags ?? this.storeTags,
    needsAttention: needsAttention ?? this.needsAttention,
    hasBarcode: hasBarcode ?? this.hasBarcode,
    isDefault: isDefault ?? this.isDefault,
    sort: sort ?? this.sort,
  );

  FoodFilter toggleSource(FoodSource source) =>
      copyWith(sources: _toggle(sources, source));

  FoodFilter toggleStoreTag(String tag) =>
      copyWith(storeTags: _toggle(storeTags, normaliseKey(tag)));

  static Set<T> _toggle<T>(Set<T> values, T value) => values.contains(value)
      ? (<T>{...values}..remove(value))
      : <T>{...values, value};
}

/// Search, filter, and sort over the food library.
///
/// Pure and synchronous, for the same reason as [RecipeSearch]: a household's
/// library is small enough to filter in Dart, which makes it testable without
/// a database and makes offline behave exactly like online.
abstract final class FoodSearch {
  /// Whether a food survives the filter.
  static bool matches(Food food, FoodFilter filter) {
    if (food.isDeleted) return false;

    final String needle = normaliseKey(filter.text);
    if (needle.isNotEmpty) {
      // Both directions, as the ingredient picker does: an entry saved plainly
      // as "White onion" should still be found by someone typing more than
      // that, and vice versa.
      final String name = normaliseKey(food.name);
      final String brand = normaliseKey(food.brand ?? '');
      final bool hit =
          name.contains(needle) ||
          brand.contains(needle) ||
          needle.contains(name);
      if (!hit) return false;
    }

    if (filter.sources.isNotEmpty && !filter.sources.contains(food.source)) {
      return false;
    }

    if (filter.storeTags.isNotEmpty) {
      final String tag = normaliseKey(food.storeTag ?? '');
      if (tag.isEmpty || !filter.storeTags.contains(tag)) return false;
    }

    if (filter.needsAttention && !food.needsAttention) return false;
    if (filter.hasBarcode && (food.barcode ?? '').isEmpty) return false;
    if (filter.isDefault && !food.isDefault) return false;

    return true;
  }

  /// The library as the screen shows it.
  ///
  /// Name is always the final tiebreaker, so an ordering that cannot separate
  /// two foods — two undated ones, most obviously — still lands somewhere a
  /// person can predict.
  static List<Food> apply(Iterable<Food> foods, FoodFilter filter) {
    final List<Food> kept = <Food>[
      for (final Food food in foods)
        if (matches(food, filter)) food,
    ];

    kept.sort((Food a, Food b) {
      final int bySort = switch (filter.sort) {
        // Unknown sinks rather than sorting as "now": a food with no
        // timestamp has not just been saved.
        FoodSort.recent => switch ((a.updatedAt, b.updatedAt)) {
          (null, null) => 0,
          (null, _) => 1,
          (_, null) => -1,
          (final DateTime x, final DateTime y) => y.compareTo(x),
        },
        FoodSort.nameAsc => 0,
      };
      if (bySort != 0) return bySort;

      return normaliseKey(a.name).compareTo(normaliseKey(b.name));
    });
    return kept;
  }

  /// The store tags the library actually uses — the chips worth offering.
  ///
  /// Folded and de-duplicated, so "Costco" and "costco" are one chip.
  static List<String> storeTagsIn(Iterable<Food> foods) {
    final Set<String> tags = <String>{
      for (final Food food in foods)
        if (!food.isDeleted && normaliseKey(food.storeTag ?? '').isNotEmpty)
          normaliseKey(food.storeTag!),
    };
    return tags.toList()..sort();
  }

  /// The sources present in the library, in enum order so the chip row does
  /// not reshuffle itself as the library changes.
  static List<FoodSource> sourcesIn(Iterable<Food> foods) {
    final Set<FoodSource> present = <FoodSource>{
      for (final Food food in foods)
        if (!food.isDeleted) food.source,
    };
    return <FoodSource>[
      for (final FoodSource source in FoodSource.values)
        if (present.contains(source)) source,
    ];
  }
}
