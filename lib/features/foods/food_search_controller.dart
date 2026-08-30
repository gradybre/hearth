import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/nutrition_source.dart';

/// What the search of the outside world is doing (spec §5.5).
@immutable
sealed class FoodSearchState {
  const FoodSearchState();
}

/// Nothing asked for yet, or the query is too short to be worth a round trip.
class FoodSearchIdle extends FoodSearchState {
  const FoodSearchIdle();
}

class FoodSearchRunning extends FoodSearchState {
  const FoodSearchRunning(this.query);
  final String query;
}

class FoodSearchResults extends FoodSearchState {
  const FoodSearchResults(this.query, this.matches, {required this.hasMore});
  final String query;
  final List<NutritionMatch> matches;

  /// Whether asking again with a larger limit is likely to turn up more.
  ///
  /// True only when the last fetch came back *full* — the sources had at
  /// least that many to give — and the page size has not already hit its
  /// cap. A fetch that came back short means the sources are genuinely
  /// exhausted, not merely paged; asking again would just repeat itself.
  final bool hasMore;
}

/// Searching foods beyond the household's own library (spec §5.5).
///
/// Deliberately separate from the local list rather than merged into it. The
/// library is already in memory and filters as fast as the user types; making
/// that wait on a network call would tax every search to serve the minority
/// that need one, and logging speed is the bar this app is judged against.
///
/// Results the household already owns are dropped: [NutritionLookup.search]
/// asks the library first and collapses duplicates by barcode, so anything
/// still marked [NutritionMatch.fromLibrary] is a food the caller is already
/// showing above.
class FoodSearchController extends Notifier<FoodSearchState> {
  @override
  FoodSearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const FoodSearchIdle();
  }

  Timer? _debounce;

  /// The query whose answer is still wanted, so a slow earlier search cannot
  /// overwrite the results of a later one.
  String? _last;

  /// Below this, a search matches half the shelf and costs a round trip to say
  /// so.
  static const int minimumQueryLength = 3;

  static const Duration _typingPause = Duration(milliseconds: 350);

  /// How many results a search asks for. Grows with [loadMore] rather than
  /// paging by offset — the sources here are re-asked from scratch each time
  /// rather than given a cursor, so "more" means "a bigger page," which is
  /// simple and, for how often anyone taps it, cheap enough.
  static const int _pageSize = 20;

  /// Past this many, a bigger page stops being worth another round trip:
  /// external results this far down a relevance ranking are rarely what
  /// anyone is looking for.
  static const int _maxLimit = 60;

  int _limit = _pageSize;

  void search(String raw) {
    final String query = raw.trim();
    _debounce?.cancel();
    _limit = _pageSize;

    if (query.length < minimumQueryLength) {
      _last = null;
      state = const FoodSearchIdle();
      return;
    }

    // Waits for a pause in typing: firing per keystroke would send "c", "ch",
    // "chi"… and every one of those is a request someone pays for.
    _debounce = Timer(_typingPause, () => _run(query));
  }

  /// Asks the same query again with a bigger page. Not debounced — this is a
  /// deliberate tap, not a keystroke to wait out.
  Future<void> loadMore() async {
    final FoodSearchState current = state;
    if (current is! FoodSearchResults || !current.hasMore) return;

    _limit = (_limit + _pageSize).clamp(_pageSize, _maxLimit);
    await _run(current.query);
  }

  Future<void> _run(String query) async {
    _last = query;
    state = FoodSearchRunning(query);

    final List<NutritionMatch> found = await ref
        .read(nutritionLookupProvider)
        .search(query, limit: _limit);

    if (_last != query) return;

    state = FoodSearchResults(query, <NutritionMatch>[
      for (final NutritionMatch match in found)
        if (!match.fromLibrary) match,
    ], hasMore: found.length >= _limit && _limit < _maxLimit);
  }

  void clear() {
    _debounce?.cancel();
    _last = null;
    _limit = _pageSize;
    state = const FoodSearchIdle();
  }
}

final NotifierProvider<FoodSearchController, FoodSearchState>
foodSearchProvider = NotifierProvider<FoodSearchController, FoodSearchState>(
  FoodSearchController.new,
);
