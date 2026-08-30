import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/adapters/edge_function_recipe_ai.dart';
import '../data/adapters/image_picker_photos.dart';
import '../data/adapters/kitchen_devices.dart';
import '../data/adapters/library_nutrition_source.dart';
import '../data/adapters/nutrition_lookup.dart';
import '../data/adapters/nutrition_source.dart';
import '../data/adapters/open_food_facts_source.dart';
import '../data/adapters/photo_picker.dart';
import '../data/adapters/platform_kitchen_devices.dart';
import '../data/adapters/recipe_ai.dart';
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
import '../data/remote/remote_gateway.dart';
import '../data/remote/supabase_remote_gateway.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/food_profile_repository.dart';
import '../data/repositories/food_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../data/sync/library_sync.dart';
import '../data/sync/record_sync.dart';
import '../data/sync/remote_rows.dart';
import '../data/sync/sync_engine.dart';
import '../domain/cooking/cook_session.dart';
import '../domain/models/food.dart';
import '../domain/models/food_profile.dart';
import '../domain/models/macros.dart';
import '../domain/models/recipe.dart';
import '../domain/planning/day_progress.dart';
import '../domain/planning/meal_plan.dart';
import '../domain/planning/recent_log.dart';
import '../domain/planning/week.dart';
import '../domain/recipes/ingredient_matcher.dart';
import '../domain/recipes/macro_calculator.dart';
import '../domain/recipes/recipe_query.dart';
import 'cook_timers.dart';
import 'sync_controller.dart';

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

/// Every remembered ingredient-string to food mapping for this household,
/// keyed by normalised string (spec §5.3).
final FutureProvider<Map<String, String>> rememberedMatchesProvider =
    FutureProvider<Map<String, String>>((Ref ref) {
      // Re-read when the food library changes, so a deleted food stops being
      // suggested.
      ref.watch(foodLibraryProvider);
      return ref
          .watch(ingredientMatchStoreProvider)
          .allFor(ref.watch(currentHouseholdIdProvider));
    });

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

  /// Clears the chips but keeps what was typed — they are separate controls,
  /// and wiping the search box out from under the cursor is startling.
  void clearChips() => state = RecipeFilter(text: state.text);

  void clearAll() => state = RecipeFilter.none;
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

final Provider<CookSessionStore> cookSessionStoreProvider =
    Provider<CookSessionStore>(
      (Ref ref) => CookSessionStore(ref.watch(databaseProvider)),
    );

// ── Recipe photos (spec §5.2) ────────────────────────────────────────────────

final Provider<PhotoPicker> photoPickerProvider = Provider<PhotoPicker>(
  (Ref ref) => ImagePickerPhotos(),
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
