import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/preference_store.dart';
import '../../domain/models/food.dart';

/// Whose foods the library is showing (review §7.5).
///
/// A seeded chain is hundreds of rows. They arrive in the same list as the
/// twenty foods somebody actually eats, on the screen they open to log from,
/// and they bury it. So the list is scoped rather than mixed.
///
/// **A scope, not a filter.** The catalogue is never hidden — both scopes are
/// on screen at once and either is one tap away. That distinction is the whole
/// of §7.5: a filter that disappears a chain teaches people the menu is gone,
/// and the next thing they do is re-import it.
///
/// The split is on [FoodSource.restaurant] alone, and deliberately not on
/// `RestaurantMenu`'s stricter test, which also wants a brand. A restaurant
/// food with no brand belongs to no menu and the editor refuses to save one,
/// but any that predate that rule still have to be somewhere — and a scope
/// pair that between them showed less than the whole library would lose them.
enum FoodScope {
  /// The household's own: everything that did not come off a menu.
  yours('Your foods', 'yours'),

  restaurants('Restaurant menus', 'restaurants');

  const FoodScope(this.label, this.stored);

  /// What the switch shows.
  final String label;

  /// What goes in the preference row. A stable identifier rather than the
  /// label, which is copy and can be reworded.
  final String stored;

  /// An unrecognised or since-removed value falls back to your own foods —
  /// the same rule the launch target uses, and for the same reason: a stored
  /// value nobody can read must not leave the screen blank.
  static FoodScope parse(String? stored) {
    for (final FoodScope scope in FoodScope.values) {
      if (scope.stored == stored) return scope;
    }
    return FoodScope.yours;
  }

  bool contains(Food food) => switch (this) {
    FoodScope.yours => food.source != FoodSource.restaurant,
    FoodScope.restaurants => food.source == FoodSource.restaurant,
  };

  /// Which side of the switch [food] is on.
  ///
  /// The inverse of [contains], and the question a screen asks after a save:
  /// a food written while the other half is showing has not gone anywhere,
  /// but it is out of sight, which looks the same from the chair.
  static FoodScope of(Food food) => food.source == FoodSource.restaurant
      ? FoodScope.restaurants
      : FoodScope.yours;
}

/// [foods] narrowed to one scope, in the order they arrived.
List<Food> inScope(Iterable<Food> foods, FoodScope scope) => <Food>[
  for (final Food food in foods)
    if (scope.contains(food)) food,
];

/// Which scope the Foods screen is showing, remembered on this device.
///
/// Device-local like the theme and the launch target, and stored the same
/// way: whether you are looking at your own foods or at a chain's menu is a
/// property of the browsing you are doing right now, and pushing it to a
/// partner would rearrange their library for no reason they could see.
final AsyncNotifierProvider<FoodScopeNotifier, FoodScope> foodScopeProvider =
    AsyncNotifierProvider<FoodScopeNotifier, FoodScope>(FoodScopeNotifier.new);

class FoodScopeNotifier extends AsyncNotifier<FoodScope> {
  PreferenceStore get _store => ref.read(preferenceStoreProvider);

  @override
  FutureOr<FoodScope> build() =>
      _store.read(PreferenceStore.foodScope).then(FoodScope.parse);

  /// Switches scope, and rethrows if the change could not be stored.
  ///
  /// The list moves first — swapping what is on screen is the entire point of
  /// the tap and has no business waiting on sqlite — and is taken back if the
  /// write fails, so what is on screen and what the next visit will show stay
  /// the same thing.
  Future<void> choose(FoodScope scope) async {
    final FoodScope previous = state.value ?? FoodScope.yours;
    state = AsyncValue<FoodScope>.data(scope);
    try {
      await _store.write(PreferenceStore.foodScope, scope.stored);
    } on Object {
      state = AsyncValue<FoodScope>.data(previous);
      rethrow;
    }
  }
}

/// The scope as the screen should draw it right now.
///
/// While the stored answer is still being read this is your own foods, which
/// is also the default — so the common case never flashes.
final Provider<FoodScope> currentFoodScopeProvider = Provider<FoodScope>(
  (Ref ref) => ref.watch(foodScopeProvider).value ?? FoodScope.yours,
);

/// The whole library narrowed to the scope, before any filter chip.
///
/// This is what "is there anything here at all" means now: an empty-handed
/// household and one whose chips exclude everything are different states, and
/// so are a household with no foods and one with no menus.
final Provider<AsyncValue<List<Food>>> scopedLibraryProvider =
    Provider<AsyncValue<List<Food>>>((Ref ref) {
      final FoodScope scope = ref.watch(currentFoodScopeProvider);
      return ref
          .watch(foodLibraryProvider)
          .whenData((List<Food> foods) => inScope(foods, scope));
    });

/// The library as the Foods screen lists it: scoped, then filtered and sorted.
final Provider<AsyncValue<List<Food>>> scopedFoodsProvider =
    Provider<AsyncValue<List<Food>>>((Ref ref) {
      final FoodScope scope = ref.watch(currentFoodScopeProvider);
      return ref
          .watch(filteredFoodsProvider)
          .whenData((List<Food> foods) => inScope(foods, scope));
    });
