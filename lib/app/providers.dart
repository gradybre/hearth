import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/adapters/data_export.dart';
import '../data/adapters/edge_function_label_reader.dart';
import '../data/adapters/edge_function_menu_reader.dart';
import '../data/adapters/edge_function_recipe_ai.dart';
import '../data/adapters/edge_function_recipe_icon.dart';
import '../data/adapters/edge_function_shopping_assistant.dart';
import '../data/adapters/image_picker_photos.dart';
import '../data/adapters/kitchen_devices.dart';
import '../data/adapters/label_reader.dart';
import '../data/adapters/library_nutrition_source.dart';
import '../data/adapters/menu_reader.dart';
import '../data/adapters/nutrition_lookup.dart';
import '../data/adapters/nutrition_source.dart';
import '../data/adapters/open_food_facts_source.dart';
import '../data/adapters/pdf_pages.dart';
import '../data/adapters/pdfx_pages.dart';
import '../data/adapters/photo_picker.dart';
import '../data/adapters/platform_kitchen_devices.dart';
import '../data/adapters/platform_shared_content.dart';
import '../data/adapters/recipe_ai.dart';
import '../data/adapters/recipe_icon.dart';
import '../data/adapters/share_plus_file_share.dart';
import '../data/adapters/shared_content.dart';
import '../data/adapters/shopping_assistant.dart';
import '../data/adapters/usda_nutrition_source.dart';
import '../data/auth/account_cache.dart';
import '../data/auth/auth_gateway.dart';
import '../data/auth/local_auth_gateway.dart';
import '../data/auth/supabase_auth_gateway.dart';
import '../data/local/collection_store.dart';
import '../data/local/cook_session_store.dart';
import '../data/local/cook_timer_store.dart';
import '../data/local/food_profile_store.dart';
import '../data/local/food_store.dart';
import '../data/local/hearth_database.dart';
import '../data/local/ingredient_match_store.dart';
import '../data/local/pending_write_store.dart';
import '../data/local/plan_store.dart';
import '../data/local/preference_store.dart';
import '../data/local/recipe_photo_store.dart';
import '../data/local/recipe_store.dart';
import '../data/local/shopping_store.dart';
import '../data/remote/photo_storage.dart';
import '../data/remote/remote_gateway.dart';
import '../data/remote/supabase_photo_storage.dart';
import '../data/remote/supabase_remote_gateway.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/food_profile_repository.dart';
import '../data/repositories/food_repository.dart';
import '../data/repositories/ingredient_match_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../data/repositories/shopping_repository.dart';
import '../data/sync/library_sync.dart';
import '../data/sync/photo_sync.dart';
import '../data/sync/record_sync.dart';
import '../data/sync/remote_rows.dart';
import '../data/sync/sync_engine.dart';
import '../domain/cooking/cook_session.dart';
import '../domain/foods/food_query.dart';
import '../domain/foods/no_match_rule.dart';
import '../domain/models/food.dart';
import '../domain/models/food_profile.dart';
import '../domain/models/macros.dart';
import '../domain/models/recipe.dart';
import '../domain/planning/day_progress.dart';
import '../domain/planning/meal_plan.dart';
import '../domain/planning/recent_log.dart';
import '../domain/planning/week.dart';
import '../domain/planning/week_template.dart';
import '../domain/recipes/ingredient_matcher.dart';
import '../domain/recipes/macro_calculator.dart';
import '../domain/recipes/recipe_query.dart';
import 'cook_timers.dart';
import 'sync_controller.dart';
import 'theme/theme_choice.dart';

/// The app's object graph.
///
/// Features read repositories from here and never touch Drift or Supabase
/// directly (CLAUDE.md layering rule). Tests override the leaves — the
/// database and the household — and get the real wiring above them.

/// The local cache. Overridden in tests with an in-memory database.
final Provider<HearthDatabase> databaseProvider = Provider<HearthDatabase>((
  Ref ref,
) {
  final HearthDatabase db = HearthDatabase();
  ref.onDispose(db.close);
  return db;
});

final Provider<RecipeStore> recipeStoreProvider = Provider<RecipeStore>(
  (Ref ref) => RecipeStore(ref.watch(databaseProvider)),
);

final Provider<PendingWriteStore> pendingWriteStoreProvider =
    Provider<PendingWriteStore>(
      (Ref ref) => PendingWriteStore(ref.watch(databaseProvider)),
    );

/// The household whose library is on screen.
///
/// Comes from the signed-in account. Falls back to the fixed local id while
/// the account is still loading and in unconfigured builds — the same id the
/// app used before accounts existed, so a device used offline keeps its
/// library when it first signs in.
final Provider<String> currentHouseholdIdProvider = Provider<String>(
  (Ref ref) =>
      ref.watch(accountProvider).value?.householdId ??
      LocalAuthGateway.account.householdId,
);

final Provider<RecipeRepository> recipeRepositoryProvider =
    Provider<RecipeRepository>(
      (Ref ref) => RecipeRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(recipeStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        householdId: ref.watch(currentHouseholdIdProvider),
      ),
    );

/// The household's recipes, re-emitted whenever the local cache changes.
final StreamProvider<List<Recipe>> recipeLibraryProvider =
    StreamProvider<List<Recipe>>(
      (Ref ref) => ref.watch(recipeRepositoryProvider).watchAll(),
    );

/// One recipe by id, including soft-deleted ones so a past log still resolves.
// Type left to inference: Riverpod's family provider type names are internal
// and have moved between majors.
final recipeByIdProvider = FutureProvider.family<Recipe?, String>((
  Ref ref,
  String id,
) async {
  // Re-read when the library changes so an edit shows up here too.
  ref.watch(recipeLibraryProvider);
  return ref.watch(recipeRepositoryProvider).byId(id);
});

final Provider<FoodStore> foodStoreProvider = Provider<FoodStore>(
  (Ref ref) => FoodStore(ref.watch(databaseProvider)),
);

final Provider<FoodProfileStore> foodProfileStoreProvider =
    Provider<FoodProfileStore>(
      (Ref ref) => FoodProfileStore(ref.watch(databaseProvider)),
    );

final Provider<FoodProfileRepository> foodProfileRepositoryProvider =
    Provider<FoodProfileRepository>(
      (Ref ref) => FoodProfileRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(foodProfileStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        userId: ref.watch(currentUserIdProvider),
      ),
    );

/// The user's own food profile, never null (spec §5.8 makes it skippable).
final StreamProvider<FoodProfile> foodProfileProvider =
    StreamProvider<FoodProfile>(
      (Ref ref) => ref.watch(foodProfileRepositoryProvider).watchMine(),
    );

final Provider<FoodRepository> foodRepositoryProvider =
    Provider<FoodRepository>(
      (Ref ref) => FoodRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(foodStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        householdId: ref.watch(currentHouseholdIdProvider),
      ),
    );

/// The household's foods plus the global catalogue, re-emitted on any local
/// change.
final StreamProvider<List<Food>> foodLibraryProvider =
    StreamProvider<List<Food>>(
      (Ref ref) => ref.watch(foodRepositoryProvider).watchAll(),
    );

/// One food by id, including soft-deleted ones so a past log still resolves.
final foodByIdProvider = FutureProvider.family<Food?, String>((
  Ref ref,
  String id,
) async {
  ref.watch(foodLibraryProvider);
  return ref.watch(foodRepositoryProvider).byId(id);
});

final Provider<IngredientMatchStore> ingredientMatchStoreProvider =
    Provider<IngredientMatchStore>(
      (Ref ref) => IngredientMatchStore(ref.watch(databaseProvider)),
    );

/// Remembered ingredient answers, queued for the household (spec §5.3, §7.1).
///
/// The store writes locally; this is what makes the answer reach the other
/// phone. Everything that records one goes through here — a correction made
/// on one device is a correction made for the kitchen, not for a handset.
final Provider<IngredientMatchRepository> ingredientMatchRepositoryProvider =
    Provider<IngredientMatchRepository>(
      (Ref ref) => IngredientMatchRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(ingredientMatchStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        householdId: ref.watch(currentHouseholdIdProvider),
      ),
    );

/// Every remembered ingredient-string to food mapping for this household,
/// keyed by normalised string (spec §5.3).
final FutureProvider<Map<String, String>> rememberedMatchesProvider =
    FutureProvider<Map<String, String>>((Ref ref) {
      // Re-read when the food library changes, so a deleted food stops being
      // suggested.
      ref.watch(foodLibraryProvider);
      return ref.watch(ingredientMatchRepositoryProvider).allFor();
    });

/// What this household says needs no food at all — salt, pepper, a spice
/// (spec §5.3).
///
/// Combines its own rows with the seasonings Hearth ships knowing about, and
/// with the ones it has disagreed with. Nothing is written into anybody's data
/// to make the built-ins work; a row only appears when somebody says something.
final FutureProvider<NoMatchRules> noMatchRulesProvider =
    FutureProvider<NoMatchRules>(
      (Ref ref) => ref.watch(ingredientMatchRepositoryProvider).noMatchRules(),
    );

/// The food most often matched to each ingredient name, across every recipe
/// in the library (spec §5.3's "previously-used" tier, applied household-wide
/// rather than within one recipe — see [IngredientMatcher.mostUsedByName]).
final Provider<Map<String, String>> mostUsedFoodsProvider =
    Provider<Map<String, String>>((Ref ref) {
      final List<Recipe> recipes =
          ref.watch(recipeLibraryProvider).value ?? const <Recipe>[];
      return IngredientMatcher.mostUsedByName(<(String, String?)>[
        for (final Recipe recipe in recipes)
          for (final RecipeIngredient ingredient in recipe.allIngredients)
            (ingredient.name, ingredient.foodId),
      ]);
    });

/// The person whose plan and logs are on screen.
///
/// Plans, logs, and targets are user-scoped, not household-scoped: two people
/// share a library but never a diary (spec §4). Auth fills this in; until then
/// it is a fixed local id.
/// The signed-in user. User-scoped data — plans, logs, targets, favourites —
/// hangs off this (spec §8.2).
final Provider<String> currentUserIdProvider = Provider<String>(
  (Ref ref) =>
      ref.watch(accountProvider).value?.userId ??
      LocalAuthGateway.account.userId,
);

final Provider<PlanStore> planStoreProvider = Provider<PlanStore>(
  (Ref ref) => PlanStore(ref.watch(databaseProvider)),
);

final Provider<PlanRepository> planRepositoryProvider =
    Provider<PlanRepository>(
      (Ref ref) => PlanRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(planStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        userId: ref.watch(currentUserIdProvider),
      ),
    );

/// The day the planner is showing. Defaults to today.
final NotifierProvider<SelectedDate, DateTime> selectedDateProvider =
    NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() => dayKey(DateTime.now());

  void select(DateTime date) => state = dayKey(date);

  void shiftDays(int days) =>
      state = DateTime(state.year, state.month, state.day + days);

  void today() => state = dayKey(DateTime.now());
}

/// Emits whenever the local plan changes, so day and week views refresh.
final StreamProvider<void> planChangesProvider = StreamProvider<void>(
  (Ref ref) => ref.watch(planRepositoryProvider).watchChanges(),
);

/// The entries on the selected day.
/// The weeks worth having again (spec §5.6).
///
/// A future that gets invalidated, not a live stream — the same shape as
/// [dayEntriesProvider]. A sqlite subscription cannot be driven by the fake
/// async a widget test runs on, so it stays open at teardown and hangs the
/// whole run; and templates change only when somebody saves or forgets one,
/// which is exactly when an invalidate is easy to write.
final FutureProvider<List<WeekTemplate>> weekTemplatesProvider =
    FutureProvider<List<WeekTemplate>>(
      (Ref ref) => ref.watch(planRepositoryProvider).templates(),
    );

final FutureProvider<List<MealPlanEntry>> dayEntriesProvider =
    FutureProvider<List<MealPlanEntry>>((Ref ref) {
      ref.watch(planChangesProvider);
      return ref
          .watch(planRepositoryProvider)
          .entriesFor(ref.watch(selectedDateProvider));
    });

/// The macro targets covering the selected day's week, or null when unset.
final FutureProvider<MacroTargets?> dayTargetsProvider =
    FutureProvider<MacroTargets?>((Ref ref) {
      ref.watch(planChangesProvider);
      return ref
          .watch(planRepositoryProvider)
          .targetsFor(ref.watch(selectedDateProvider));
    });

// ── Shopping (spec §5.7) ─────────────────────────────────────────────────────

final Provider<ShoppingRepository> shoppingRepositoryProvider =
    Provider<ShoppingRepository>(
      (Ref ref) => ShoppingRepository(
        database: ref.watch(databaseProvider),
        store: ShoppingStore(ref.watch(databaseProvider)),
        queue: PendingWriteStore(ref.watch(databaseProvider)),
        householdId: ref.watch(currentHouseholdIdProvider),
      ),
    );

/// The range the list currently covers.
///
/// Adjustable, and deliberately not a week: the shop happens on a Friday for a
/// stretch covering the weekend and the week after (spec §5.7).
class ShoppingRange extends Notifier<({DateTime from, DateTime to})> {
  @override
  ({DateTime from, DateTime to}) build() =>
      ref.watch(shoppingRepositoryProvider).defaultRange();

  void set({DateTime? from, DateTime? to}) {
    final DateTime start = from ?? state.from;
    final DateTime end = to ?? state.to;
    // A range that ends before it starts is a mis-tap, not an instruction.
    state = end.isBefore(start)
        ? (from: start, to: start)
        : (from: start, to: end);
  }
}

final NotifierProvider<ShoppingRange, ({DateTime from, DateTime to})>
shoppingRangeProvider =
    NotifierProvider<ShoppingRange, ({DateTime from, DateTime to})>(
      ShoppingRange.new,
    );

/// Whether spices are pulled from recipes. Off by default (spec §5.7).
final NotifierProvider<ShoppingSeasonings, bool> shoppingSeasoningsProvider =
    NotifierProvider<ShoppingSeasonings, bool>(ShoppingSeasonings.new);

class ShoppingSeasonings extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Editing the list by asking (spec §5.7).
///
/// Nullable for the same reason as the other AI surfaces: the key lives in an
/// Edge Function, so an unconfigured build has no way to, and the panel hides
/// itself rather than failing on send.
final Provider<ShoppingAssistant?> shoppingAssistantProvider =
    Provider<ShoppingAssistant?>(
      (Ref ref) => ref.watch(supabaseReadyProvider)
          ? EdgeFunctionShoppingAssistant(Supabase.instance.client)
          : null,
    );

final StreamProvider<void> shoppingChangesProvider = StreamProvider<void>(
  (Ref ref) => ref.watch(shoppingRepositoryProvider).watchChanges(),
);

/// The list as it stands, or null when none has been built.
final FutureProvider<ShoppingListSnapshot?> shoppingListProvider =
    FutureProvider<ShoppingListSnapshot?>((Ref ref) {
      ref.watch(shoppingChangesProvider);
      return ref.watch(shoppingRepositoryProvider).current();
    });

/// The plan across the shopping range, which is what the list is built from.
final FutureProvider<Map<DateTime, List<MealPlanEntry>>> shoppingPlanProvider =
    FutureProvider<Map<DateTime, List<MealPlanEntry>>>((Ref ref) {
      ref.watch(planChangesProvider);
      final ({DateTime from, DateTime to}) range = ref.watch(
        shoppingRangeProvider,
      );
      return ref
          .watch(planRepositoryProvider)
          .entriesBetween(range.from, range.to);
    });

/// Things logged recently, for one-tap repeat (spec §5.6).
final FutureProvider<List<RecentLog>> recentLogsProvider =
    FutureProvider<List<RecentLog>>((Ref ref) {
      ref.watch(planChangesProvider);
      return ref.watch(planRepositoryProvider).recentLogs();
    });

/// Which planner view is showing: the day, or the week summary.
///
/// The day is the default because daily logging is the loop the app is judged
/// on; the week is where you step back and look.
enum PlanView { day, week }

final NotifierProvider<PlanViewMode, PlanView> planViewProvider =
    NotifierProvider<PlanViewMode, PlanView>(PlanViewMode.new);

class PlanViewMode extends Notifier<PlanView> {
  @override
  PlanView build() => PlanView.day;

  void show(PlanView view) => state = view;
}

/// Every entry in the selected day's week, keyed by day.
final FutureProvider<Map<DateTime, List<MealPlanEntry>>> weekEntriesProvider =
    FutureProvider<Map<DateTime, List<MealPlanEntry>>>((Ref ref) {
      ref.watch(planChangesProvider);
      final List<DateTime> days = weekOf(ref.watch(selectedDateProvider));
      return ref
          .watch(planRepositoryProvider)
          .entriesBetween(days.first, days.last);
    });

// ── Favourites and collections (spec §5.2) ───────────────────────────────────

final Provider<CollectionStore> collectionStoreProvider =
    Provider<CollectionStore>(
      (Ref ref) => CollectionStore(ref.watch(databaseProvider)),
    );

final Provider<CollectionRepository> collectionRepositoryProvider =
    Provider<CollectionRepository>(
      (Ref ref) => CollectionRepository(
        database: ref.watch(databaseProvider),
        store: ref.watch(collectionStoreProvider),
        queue: ref.watch(pendingWriteStoreProvider),
        householdId: ref.watch(currentHouseholdIdProvider),
        userId: ref.watch(currentUserIdProvider),
      ),
    );

/// The recipes this user has hearted. Personal — never the household's.
final StreamProvider<Set<String>> favoriteRecipeIdsProvider =
    StreamProvider<Set<String>>(
      (Ref ref) => ref.watch(collectionRepositoryProvider).watchFavoriteIds(),
    );

/// The household's cookbooks, each with the recipes in it.
final StreamProvider<List<CollectionSummary>> collectionsProvider =
    StreamProvider<List<CollectionSummary>>(
      (Ref ref) => ref.watch(collectionRepositoryProvider).watchCollections(),
    );

/// Which collections each recipe belongs to, for filtering in one pass.
final StreamProvider<Map<String, Set<String>>> recipeCollectionsProvider =
    StreamProvider<Map<String, Set<String>>>(
      (Ref ref) => ref.watch(collectionRepositoryProvider).watchMembership(),
    );

/// The food library's search text, filter chips, and sort.
///
/// A provider for the same reason as the recipe one below: opening a food and
/// coming back should not silently reset what you were looking at.
final NotifierProvider<FoodFilterController, FoodFilter> foodFilterProvider =
    NotifierProvider<FoodFilterController, FoodFilter>(
      FoodFilterController.new,
    );

class FoodFilterController extends Notifier<FoodFilter> {
  @override
  FoodFilter build() => FoodFilter.none;

  void search(String text) => state = state.copyWith(text: text);
  void toggleSource(FoodSource source) => state = state.toggleSource(source);
  void toggleStoreTag(String tag) => state = state.toggleStoreTag(tag);
  void toggleNeedsAttention() =>
      state = state.copyWith(needsAttention: !state.needsAttention);
  void toggleHasBarcode() =>
      state = state.copyWith(hasBarcode: !state.hasBarcode);
  void toggleDefaults() => state = state.copyWith(isDefault: !state.isDefault);
  void setSort(FoodSort sort) => state = state.copyWith(sort: sort);

  /// Keeps the typed text and the sort, for the same reasons as the recipe
  /// library: the search box is a separate control, and the sort hides
  /// nothing so clearing filters must not reorder the list.
  void clearChips() => state = FoodFilter(text: state.text, sort: state.sort);
}

/// The food library as the screen shows it: filtered and sorted.
final Provider<AsyncValue<List<Food>>> filteredFoodsProvider =
    Provider<AsyncValue<List<Food>>>((Ref ref) {
      final AsyncValue<List<Food>> library = ref.watch(foodLibraryProvider);
      final FoodFilter filter = ref.watch(foodFilterProvider);
      return library.whenData(
        (List<Food> foods) => FoodSearch.apply(foods, filter),
      );
    });

/// The library's live search text and filter chips.
///
/// Held in a provider rather than the screen's state so it survives navigating
/// into a recipe and back — losing your filters every time you look at
/// something is the kind of small tax that stops a library being browsed.
final NotifierProvider<RecipeFilterController, RecipeFilter>
recipeFilterProvider = NotifierProvider<RecipeFilterController, RecipeFilter>(
  RecipeFilterController.new,
);

class RecipeFilterController extends Notifier<RecipeFilter> {
  @override
  RecipeFilter build() => RecipeFilter.none;

  void search(String text) => state = state.copyWith(text: text);
  void toggleFavoritesOnly() =>
      state = state.copyWith(favoritesOnly: !state.favoritesOnly);
  void toggleEatenOutOnly() =>
      state = state.copyWith(eatenOutOnly: !state.eatenOutOnly);
  void toggleTag(String tag) => state = state.toggleTag(tag);
  void toggleCuisine(String cuisine) => state = state.toggleCuisine(cuisine);
  void toggleCollection(String id) => state = state.toggleCollection(id);

  /// Null clears the chip — it is a single-choice dimension, so choosing the
  /// lit value again turns it off.
  void setMaxTotalTime(Duration? value) => state = value == null
      ? state.copyWith(clearMaxTotalTime: true)
      : state.copyWith(maxTotalTime: value);

  void setMaxKcal(double? value) => state = value == null
      ? state.copyWith(clearMaxKcal: true)
      : state.copyWith(maxKcalPerServing: value);

  void setMinProtein(double? value) => state = value == null
      ? state.copyWith(clearMinProtein: true)
      : state.copyWith(minProteinPerServing: value);

  void setSort(RecipeSort sort) => state = state.copyWith(sort: sort);

  /// Clears the chips but keeps what was typed — they are separate controls,
  /// and wiping the search box out from under the cursor is startling.
  ///
  /// The sort is kept for the same reason: it hides nothing, so clearing
  /// filters has no business reordering the list under the user.
  void clearChips() => state = RecipeFilter(text: state.text, sort: state.sort);

  void clearAll() => state = RecipeFilter(sort: state.sort);
}

/// The library as the screen shows it: filtered, and favourites first.
final Provider<AsyncValue<List<Recipe>>> filteredRecipesProvider =
    Provider<AsyncValue<List<Recipe>>>((Ref ref) {
      final AsyncValue<List<Recipe>> library = ref.watch(recipeLibraryProvider);
      final RecipeFilter filter = ref.watch(recipeFilterProvider);
      final Set<String> favorites =
          ref.watch(favoriteRecipeIdsProvider).value ?? const <String>{};
      final Map<String, Set<String>> membership =
          ref.watch(recipeCollectionsProvider).value ??
          const <String, Set<String>>{};
      final Map<String, Food> foods = <String, Food>{
        for (final Food food
            in ref.watch(foodLibraryProvider).value ?? <Food>[])
          food.id: food,
      };

      return library.whenData(
        (List<Recipe> recipes) => RecipeSearch.apply(
          recipes,
          filter,
          contextOf: (Recipe recipe) => RecipeContext(
            isFavorite: favorites.contains(recipe.id),
            collectionIds: membership[recipe.id] ?? const <String>{},
            perServing: _perServingIfComplete(recipe, foods),
          ),
        ),
      );
    });

/// A recipe's per-serving macros, but only when every ingredient counted.
///
/// A recipe with unmatched ingredients has a number that is missing part of
/// itself. Filtering "under 600 kcal" on that would hand back a 900 kcal dish
/// because half of it was invisible — so an incomplete recipe reports no
/// macros at all and the macro chips exclude it (spec §5.3's flag-don't-guess).
Macros? _perServingIfComplete(Recipe recipe, Map<String, Food> foods) {
  if (recipe.allIngredients.isEmpty) return null;
  final RecipeMacros macros = MacroCalculator.forRecipe(recipe, foods: foods);
  return macros.isIncomplete ? null : macros.perServing;
}

// ── Cook-along (spec §5.2) ───────────────────────────────────────────────────

/// Keeps the screen awake while cooking.
///
/// A provider so a widget test can swap in the no-op and exercise cook mode
/// without a platform channel.
final Provider<ScreenKeeper> screenKeeperProvider = Provider<ScreenKeeper>(
  (Ref ref) => PlatformScreenKeeper(),
);

/// Cook-timer alerts that outlive the app being backgrounded.
final Provider<TimerAlerts> timerAlertsProvider = Provider<TimerAlerts>(
  (Ref ref) => PlatformTimerAlerts(),
);

final Provider<CookTimerStore> cookTimerStoreProvider =
    Provider<CookTimerStore>(
      (Ref ref) => CookTimerStore(ref.watch(databaseProvider)),
    );

/// Running cook timers, app-wide and persisted — see [CookTimersNotifier] for
/// why they do not live in the cook-along screen.
final AsyncNotifierProvider<CookTimersNotifier, List<CookTimer>>
cookTimersProvider = AsyncNotifierProvider<CookTimersNotifier, List<CookTimer>>(
  CookTimersNotifier.new,
);

final Provider<PreferenceStore> preferenceStoreProvider =
    Provider<PreferenceStore>(
      (Ref ref) => PreferenceStore(ref.watch(databaseProvider)),
    );

/// Whether cook-along shows every step at once.
///
/// Remembered across launches: a cook who prefers the whole list should not
/// have to say so every time they open a recipe.
final AsyncNotifierProvider<CookStepViewNotifier, bool>
cookShowAllStepsProvider = AsyncNotifierProvider<CookStepViewNotifier, bool>(
  CookStepViewNotifier.new,
);

class CookStepViewNotifier extends AsyncNotifier<bool> {
  PreferenceStore get _store => ref.read(preferenceStoreProvider);

  @override
  Future<bool> build() => _store.readFlag(PreferenceStore.cookShowAllSteps);

  Future<void> toggle() async {
    final bool wanted = !(state.value ?? false);
    state = AsyncValue<bool>.data(wanted);
    await _store.writeFlag(PreferenceStore.cookShowAllSteps, value: wanted);
  }
}

/// Light, dark, or whatever the device is doing (spec §6.1).
///
/// Device-local, like every other preference in this store: a theme is a
/// statement about the screen in front of you, and pushing it to a partner
/// would change their app for a reason they could not see.
final AsyncNotifierProvider<ThemeChoiceNotifier, ThemeChoice>
themeChoiceProvider = AsyncNotifierProvider<ThemeChoiceNotifier, ThemeChoice>(
  ThemeChoiceNotifier.new,
);

/// The theme already read off the device before the first frame, by
/// `bootstrap`.
///
/// Null in anything that did not come through `main` — widget tests, mostly —
/// where the notifier reads it itself and the first frame or two follow the
/// device instead.
final Provider<ThemeChoice?> launchThemeChoiceProvider = Provider<ThemeChoice?>(
  (Ref ref) => null,
);

class ThemeChoiceNotifier extends AsyncNotifier<ThemeChoice> {
  PreferenceStore get _store => ref.read(preferenceStoreProvider);

  @override
  FutureOr<ThemeChoice> build() {
    // Synchronously when the app came through main(), because the answer was
    // read before anything was painted. Reading it here instead costs a Drift
    // open and a query, and until those returned the app painted
    // ThemeMode.system — a light flash on every cold start for anyone who had
    // asked for dark.
    final ThemeChoice? atLaunch = ref.read(launchThemeChoiceProvider);
    if (atLaunch != null) return atLaunch;
    return _store.read(PreferenceStore.themeChoice).then(ThemeChoice.parse);
  }

  /// Changes the theme, and rethrows if the change could not be stored.
  ///
  /// The caller is expected to await it and say so. An optimistic write that
  /// failed and was never taken back is the worst of both: the app stays dark
  /// until the next launch and is quietly light after it, with nothing ever
  /// said about why.
  Future<void> choose(ThemeChoice choice) async {
    // Repaint first, write second. Recolouring the whole app is the entire
    // point of the tap, and it has no business waiting on a disk write.
    final ThemeChoice previous = state.value ?? ThemeChoice.system;
    state = AsyncValue<ThemeChoice>.data(choice);
    try {
      await _store.write(PreferenceStore.themeChoice, choice.stored);
    } on Object {
      // Back to what is actually on the device, so what is on screen and what
      // the next launch will do are the same thing again.
      state = AsyncValue<ThemeChoice>.data(previous);
      rethrow;
    }
  }
}

final Provider<CookSessionStore> cookSessionStoreProvider =
    Provider<CookSessionStore>(
      (Ref ref) => CookSessionStore(ref.watch(databaseProvider)),
    );

// ── Taking your data with you (spec §7.4) ────────────────────────────────────

final Provider<DataExport> dataExportProvider = Provider<DataExport>(
  (Ref ref) => DataExport(
    database: ref.watch(databaseProvider),
    recipes: RecipeStore(ref.watch(databaseProvider)),
    foods: FoodStore(ref.watch(databaseProvider)),
  ),
);

/// Handing the file to the OS, behind an interface so a widget test can watch
/// it happen without a share sheet (rule 7).
final Provider<FileShare> fileShareProvider = Provider<FileShare>(
  (Ref ref) => const SharePlusFileShare(),
);

// ── Recipe photos (spec §5.2) ────────────────────────────────────────────────

final Provider<PhotoPicker> photoPickerProvider = Provider<PhotoPicker>(
  (Ref ref) => ImagePickerPhotos(),
);

/// Turning a PDF's pages into pictures, for reading a menu off one (§5.2).
final Provider<PdfPages> pdfPagesProvider = Provider<PdfPages>(
  (Ref ref) => const PdfxPages(),
);

final Provider<RecipePhotoStore> recipePhotoStoreProvider =
    Provider<RecipePhotoStore>(
      (Ref ref) => RecipePhotoStore(
        ref.watch(databaseProvider),
        directory: getApplicationSupportDirectory,
      ),
    );

/// Every recipe's photo file name, so the library can show thumbnails without
/// a query per card.
final StreamProvider<Map<String, String>> recipePhotoNamesProvider =
    StreamProvider<Map<String, String>>(
      (Ref ref) => ref.watch(recipePhotoStoreProvider).watchAll(),
    );

/// Photos in the household's bucket (spec §5.2, rule 7).
///
/// Null when there is no backend, matching every other remote provider — and
/// the honest state of a build with none configured.
final Provider<PhotoStorage?> photoStorageProvider = Provider<PhotoStorage?>(
  (Ref ref) => ref.watch(supabaseReadyProvider)
      ? SupabasePhotoStorage(Supabase.instance.client)
      : null,
);

/// The photo half of a sync pass. Null for the same reason as above.
final Provider<PhotoSync?> photoSyncProvider = Provider<PhotoSync?>((Ref ref) {
  final PhotoStorage? storage = ref.watch(photoStorageProvider);
  if (storage == null) return null;
  return PhotoSync(
    database: ref.watch(databaseProvider),
    photos: ref.watch(recipePhotoStoreProvider),
    recipes: ref.watch(recipeRepositoryProvider),
    storage: storage,
  );
});

/// How much photo work is waiting, so adding one nudges a sync.
///
/// A Drift stream, like [pendingWriteCountProvider], and under the same
/// standing warning: nothing may invalidate it by hand.
final StreamProvider<int> pendingPhotoWorkProvider = StreamProvider<int>(
  (Ref ref) => ref.watch(recipePhotoStoreProvider).watchPendingWork(),
);

/// What a photo's sharing state is, for the one recipe on screen.
///
/// Watched rather than read: an upload finishing should update the line
/// without the user touching anything.
final recipePhotoRowProvider = StreamProvider.family<RecipePhotoRow?, String>(
  (Ref ref, String recipeId) =>
      ref.watch(recipePhotoStoreProvider).watchRow(recipeId),
);

/// The directory photos are resolved against.
final FutureProvider<Directory> recipePhotoDirectoryProvider =
    FutureProvider<Directory>(
      (Ref ref) => ref.watch(recipePhotoStoreProvider).photosDirectory(),
    );

// ── Accounts (spec §5.1, §8.3) ───────────────────────────────────────────────

/// Whether this build came up with a Supabase connection.
///
/// Overridden at startup by [bootstrap]. False in tests and in any build with
/// no `config/local.json`, which is a supported way to run — offline, alone.
final Provider<bool> supabaseReadyProvider = Provider<bool>((Ref ref) => false);

final Provider<AuthGateway> authGatewayProvider = Provider<AuthGateway>((
  Ref ref,
) {
  if (!ref.watch(supabaseReadyProvider)) return LocalAuthGateway();
  final SupabaseAuthGateway gateway = SupabaseAuthGateway(
    Supabase.instance.client,
    // Lets a cold start with no signal get in on a session that is already in
    // the Keychain (spec §5.1's offline-first promise).
    cache: AccountCache(ref.watch(preferenceStoreProvider)),
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// The signed-in account, or null when nobody is.
final StreamProvider<HearthAccount?> accountProvider =
    StreamProvider<HearthAccount?>(
      (Ref ref) => ref.watch(authGatewayProvider).watchAccount(),
    );

// ── Sync (spec §7.1) ─────────────────────────────────────────────────────────

final Provider<RemoteGateway?> remoteGatewayProvider = Provider<RemoteGateway?>(
  (Ref ref) => ref.watch(supabaseReadyProvider)
      ? SupabaseRemoteGateway(Supabase.instance.client)
      : null,
);

final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>((Ref ref) {
  final RemoteGateway? gateway = ref.watch(remoteGatewayProvider);
  if (gateway == null) {
    throw StateError('Sync needs a configured Supabase connection.');
  }
  return SyncEngine(
    queue: ref.watch(pendingWriteStoreProvider),
    gateway: gateway,
  );
});

/// How many writes are waiting to go up. Also the signal that something was
/// written locally, which is one of the things that triggers a sync.
final StreamProvider<int> pendingWriteCountProvider = StreamProvider<int>(
  (Ref ref) => ref.watch(pendingWriteStoreProvider).watchCount(),
);

final NotifierProvider<SyncController, SyncStatus> syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

final Provider<LibrarySync> librarySyncProvider = Provider<LibrarySync>(
  (Ref ref) => LibrarySync(
    engine: ref.watch(syncEngineProvider),
    recipes: ref.watch(recipeStoreProvider),
    foods: ref.watch(foodStoreProvider),
    queue: ref.watch(pendingWriteStoreProvider),
    preferences: ref.watch(preferenceStoreProvider),
  ),
);

final Provider<RemoteRows> remoteRowsProvider = Provider<RemoteRows>(
  (Ref ref) => RemoteRows(ref.watch(databaseProvider)),
);

final Provider<RecordSync> recordSyncProvider = Provider<RecordSync>(
  (Ref ref) => RecordSync(
    engine: ref.watch(syncEngineProvider),
    rows: ref.watch(remoteRowsProvider),
    queue: ref.watch(pendingWriteStoreProvider),
    preferences: ref.watch(preferenceStoreProvider),
    userId: () => ref.read(currentUserIdProvider),
  ),
);

// ── Food lookup (spec §5.5) ──────────────────────────────────────────────────

/// The lookup chain, in the order §5.5 sets: the household's own library
/// first, then Open Food Facts, then USDA.
///
/// External sources are only in the chain when there is a backend to reach.
/// An unconfigured build still looks things up — it just finds only what the
/// household already knows, which is the honest answer offline.
/// Whether a camera is available to scan with.
///
/// Windows has none that mobile_scanner speaks to, and asking for one produces
/// a permission prompt that can never be satisfied. macOS is included because
/// the package ships a real implementation there and every Mac has a webcam —
/// which also makes the detector testable without a phone.
///
/// A provider rather than a bare platform check so a test can drive the
/// typed-barcode path — the whole flow apart from the detector itself —
/// without hardware.
final Provider<bool> cameraScanningAvailableProvider = Provider<bool>(
  (Ref ref) => switch (defaultTargetPlatform) {
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.macOS => true,
    _ => false,
  },
);

/// Recipe import and generation (spec §5.3, §5.4).
///
/// Null when there is no backend to reach: the Claude API key lives in an Edge
/// Function, so an unconfigured build has no way to import or generate and the
/// screens say so rather than failing at the moment of use.
final Provider<RecipeAiSource?> recipeAiProvider = Provider<RecipeAiSource?>(
  (Ref ref) => ref.watch(supabaseReadyProvider)
      ? EdgeFunctionRecipeAi(Supabase.instance.client)
      : null,
);

/// Reading a nutrition label off a photo (spec §5.5).
///
/// Nullable for the same reason as [recipeAiProvider], and the buttons that
/// use it hide themselves rather than failing on tap: offering a camera that
/// cannot lead anywhere is worse than not offering one.
final Provider<LabelReader?> labelReaderProvider = Provider<LabelReader?>(
  (Ref ref) => ref.watch(supabaseReadyProvider)
      ? EdgeFunctionLabelReader(Supabase.instance.client)
      : null,
);

/// Draws a recipe's little sketch icon (spec §5.2, §6.1).
///
/// Null without a backend, like the readers above — and unlike them, nothing
/// says so. An icon is decoration: a build that cannot draw one simply has
/// recipes without pictures, which is what every recipe starts as.
final Provider<RecipeIconSource?> recipeIconProvider =
    Provider<RecipeIconSource?>(
      (Ref ref) => ref.watch(supabaseReadyProvider)
          ? EdgeFunctionRecipeIcon(Supabase.instance.client)
          : null,
    );

/// Reads a restaurant's nutrition table off pictures of it (spec §5.2).
///
/// Null without a backend, the same way the label reader is: the screens that
/// offer it hide the button rather than failing on tap.
final Provider<MenuReader?> menuReaderProvider = Provider<MenuReader?>(
  (Ref ref) => ref.watch(supabaseReadyProvider)
      ? EdgeFunctionMenuReader(Supabase.instance.client)
      : null,
);

/// Where content shared from another app arrives (spec §5.3).
///
/// Only iOS has a share sheet Hearth is part of; everywhere else the honest
/// implementation is one that never emits, so nothing above has to ask which
/// platform it is on before listening.
final Provider<SharedContentSource> sharedContentSourceProvider =
    Provider<SharedContentSource>((Ref ref) {
      if (!PlatformSharedContent.isSupported) return const NoSharedContent();
      final PlatformSharedContent source = PlatformSharedContent();
      return source;
    });

/// Everything shared into Hearth, whether it arrived while the app was open
/// or was waiting on disk before it started.
///
/// The two cases are genuinely different — a share extension runs in its own
/// process and often while Hearth is not running at all — and neither is the
/// special one, so both come down the same stream.
final StreamProvider<SharedContent> sharedContentProvider =
    StreamProvider<SharedContent>((Ref ref) async* {
      final SharedContentSource source = ref.watch(sharedContentSourceProvider);
      if (await source.pending() case final SharedContent waiting) {
        yield waiting;
      }
      yield* source.incoming;
    });

final Provider<NutritionLookup> nutritionLookupProvider =
    Provider<NutritionLookup>((Ref ref) {
      final bool connected = ref.watch(supabaseReadyProvider);
      return NutritionLookup(<NutritionSource>[
        LibraryNutritionSource(
          store: ref.watch(foodStoreProvider),
          householdId: ref.watch(currentHouseholdIdProvider),
        ),
        OpenFoodFactsSource(),
        if (connected) UsdaNutritionSource(Supabase.instance.client),
      ]);
    });
