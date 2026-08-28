import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/hearth_database.dart';
import '../data/local/pending_write_store.dart';
import '../data/local/recipe_store.dart';
import '../data/repositories/recipe_repository.dart';
import '../domain/models/recipe.dart';

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
