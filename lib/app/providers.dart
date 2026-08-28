import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/food_store.dart';
import '../data/local/hearth_database.dart';
import '../data/local/ingredient_match_store.dart';
import '../data/local/pending_write_store.dart';
import '../data/local/plan_store.dart';
import '../data/local/recipe_store.dart';
import '../data/repositories/food_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../domain/models/food.dart';
import '../domain/models/recipe.dart';
import '../domain/planning/day_progress.dart';
import '../domain/planning/meal_plan.dart';
import '../domain/planning/recent_log.dart';
import '../domain/planning/week.dart';

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
/// Auth fills this in once accounts land; until then it is a fixed local id so
/// the library works end to end on one device. It is deliberately a provider
/// rather than a constant so that switch is a one-line override rather than a
/// hunt through the feature code.
final Provider<String> currentHouseholdIdProvider = Provider<String>(
  (Ref ref) => 'local-household',
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

/// The person whose plan and logs are on screen.
///
/// Plans, logs, and targets are user-scoped, not household-scoped: two people
/// share a library but never a diary (spec §4). Auth fills this in; until then
/// it is a fixed local id.
final Provider<String> currentUserIdProvider = Provider<String>(
  (Ref ref) => 'local-user',
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
