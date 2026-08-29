import '../../domain/models/food.dart';
import '../../domain/text/text_normaliser.dart';
import '../local/food_store.dart';
import 'nutrition_source.dart';

/// The first link in the lookup chain: what this household already knows
/// (spec §5.5).
///
/// Asked before any external source, and for two reasons. It is the only
/// source that works with no signal, and a food the household has already
/// corrected must never be silently replaced by a stranger's version of it —
/// "user overrides win" is the whole point of keeping a personal library.
class LibraryNutritionSource implements NutritionSource {
  LibraryNutritionSource({
    required FoodStore store,
    required String householdId,
  }) : _store = store,
       _householdId = householdId;

  final FoodStore _store;
  final String _householdId;

  @override
  String get displayName => 'Your library';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    final String wanted = barcode.trim();
    if (wanted.isEmpty) return null;

    for (final Food food in await _store.all(householdId: _householdId)) {
      if (food.barcode == wanted) {
        // Certain: this household attached this barcode to this food.
        //
        // [NutritionMatch.source] stays the food's provenance — where the
        // numbers originally came from — so `fromLibrary` is what says the
        // household already has this. Without it a food saved from Open Food
        // Facts is indistinguishable from one fetched a moment ago, and the
        // screen offers to save a second copy of it.
        return NutritionMatch(
          food: food,
          source: food.source,
          confidence: 1,
          fromLibrary: true,
        );
      }
    }
    return null;
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    final String needle = normaliseKey(query);
    if (needle.isEmpty) return const <NutritionMatch>[];

    final List<Food> foods = await _store.all(householdId: _householdId);
    final List<({Food food, int rank})> hits = <({Food food, int rank})>[];

    for (final Food food in foods) {
      final String name = normaliseKey(food.name);
      final String brand = normaliseKey(food.brand ?? '');
      // Ranked, not merely filtered: something you type the start of is
      // almost always what you meant, and burying it under an alphabetical
      // list is the tax logging speed cannot afford.
      if (name.startsWith(needle)) {
        hits.add((food: food, rank: 0));
      } else if (name.contains(needle)) {
        hits.add((food: food, rank: 1));
      } else if (brand.contains(needle)) {
        hits.add((food: food, rank: 2));
      }
    }

    hits.sort((({Food food, int rank}) a, ({Food food, int rank}) b) {
      if (a.rank != b.rank) return a.rank.compareTo(b.rank);
      return normaliseKey(a.food.name).compareTo(normaliseKey(b.food.name));
    });

    return <NutritionMatch>[
      for (final ({Food food, int rank}) hit in hits.take(limit))
        NutritionMatch(
          food: hit.food,
          source: hit.food.source,
          confidence: 1,
          fromLibrary: true,
        ),
    ];
  }
}
