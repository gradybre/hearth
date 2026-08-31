import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/food_profile.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/main.dart';

import 'fake_kitchen.dart';

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
  Stream<List<Recipe>>? recipeStream,
  List<Food> foods = const <Food>[],
  List<MealPlanEntry> entries = const <MealPlanEntry>[],
  Set<String> favorites = const <String>{},
  List<CookTimer> timers = const <CookTimer>[],
  Map<String, String> photos = const <String, String>{},
  List<CollectionSummary> collections = const <CollectionSummary>[],
  bool cameraAvailable = false,
  List<NutritionSource> nutritionSources = const <NutritionSource>[],
  RecipeAiSource? recipeAi,
  PhotoPicker? photoPicker,
  FoodProfile? foodProfile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  // Foods are handed to the UI as a plain stream (see above), but some of what
  // the UI does with them writes to the database — remembering an ingredient
  // match stores a row whose food_id is a foreign key. A food that exists only
  // in the stream would make that write fail on a constraint the real app
  // never hits, so the rows go in as well.
  for (final Food food in foods) {
    await FoodStore(db).upsert(food, updatedAt: DateTime(2026));
  }

  // Same reasoning as foods: the library list reads from the stream override
  // below, but the recipe detail screen resolves a single recipe through
  // recipeByIdProvider, which reads the real database rather than the
  // stream. A recipe that exists only in the stream would show as "no longer
  // exists" the moment a test opens it.
  for (final Recipe recipe in recipes) {
    await RecipeStore(db).upsert(recipe, updatedAt: DateTime(2026));
  }

  await tester.pumpWidget(
    ProviderScope(
      // Types left to inference: flutter_riverpod 3 does not export the
      // `Override` type name, only the methods that produce one.
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Widget tests have no camera and no platform channels to ask one for.
        // Forcing this off keeps the scan screen on its typed-barcode path,
        // which is the whole flow apart from the detector itself.
        cameraScanningAvailableProvider.overrideWithValue(cameraAvailable),
        nutritionLookupProvider.overrideWithValue(
          NutritionLookup(nutritionSources),
        ),
        // Import and generation reach a paid API through an Edge Function;
        // neither belongs in a widget test, and null is also the honest state
        // of a build with no backend configured.
        recipeAiProvider.overrideWithValue(recipeAi),
        // Another sqlite-backed stream, and the same reasoning as the rest:
        // fake async cannot drive real I/O, so a live subscription would
        // never emit and would still be open at teardown.
        foodProfileProvider.overrideWith(
          (Ref ref) => Stream<FoodProfile>.value(
            foodProfile ?? FoodProfile.empty('test-user'),
          ),
        ),
        if (photoPicker != null)
          photoPickerProvider.overrideWithValue(photoPicker),
        // A stream can be supplied instead of a fixed list, for the tests that
        // need the library to actually change — a deletion, say.
        recipeLibraryProvider.overrideWith(
          (Ref ref) => recipeStream ?? Stream<List<Recipe>>.value(recipes),
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
        // The shell's timer bar watches this, and it is DB-backed.
        cookTimersProvider.overrideWith(() => FakeCookTimers(timers)),
        cookShowAllStepsProvider.overrideWith(FakeCookStepView.new),
        // Photos are sqlite- and filesystem-backed, neither of which a widget
        // test can drive under fake async.
        recipePhotoNamesProvider.overrideWith(
          (Ref ref) => Stream<Map<String, String>>.value(photos),
        ),
        recipePhotoDirectoryProvider.overrideWith(
          (Ref ref) async => Directory.systemTemp,
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
