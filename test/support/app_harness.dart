import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/main.dart';

/// Pumps the real app for a widget test.
///
/// Two overrides, both load-bearing:
///
///  * [databaseProvider] gets an in-memory database. Without it a widget test
///    would open the on-disk database the app itself uses, so tests would
///    share state with each other and with the developer's own library.
///  * [recipeLibraryProvider] and [foodLibraryProvider] are fed plain streams.
///    Widget tests run under fake async, which cannot drive real sqlite I/O,
///    so a DB-backed stream would never emit — leaving the loading spinner on
///    screen and its animation timer pending at teardown. Feeding the data
///    directly keeps these tests about the UI, deterministic, and fast.
///
/// Repository behaviour is covered against a real database in the data-layer
/// tests, which are the right place for it.
Future<HearthDatabase> pumpHearthApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<Recipe> recipes = const <Recipe>[],
  List<Food> foods = const <Food>[],
  List<MealPlanEntry> entries = const <MealPlanEntry>[],
  Set<String> favorites = const <String>{},
  List<CollectionSummary> collections = const <CollectionSummary>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      // Types left to inference: flutter_riverpod 3 does not export the
      // `Override` type name, only the methods that produce one.
      overrides: [
        databaseProvider.overrideWithValue(db),
        recipeLibraryProvider.overrideWith(
          (Ref ref) => Stream<List<Recipe>>.value(recipes),
        ),
        foodLibraryProvider.overrideWith(
          (Ref ref) => Stream<List<Food>>.value(foods),
        ),
        // Same reasoning as the libraries: fake async cannot drive sqlite, so
        // the planner's day is fed directly.
        dayEntriesProvider.overrideWith((Ref ref) async => entries),
        planChangesProvider.overrideWith(
          (Ref ref) => const Stream<void>.empty(),
        ),
        recentLogsProvider.overrideWith((Ref ref) async => const <RecentLog>[]),
        weekEntriesProvider.overrideWith(
          (Ref ref) async => <DateTime, List<MealPlanEntry>>{},
        ),
        // Favourites and collections are sqlite-backed streams too, so they
        // need the same treatment — without these the library screen sits on
        // its spinner forever and the test times out rather than failing.
        favoriteRecipeIdsProvider.overrideWith(
          (Ref ref) => Stream<Set<String>>.value(favorites),
        ),
        collectionsProvider.overrideWith(
          (Ref ref) => Stream<List<CollectionSummary>>.value(collections),
        ),
        recipeCollectionsProvider.overrideWith(
          (Ref ref) =>
              Stream<Map<String, Set<String>>>.value(<String, Set<String>>{
                for (final CollectionSummary collection in collections)
                  for (final String recipeId in collection.recipeIds)
                    recipeId: <String>{
                      for (final CollectionSummary c in collections)
                        if (c.recipeIds.contains(recipeId)) c.id,
                    },
              }),
        ),
      ],
      child: const HearthApp(),
    ),
  );
  await tester.pump();
  return db;
}

/// Pumps a few frames without settling.
///
/// `pumpAndSettle` cannot be used anywhere in this app: the loading spinners
/// animate forever, so settling waits out the full timeout. A handful of timed
/// pumps is enough for a provider to resolve and the tree to rebuild.
Future<void> pumpFrames(WidgetTester tester, {int frames = 5}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
