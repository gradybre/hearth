import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';
import 'package:hearth/features/foods/food_editor_screen.dart';
import 'package:hearth/features/plan/logged_details_sheet.dart';
import 'package:hearth/features/plan/nutrient_contributors_flow.dart';
import 'package:hearth/features/plan/nutrient_contributors_screen.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;

final DateTime _date = DateTime(2026, 9, 30);
const String _user = 'captured-user';
const String _house = 'captured-house';
const String _entryId = 'saved-meal';
const String _sourceId = 'current-source';

final _identityProvider = NotifierProvider<_Identity, (String, String)>(
  _Identity.new,
);

class _Identity extends Notifier<(String, String)> {
  @override
  (String, String) build() => (_user, _house);
  void select(String user, String house) => state = (user, house);
}

Food _food({bool global = false, bool deleted = false}) => Food(
  id: _sourceId,
  householdId: global ? null : _house,
  name: 'Current food name',
  source: FoodSource.manual,
  isDeleted: deleted,
  servingOptions: <ServingOption>[
    ServingOption(
      id: 'current-serving',
      label: '200 g pot',
      amount: Quantity.of(200, Units.gram),
      macros: const Macros(kcal: 900),
    ),
  ],
);

Recipe _recipe() => const Recipe(
  id: _sourceId,
  title: 'Current recipe name',
  householdId: _house,
  servings: 4,
  sections: <RecipeSection>[],
);

MealPlanEntry _entry({PlanRefType type = PlanRefType.food}) => MealPlanEntry(
  id: _entryId,
  dayId: PlanRepository.dayIdFor(userId: _user, date: _date),
  slot: MealSlot.lunch,
  refType: type,
  refId: _sourceId,
  servings: 1.5,
  isLogged: true,
  loggedAt: DateTime(2026, 9, 30, 12),
  macroSnapshot: MacroSnapshot(
    label: 'Frozen meal name',
    macros: const Macros(kcal: 250, proteinG: 25, fiberG: 3),
    servings: 1.5,
    capturedAt: DateTime(2026, 9, 30, 12),
    coverage: const NutrientCoverage.allComplete(),
  ),
);

class _Foods extends FoodRepository {
  _Foods(HearthDatabase db)
    : super(
        database: db,
        store: FoodStore(db),
        queue: PendingWriteStore(db),
        householdId: _house,
      );
  Completer<void>? gate;
  int calls = 0;
  int? gateAtCall;
  @override
  Future<Food?> byId(String id) async {
    calls += 1;
    if (gateAtCall == null || gateAtCall == calls) await gate?.future;
    return super.byId(id);
  }
}

class _Session {
  _Session(this.db, this.container, this.foods, this.entries);
  final HearthDatabase db;
  final ProviderContainer container;
  final _Foods foods;
  final List<MealPlanEntry> entries;
  NutrientContributorsScreen screen(WidgetTester tester) =>
      tester.widget<NutrientContributorsScreen>(
        find.byType(NutrientContributorsScreen),
      );
  Future<List<MealPlanEntryRow>> history() =>
      db.select(db.mealPlanEntries).get();
  Future<int> queuedWrites() async =>
      (await db.select(db.pendingWrites).get()).length;
}

Future<_Session> _pump(
  WidgetTester tester, {
  PlanRefType type = PlanRefType.food,
  bool global = false,
  bool sourceDeleted = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1000);
  addTearDown(tester.view.reset);
  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  final List<MealPlanEntry> entries = <MealPlanEntry>[_entry(type: type)];
  final PlanStore plans = PlanStore(db);
  await plans.ensureDay(
    userId: _user,
    date: _date,
    idFactory: () => entries.single.dayId,
    updatedAt: _date,
  );
  await plans.upsertEntry(entries.single, updatedAt: _date);
  final Food food = _food(global: global, deleted: sourceDeleted);
  await FoodStore(db).upsert(food, updatedAt: _date);
  await RecipeStore(db).upsert(_recipe(), updatedAt: _date);
  final _Foods foods = _Foods(db);
  final ProviderContainer container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith(
        (Ref ref) => ref.watch(_identityProvider).$1,
      ),
      currentHouseholdIdProvider.overrideWith(
        (Ref ref) => ref.watch(_identityProvider).$2,
      ),
      accountProvider.overrideWith((Ref ref) {
        final (String, String) identity = ref.watch(_identityProvider);
        return Stream<HearthAccount?>.value(
          HearthAccount(
            userId: identity.$1,
            householdId: identity.$2,
            email: 'synthetic@example.com',
          ),
        );
      }),
      foodRepositoryProvider.overrideWithValue(foods),
      foodLibraryProvider.overrideWith(
        (Ref ref) => Stream<List<Food>>.value(<Food>[food]),
      ),
      recipeLibraryProvider.overrideWith(
        (Ref ref) => Stream<List<Recipe>>.value(<Recipe>[_recipe()]),
      ),
      planChangesProvider.overrideWith((Ref ref) => const Stream<void>.empty()),
      dayEntriesProvider.overrideWith((Ref ref) async => <MealPlanEntry>[]),
      recipeIconProvider.overrideWithValue(null),
      recipeAiProvider.overrideWithValue(null),
      labelReaderProvider.overrideWithValue(null),
      favoriteRecipeIdsProvider.overrideWith(
        (Ref ref) => Stream<Set<String>>.value(<String>{}),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                await showDailyNutrientContributors(
                  context,
                  date: _date,
                  nutrient: SupportedNutrient.calories,
                  entries: entries,
                );
              },
              child: const Text('Open saved contributors'),
            ),
          ),
        ),
      ),
    ),
  );
  await pumpFrames(tester, frames: 8);
  await tester.tap(find.text('Open saved contributors'));
  await pumpFrames(tester, frames: 12);
  return _Session(db, container, foods, entries);
}

Future<void> _press(WidgetTester tester, String text) async {
  final Finder target = find.text(text).last;
  await tester.ensureVisible(target);
  await pumpFrames(tester);
  await tester.tap(target.hitTestable());
  await pumpFrames(tester, frames: 12);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('system back closes frozen details first and then the receipt', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    final List<MealPlanEntryRow> before = await session.history();
    await _press(tester, 'View logged details');
    await tester.binding.handlePopRoute();
    await pumpFrames(tester, frames: 12);
    expect(find.byType(LoggedDetailsSheet), findsNothing);
    expect(find.byType(NutrientContributorsScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester, frames: 12);
    expect(find.text('Open saved contributors'), findsOneWidget);
    expect(find.byType(NutrientContributorsScreen), findsNothing);
    expect(await session.history(), before);
    expect(await session.queuedWrites(), 0);
  });

  testWidgets(
    'captures the day and opens original saved details without changing history',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      expect(find.text('Wednesday, September 30, 2026'), findsOneWidget);
      session.container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2027, 1, 2));
      session.entries.clear();
      await _press(tester, 'View logged details');
      expect(find.byType(LoggedDetailsSheet), findsOneWidget);
      expect(find.text('Frozen meal name'), findsWidgets);
      expect(find.text('Calories: 250 kcal'), findsOneWidget);
      expect(find.text('Current food name'), findsNothing);
      await _press(tester, 'Close');
      expect(await session.history(), before);
    },
  );

  for (final PlanRefType type in PlanRefType.values) {
    testWidgets(
      'Improve future logs opens the current ${type.name} editor without rewriting history',
      (WidgetTester tester) async {
        final _Session session = await _pump(tester, type: type);
        final List<MealPlanEntryRow> before = await session.history();
        await _press(tester, 'Improve future logs');
        if (type == PlanRefType.food) {
          expect(find.byType(FoodEditorScreen), findsOneWidget);
          expect(
            tester
                .widget<FoodEditorScreen>(find.byType(FoodEditorScreen))
                .foodId,
            _sourceId,
          );
          expect(
            find.widgetWithText(TextField, 'Current food name'),
            findsOneWidget,
          );
        } else {
          expect(find.byType(RecipeEditorScreen), findsOneWidget);
          expect(
            tester
                .widget<RecipeEditorScreen>(find.byType(RecipeEditorScreen))
                .recipeId,
            _sourceId,
          );
          expect(
            find.widgetWithText(TextField, 'Current recipe name'),
            findsOneWidget,
          );
        }
        expect(find.byType(NutrientContributorsScreen), findsNothing);
        await _press(tester, 'Cancel');
        expect(find.text('Open saved contributors'), findsOneWidget);
        expect(find.byType(NutrientContributorsScreen), findsNothing);
        expect(await session.history(), before);
        expect(await session.queuedWrites(), 0);
      },
    );
  }

  testWidgets(
    'global food opens the existing reviewed copy editor with no global identity',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester, global: true);
      final List<MealPlanEntryRow> before = await session.history();
      await _press(tester, 'Improve future logs');
      final FoodEditorScreen editor = tester.widget<FoodEditorScreen>(
        find.byType(FoodEditorScreen),
      );
      expect(editor.foodId, isNull);
      expect(editor.initialDraft!.existingId, isNull);
      expect(editor.initialDraft!.name, 'Current food name');
      expect(await session.history(), before);
      expect((await FoodStore(session.db).byId(_sourceId))!.isGlobal, isTrue);
    },
  );

  testWidgets('source deleted after opening is rechecked before editing', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    final List<MealPlanEntryRow> before = await session.history();
    await FoodStore(session.db)
        .softDelete(_sourceId, updatedAt: DateTime(2026, 10));
    await _press(tester, 'Improve future logs');
    expect(find.byType(FoodEditorScreen), findsNothing);
    expect(
      find.text(
        'The current food is unavailable. Your saved log has not changed.',
      ),
      findsOneWidget,
    );
    expect(await session.history(), before);
  });

  testWidgets(
    'deleted source still opens frozen details and hides current source action',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester, sourceDeleted: true);
      final List<MealPlanEntryRow> before = await session.history();
      await _press(tester, 'View logged details');
      expect(find.text('Calories: 250 kcal'), findsOneWidget);
      expect(find.text('View current food'), findsNothing);
      expect(await session.history(), before);
    },
  );

  testWidgets('View current food opens read-only current details', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    final List<MealPlanEntryRow> before = await session.history();
    await _press(tester, 'View logged details');
    await _press(tester, 'View current food');
    expect(find.byType(FoodDetailScreen), findsOneWidget);
    expect(find.text('Current food name'), findsOneWidget);
    expect(find.byType(FoodEditorScreen), findsNothing);
    expect(await session.history(), before);
  });

  testWidgets('changed saved meal refuses an edit from the old receipt', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await _press(tester, 'View logged details');
    await PlanStore(session.db).upsertEntry(
      _entry().copyWith(servings: 2),
      updatedAt: DateTime(2026, 10),
    );
    final List<MealPlanEntryRow> changed = await session.history();
    await _press(tester, 'Edit portion');
    expect(
      find.text(
        'This logged meal changed. Close this view and reopen the day.',
      ),
      findsOneWidget,
    );
    expect(find.text('Update logged portion'), findsNothing);
    expect(await session.history(), changed);
  });

  testWidgets(
    'portion handoff retains captured day, meal and saved serving count',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      session.container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2027, 1, 2));
      await _press(tester, 'View logged details');
      await _press(tester, 'Edit portion');
      expect(find.byType(NutrientContributorsScreen), findsNothing);
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(find.text('Frozen meal name'), findsOneWidget);
      expect(
        find.text('Lunch · ${relativeDay(_date) ?? 'Wednesday 9/30'}'),
        findsOneWidget,
      );
      expect(find.text('Saved servings'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1 1/2'), findsOneWidget);
      expect(find.text('Update logged portion'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, frames: 12);
      expect(find.text('Open saved contributors'), findsOneWidget);
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'closing during source lookup blocks that result and held edit callbacks',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      final NutrientContributorsScreen held = session.screen(tester);
      final MealPlanEntry saved = session.entries.single;
      final Completer<void> gate = Completer<void>();
      session.foods.gate = gate;
      final Future<void> pending = held.onImproveFuture(saved);
      await pumpFrames(tester);
      expect(session.foods.calls, 1);
      await tester.tap(
        find.byKey(const ValueKey<String>('nutrient-contributors-back')),
      );
      await pumpFrames(tester, frames: 12);
      expect(find.text('Open saved contributors'), findsOneWidget);
      gate.complete();
      await pending;
      await held.onImproveFuture(saved);
      await held.onOpenLoggedDetails(saved);
      await pumpFrames(tester, frames: 12);
      expect(session.foods.calls, 1);
      expect(find.byType(FoodEditorScreen), findsNothing);
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'source is checked again after closing the receipt before editor handoff',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      final Completer<void> gate = Completer<void>();
      session.foods
        ..gate = gate
        ..gateAtCall = 2;
      await _press(tester, 'Improve future logs');
      expect(session.foods.calls, 2);
      expect(find.byType(NutrientContributorsScreen), findsNothing);
      await FoodStore(session.db)
          .softDelete(_sourceId, updatedAt: DateTime(2026, 10));
      gate.complete();
      await pumpFrames(tester, frames: 12);
      expect(find.byType(FoodEditorScreen), findsNothing);
      expect(
        find.text(
          'The current food is unavailable. Your saved log has not changed.',
        ),
        findsOneWidget,
      );
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'meal changed during final source lookup refuses the stale handoff',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final Completer<void> gate = Completer<void>();
      session.foods
        ..gate = gate
        ..gateAtCall = 2;
      await _press(tester, 'Improve future logs');
      expect(session.foods.calls, 2);
      await PlanStore(session.db).upsertEntry(
        _entry().copyWith(servings: 2),
        updatedAt: DateTime(2026, 10),
      );
      final List<MealPlanEntryRow> changed = await session.history();
      gate.complete();
      await pumpFrames(tester, frames: 12);
      expect(find.byType(FoodEditorScreen), findsNothing);
      expect(
        find.text(
          'This logged meal changed. Close this view and reopen the day.',
        ),
        findsOneWidget,
      );
      expect(await session.history(), changed);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'household change during final source lookup cancels the handoff',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      final Completer<void> gate = Completer<void>();
      session.foods
        ..gate = gate
        ..gateAtCall = 2;
      await _press(tester, 'Improve future logs');
      expect(session.foods.calls, 2);
      session.container
          .read(_identityProvider.notifier)
          .select(_user, 'other-house');
      await pumpFrames(tester);
      session.container.read(_identityProvider.notifier).select(_user, _house);
      await pumpFrames(tester);
      gate.complete();
      await pumpFrames(tester, frames: 12);
      expect(find.byType(FoodEditorScreen), findsNothing);
      expect(find.text('Open saved contributors'), findsOneWidget);
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'losing the original page during final source lookup cancels the handoff',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      final Completer<void> gate = Completer<void>();
      session.foods
        ..gate = gate
        ..gateAtCall = 2;
      await _press(tester, 'Improve future logs');
      expect(session.foods.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await pumpFrames(tester, frames: 12);
      expect(tester.takeException(), isNull);
      expect(find.byType(FoodEditorScreen), findsNothing);
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );

  testWidgets(
    'account change during source lookup stops navigation and cannot revive away and back',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      final List<MealPlanEntryRow> before = await session.history();
      final NutrientContributorsScreen held = session.screen(tester);
      final MealPlanEntry saved = session.entries.single;
      final Completer<void> gate = Completer<void>();
      session.foods.gate = gate;
      final Future<void> pending = held.onImproveFuture(saved);
      await pumpFrames(tester);
      session.container
          .read(_identityProvider.notifier)
          .select('other-user', 'other-house');
      await pumpFrames(tester);
      session.container.read(_identityProvider.notifier).select(_user, _house);
      await pumpFrames(tester);
      gate.complete();
      await pending;
      await pumpFrames(tester);
      expect(find.byType(FoodEditorScreen), findsNothing);
      await held.onImproveFuture(saved);
      await held.onOpenLoggedDetails(saved);
      await pumpFrames(tester);
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(
        find.text('This view expired. Open the day and try again.'),
        findsOneWidget,
      );
      expect(await session.history(), before);
      expect(await session.queuedWrites(), 0);
    },
  );
}
