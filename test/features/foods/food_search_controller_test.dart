import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/features/foods/food_search_controller.dart';

import '../../support/fixtures.dart';

/// A source with a controllable number of results, so the page-size and
/// "hasMore" boundary can be tested without a real network.
class _FakeSource implements NutritionSource {
  _FakeSource(this.totalAvailable);

  final int totalAvailable;

  final List<int> limitsAsked = <int>[];

  @override
  String get displayName => 'Fake';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => null;

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    limitsAsked.add(limit);
    final int count = totalAvailable < limit ? totalAvailable : limit;
    return <NutritionMatch>[
      // The query itself is baked into every name so NutritionLookup's own
      // relevance filter never strips these out regardless of what was
      // asked — this test is about paging, not about relevance scoring.
      for (int i = 0; i < count; i++)
        NutritionMatch(
          food: aFood('$query $i'),
          source: FoodSource.openFoodFacts,
          confidence: 1,
        ),
    ];
  }
}

ProviderContainer containerWith(int totalAvailable) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      nutritionLookupProvider.overrideWithValue(
        NutritionLookup(<NutritionSource>[_FakeSource(totalAvailable)]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<FoodSearchState> runSearch(
  ProviderContainer container,
  String query,
) async {
  container.read(foodSearchProvider.notifier).search(query);
  // Past the controller's own debounce.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return container.read(foodSearchProvider);
}

void main() {
  group('paging', () {
    test('a full page offers more; a short one does not', () async {
      final ProviderContainer full = containerWith(20);
      final FoodSearchState fullState = await runSearch(full, 'ground beef');
      expect(fullState, isA<FoodSearchResults>());
      expect((fullState as FoodSearchResults).hasMore, isTrue);

      final ProviderContainer short = containerWith(5);
      final FoodSearchState shortState = await runSearch(short, 'ground beef');
      expect((shortState as FoodSearchResults).matches, hasLength(5));
      expect(shortState.hasMore, isFalse);
    });

    test(
      'loadMore asks again with a bigger page and grows the results',
      () async {
        final ProviderContainer container = containerWith(45);
        final FoodSearchState first = await runSearch(container, 'ground beef');
        expect((first as FoodSearchResults).matches, hasLength(20));

        await container.read(foodSearchProvider.notifier).loadMore();

        final FoodSearchState second = container.read(foodSearchProvider);
        expect((second as FoodSearchResults).matches, hasLength(40));
        // Still full at 40 of 45 available, so there's still more to offer.
        expect(second.hasMore, isTrue);
      },
    );

    test('loadMore stops offering once the source runs out', () async {
      final ProviderContainer container = containerWith(25);
      await runSearch(container, 'ground beef');

      await container.read(foodSearchProvider.notifier).loadMore();

      final FoodSearchState state = container.read(foodSearchProvider);
      // 25 available, asked for 40 — the source came back short.
      expect((state as FoodSearchResults).matches, hasLength(25));
      expect(state.hasMore, isFalse);
    });

    test('a fresh search resets the page size', () async {
      final ProviderContainer container = containerWith(45);
      await runSearch(container, 'ground beef');
      await container.read(foodSearchProvider.notifier).loadMore();
      expect(
        (container.read(foodSearchProvider) as FoodSearchResults).matches,
        hasLength(40),
      );

      final FoodSearchState fresh = await runSearch(
        container,
        'chicken breast',
      );
      expect((fresh as FoodSearchResults).matches, hasLength(20));
    });
  });
}
