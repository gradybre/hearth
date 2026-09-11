import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/menu_reader.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/pdf_pages.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/platform_shared_content.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/recipe_icon.dart';
import 'package:hearth/data/adapters/shared_content.dart';
import 'package:hearth/data/adapters/shopping_assistant.dart';
import 'package:hearth/data/auth/local_auth_gateway.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/food_profile.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/main.dart';

import 'fake_auth.dart';
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

  /// Dynamic type, driven the way the OS drives it (spec §6.3).
  ///
  /// Set on the platform dispatcher rather than wrapped in a MediaQuery,
  /// because HearthApp builds its own MaterialApp — which would rebuild the
  /// MediaQuery and throw an outer one away.
  double textScale = 1.0,

  /// The app is ThemeMode.system, so this is the switch the OS actually flips.
  Brightness brightness = Brightness.light,

  /// What the OS reserves at the edges of the screen — the status bar, the
  /// notch, the home indicator.
  ///
  /// Zero by default, which is what a test view has and what no real device
  /// has. A layout that applies the inset twice looks identical to a correct
  /// one until this is set, which is how a doubled status bar shipped once.
  EdgeInsets viewPadding = EdgeInsets.zero,

  /// Provider overrides for this test, applied ahead of the harness's own.
  ///
  /// Typed as `Object` because riverpod's `Override` is sealed and exported
  /// by neither package — the same reason the list below leaves its own type
  /// to inference. `cast` recovers it from the elements beside it.
  List<Object> extraOverrides = const <Object>[],

  /// What the sync controller reports, for a screen that says so.
  ///
  /// A parameter rather than something `extraOverrides` can supply: Riverpod 3
  /// throws on a provider overridden twice in one container whichever order
  /// they are in, and this harness already overrides both of these to keep
  /// teardown from hanging.
  SyncStatus? syncStatus,
  int pendingWrites = 0,
  List<Recipe> recipes = const <Recipe>[],
  Stream<List<Recipe>>? recipeStream,
  List<Food> foods = const <Food>[],
  List<MealPlanEntry> entries = const <MealPlanEntry>[],

  /// A whole week, for the screen that compares seven days.
  ///
  /// Separate from [entries], which is one day's worth and feeds the day
  /// view. Without this the week provider was overridden with an empty map in
  /// every test and every gallery render, so the one screen whose entire job
  /// is comparing seven days had never been drawn with anything on it.
  Map<DateTime, List<MealPlanEntry>> weekEntries =
      const <DateTime, List<MealPlanEntry>>{},

  /// The day the planner is standing on.
  ///
  /// Today unless a test says otherwise. A week fixture has to be keyed to
  /// real dates, and a test that builds one around `DateTime.now()` says
  /// nothing about what it does on the last Sunday of a month — so the date
  /// is a fact the test states rather than one it inherits from the clock.
  DateTime? selectedDate,

  /// A shopping list already on the phone (spec §5.7).
  ///
  /// Written through the real repository before the app builds, rather than
  /// handed to the screen as an override, because the screen reads its list
  /// from sqlite through `shoppingListProvider` and takes the dates on the
  /// range card from the saved list's own range. A stubbed provider would
  /// picture a list nothing could tick.
  ///
  /// The only way to arrange a populated list without it is to press "Build
  /// from the plan" — which cannot produce a ticked line, an item added by
  /// hand, or a line tagged with a shop.
  List<ShoppingLine> shoppingLines = const <ShoppingLine>[],
  MacroTargets? targets,
  Set<String> favorites = const <String>{},
  List<CookTimer> timers = const <CookTimer>[],
  Map<String, String> photos = const <String, String>{},
  List<CollectionSummary> collections = const <CollectionSummary>[],
  bool cameraAvailable = false,
  List<NutritionSource> nutritionSources = const <NutritionSource>[],
  RecipeAiSource? recipeAi,
  LabelReader? labelReader,
  MenuReader? menuReader,
  RecipeIconSource? recipeIcon,
  PdfPages? pdfPages,
  ShoppingAssistant? shoppingAssistant,
  PhotoPicker? photoPicker,
  SharedContentSource? sharedContent,
  FoodProfile? foodProfile,

  /// Where the app opens (spec §6.2).
  ///
  /// Nutrition by default, which is *not* the app's own default — the app
  /// opens on the home screen. Almost every test here is about a screen inside
  /// Nutrition, and starting them on the home screen would put a tap on a card
  /// in front of each one, which is setup rather than subject. The tests that
  /// are about the home screen and the launch preference say so explicitly.
  LaunchTarget? launchTarget,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  // Both, because MediaQuery reads `padding` while a SafeArea consults
  // `viewPadding` to decide what a keyboard has already covered — a view that
  // set only one of them would not be any device.
  final FakeViewPadding fakePadding = FakeViewPadding(
    left: viewPadding.left,
    top: viewPadding.top,
    right: viewPadding.right,
    bottom: viewPadding.bottom,
  );
  tester.view.viewPadding = fakePadding;
  tester.view.padding = fakePadding;
  addTearDown(tester.view.reset);

  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearAllTestValues);

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
    // The fixture's own timestamp where it has one. A hardcoded date here
    // makes every test about *when* a recipe changed impossible to write,
    // which is not obvious until you try — see the stale-draft test.
    await RecipeStore(db)
        .upsert(recipe, updatedAt: recipe.updatedAt ?? DateTime(2026));
  }

  // Plan entries are handed to the UI through the override below, but acting
  // on one — logging it, removing it — goes through the repository, which
  // reads the real database. An entry that existed only in the override would
  // make every gesture a silent no-op.
  if (entries.isNotEmpty) {
    final PlanStore plans = PlanStore(db);
    final DateTime today = dayKey(DateTime.now());
    await plans.ensureDay(
      userId: LocalAuthGateway.account.userId,
      date: today,
      idFactory: () => entries.first.dayId,
      updatedAt: DateTime(2026),
    );
    for (final MealPlanEntry entry in entries) {
      await plans.upsertEntry(entry, updatedAt: DateTime(2026));
    }
  }

  // Through the repository rather than the store, so the list on screen went
  // in the way the screen's own Save does: display order applied, ids derived
  // from the line keys, and the write queued for sync.
  if (shoppingLines.isNotEmpty) {
    await ShoppingRepository(
      database: db,
      store: ShoppingStore(db),
      queue: PendingWriteStore(db),
      householdId: LocalAuthGateway.account.householdId,
    ).replace(shoppingLines);
  }

  await tester.pumpWidget(
    ProviderScope(
      // Types left to inference: flutter_riverpod 3 does not export the
      // `Override` type name, only the methods that produce one.
      overrides: [
        // The caller's own, first: a test that needs a repository to fail has
        // no other way to arrange it, and a failure path nobody can reach in
        // a test is a failure path nobody has checked.
        //
        // They *add*, they do not win. Riverpod 3 throws on a provider
        // overridden twice in one container whatever the order, so anything
        // this harness overrides below needs a parameter of its own instead —
        // `syncStatus` and `pendingWrites` are here for exactly that reason.
        ...extraOverrides.cast(),
        databaseProvider.overrideWithValue(db),
        // Seeded the way bootstrap seeds it on a device, because the router is
        // built with a starting route and reads this before the first frame.
        bootLaunchTargetProvider.overrideWithValue(
          launchTarget ?? LaunchTarget.section(builtSections.first),
        ),
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
        // Reading a label goes through the same Edge Function, and the same
        // reasoning applies: null is the honest state of a build with no
        // backend, and it is what the buttons check before offering
        // themselves.
        labelReaderProvider.overrideWithValue(labelReader),
        // The menu reader, same shape: null is the honest state of a build
        // with no backend, and it is what the read buttons check before
        // offering themselves.
        menuReaderProvider.overrideWithValue(menuReader),
        // Drawing a recipe's icon reaches the same paid API. Null is the
        // honest state of a build with no backend — and unlike the readers
        // above, nothing on screen says so: a recipe simply has no picture,
        // which is what every recipe starts as.
        recipeIconProvider.overrideWithValue(recipeIcon),
        // And the PDF renderer, which would otherwise open a file dialog no
        // widget test can answer.
        pdfPagesProvider.overrideWithValue(pdfPages ?? const _NoPdf()),
        // And the list's chat. Null hides the panel, which is what a build
        // with no backend honestly does.
        shoppingAssistantProvider.overrideWithValue(shoppingAssistant),
        // Photos go to a household bucket over the network; a widget test has
        // neither. Null is also what a build with no backend honestly has.
        photoStorageProvider.overrideWithValue(null),
        // Cook-along keeps the screen awake and schedules timer alerts, both
        // of which are platform channels a widget test has none of — the
        // wakelock throws a PlatformException the moment the screen opens.
        // The household screen carries the sync panel, and the real controller
        // registers a lifecycle observer and a 600ms debounce timer. Either
        // one left running means teardown never completes — the test does not
        // fail, it hangs, which is far worse to diagnose.
        syncControllerProvider.overrideWith(
          () => FakeSyncController(syncStatus),
        ),
        // And the queue count it displays, which is a live Drift stream —
        // fake async cannot drive real sqlite, so the subscription is still
        // open at teardown and the run hangs rather than fails.
        pendingWriteCountProvider.overrideWith(
          (Ref ref) => Stream<int>.value(pendingWrites),
        ),
        screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
        timerAlertsProvider.overrideWithValue(FakeTimerAlerts()),
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
        // A share sheet cannot be driven from a widget test, and the flow
        // above the seam is the part worth testing anyway.
        sharedContentSourceProvider.overrideWithValue(
          sharedContent ?? const NoSharedContent(),
        ),
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
        // Same reasoning again: the targets live in sqlite, and a day with
        // none is a different screen entirely — the one that asks you to set
        // some — so a test about the tiles has to be able to say there are.
        dayTargetsProvider.overrideWith((Ref ref) async => targets),
        if (selectedDate case final DateTime day)
          selectedDateProvider.overrideWith(() => _FixedDate(day)),
        planChangesProvider.overrideWith(
          (Ref ref) => const Stream<void>.empty(),
        ),
        // Same reasoning, and it bit before it was written: the shopping list
        // watches sqlite for changes, and a live subscription fake async can
        // never drive is still open at teardown — which hangs the whole run,
        // not just the test. The list itself is read through the real
        // repository, so building and editing are genuinely exercised.
        shoppingChangesProvider.overrideWith(
          (Ref ref) => const Stream<void>.empty(),
        ),
        recentLogsProvider.overrideWith((Ref ref) async => const <RecentLog>[]),
        weekEntriesProvider.overrideWith((Ref ref) async => weekEntries),
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

/// A device with no PDF support, which is what a widget test is unless it
/// says otherwise.
class _NoPdf implements PdfPages {
  const _NoPdf();

  @override
  bool get isSupported => false;

  @override
  Future<PickedPdf?> pick() async => null;

  @override
  Future<RenderedPdf> render(PickedPdf pdf, {required List<int> pages}) async =>
      const RenderedPdf(pages: <RenderedPage>[]);
}

/// A PDF of [pageCount] pages that renders every page but [wontRender]
/// (spec §5.2).
///
/// A document rather than a canned batch, so the batching the screen does is
/// exercised rather than stubbed: asking for pages 7–12 gets pages 7–12 back,
/// and asking for a page that will not render gets it back in `failed` under
/// its own number.
class FakePdf implements PdfPages {
  FakePdf({
    this.pageCount = 18,
    this.name = 'nutrition-guide.pdf',
    this.wontRender = const <int>{},
    this.picks = true,
  });

  final int pageCount;
  final String name;
  final Set<int> wontRender;

  /// False for somebody who opens the dialog and changes their mind.
  final bool picks;

  /// Every batch that has been asked for, in order — so a test can show that
  /// a second read asked for different pages rather than the same six again.
  final List<List<int>> asked = <List<int>>[];

  @override
  bool get isSupported => true;

  @override
  Future<PickedPdf?> pick() async => picks
      ? PickedPdf(
          name: name,
          pageCount: pageCount,
          bytes: Uint8List.fromList(<int>[37]),
        )
      : null;

  @override
  Future<RenderedPdf> render(PickedPdf pdf, {required List<int> pages}) async {
    asked.add(List<int>.unmodifiable(pages));
    return RenderedPdf(
      pages: <RenderedPage>[
        for (final int number in pages)
          if (!wontRender.contains(number))
            RenderedPage(
              number: number,
              bytes: Uint8List.fromList(<int>[number]),
            ),
      ],
      failed: <int>[
        for (final int number in pages)
          if (wontRender.contains(number)) number,
      ],
    );
  }
}

/// Opens the library's Add recipe menu and takes one of the ways in.
///
/// The four ways used to be four buttons stacked in the corner, so tests
/// tapped them directly. They are rows in one sheet now (U05), and going
/// through it is what a person does — a test that reached past it would stop
/// noticing if the sheet broke.
Future<void> addRecipeVia(WidgetTester tester, String way) async {
  await tester.tap(find.text('Add recipe'));
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.text(way));
  await pumpFrames(tester, frames: 16);
}

/// A planner pinned to one day, for [pumpHearthApp]'s `selectedDate`.
class _FixedDate extends SelectedDate {
  _FixedDate(this.day);

  final DateTime day;

  @override
  DateTime build() => dayKey(day);
}
