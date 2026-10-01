import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';
import 'package:hearth/features/plan/day_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

const String _entryId = 'undo-meal';
const ValueKey<String> _toggle = ValueKey<String>('meal-log-$_entryId');
final DateTime _recorded = DateTime.utc(2026, 6, 2, 8, 15);

Food _food() => aFood(
  'Current yogurt',
  id: 'yogurt',
  servingOptions: <ServingOption>[
    aServing(
      id: 'pot',
      label: '170 g pot',
      amount: 170,
      unit: Units.gram,
      macros: const Macros(kcal: 999, proteinG: 90),
    ),
  ],
);

MealPlanEntry _entry({required bool logged}) {
  const MealPlanEntry planned = MealPlanEntry(
    id: _entryId,
    dayId: 'undo-day',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'yogurt',
    servings: 1.5,
  );
  return logged
      ? planned.log(
          liveMacros: const Macros(
            kcal: 170,
            proteinG: 17,
            fiberG: 2,
            sodiumMg: 30,
          ),
          at: _recorded,
          label: 'Yogurt as eaten',
          coverage: const NutrientCoverage.notRecorded(),
        )
      : planned;
}

Future<void> _press(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty &&
      find.byType(DayScreen).evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      target,
      240,
      scrollable: find
          .descendant(
            of: find.byType(DayScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 30,
    );
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await pumpFrames(tester);
  await tester.tap(target.hitTestable());
  await pumpFrames(tester, frames: 20);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DayScreen)));

class _Queue extends PendingWriteStore {
  _Queue(super.db);
  int failures = 0;
  Completer<void>? gate;
  bool waiting = false;

  @override
  Future<void> enqueue({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
    required DateTime queuedAt,
  }) async {
    await super.enqueue(
      entityTable: entityTable,
      entityId: entityId,
      operation: operation,
      payload: payload,
      queuedAt: queuedAt,
    );
    final Completer<void>? held = gate;
    if (held != null) {
      waiting = true;
      await held.future;
    }
    if (failures > 0) {
      failures--;
      throw StateError('Storage unavailable');
    }
  }
}

void main() {
  testWidgets('different meals remain tappable while another entry is saving', (
    WidgetTester tester,
  ) async {
    late _Queue queue;
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[
        _entry(logged: false),
        const MealPlanEntry(
          id: 'second',
          dayId: 'undo-day',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'yogurt',
          servings: 2,
        ),
      ],
      extraOverrides: <Object>[
        planRepositoryProvider.overrideWith((Ref ref) {
          final HearthDatabase db = ref.read(databaseProvider);
          queue = _Queue(db);
          return PlanRepository(
            database: db,
            store: PlanStore(db),
            queue: queue,
            userId: ref.read(currentUserIdProvider),
          );
        }),
      ],
    );
    queue.gate = Completer<void>();
    await _press(tester, find.byKey(_toggle));
    expect(queue.waiting, isTrue);
    await _press(tester, find.byKey(const ValueKey<String>('meal-log-second')));
    queue.gate!.complete();
    queue.gate = null;
    await pumpFrames(tester, frames: 35);
    expect(
      (await db.select(db.mealPlanEntries).get()).where(
        (MealPlanEntryRow r) => r.isLogged,
      ),
      hasLength(2),
    );
    await _press(tester, find.text('Undo'));
    final Map<String, bool> states = <String, bool>{
      for (final MealPlanEntryRow r
          in await db.select(db.mealPlanEntries).get())
        r.id: r.isLogged,
    };
    expect(states, <String, bool>{_entryId: true, 'second': false});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a row rebuild during a pending tap cannot replace its Undo with a duplicate refusal',
    (WidgetTester tester) async {
      late _Queue queue;
      final HearthDatabase db = await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.today,
        readPlanEntriesFromStore: true,
        foods: <Food>[_food()],
        entries: <MealPlanEntry>[_entry(logged: false)],
        extraOverrides: <Object>[
          planRepositoryProvider.overrideWith((Ref ref) {
            final HearthDatabase db = ref.read(databaseProvider);
            queue = _Queue(db);
            return PlanRepository(
              database: db,
              store: PlanStore(db),
              queue: queue,
              userId: ref.read(currentUserIdProvider),
            );
          }),
        ],
      );
      final ProviderContainer container = _container(tester);
      queue.gate = Completer<void>();
      final VoidCallback first = tester
          .widget<IconButton>(find.byKey(_toggle))
          .onPressed!;
      await _press(tester, find.byKey(_toggle));
      expect(queue.waiting, isTrue);
      container.invalidate(foodLibraryProvider);
      await pumpFrames(tester, frames: 20);
      final VoidCallback rebuilt = tester
          .widget<IconButton>(find.byKey(_toggle))
          .onPressed!;
      expect(identical(rebuilt, first), isFalse);
      rebuilt();
      await pumpFrames(tester, frames: 10);
      queue.gate!.complete();
      queue.gate = null;
      await pumpFrames(tester, frames: 35);
      expect(
        (await db.select(db.mealPlanEntries).getSingle()).isLogged,
        isTrue,
      );
      expect(find.text('Undo').hitTestable(), findsOneWidget);
      expect(
        find.text('This meal changed. Nothing was changed.'),
        findsNothing,
      );
      await _press(tester, find.text('Undo'));
      expect(
        (await db.select(db.mealPlanEntries).getSingle()).isLogged,
        isFalse,
      );
    },
  );

  testWidgets('ordinary Undo expires after the shared six-second window', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[_entry(logged: false)],
    );
    await _press(tester, find.byKey(_toggle));
    expect(find.text('Undo').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await pumpFrames(tester, frames: 20);
    expect(find.text('Undo'), findsNothing);
    expect((await db.select(db.mealPlanEntries).getSingle()).isLogged, isTrue);
  });

  testWidgets(
    'identity invalidation immediately before a held callback prevents a write',
    (WidgetTester tester) async {
      String user = 'local-user';
      final HearthDatabase db = await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.today,
        readPlanEntriesFromStore: true,
        foods: <Food>[_food()],
        entries: <MealPlanEntry>[_entry(logged: false)],
        extraOverrides: <Object>[
          currentUserIdProvider.overrideWith((Ref ref) => user),
        ],
      );
      final ProviderContainer container = _container(tester);
      final VoidCallback held = tester
          .widget<IconButton>(find.byKey(_toggle))
          .onPressed!;
      user = 'another-user';
      container.invalidate(currentUserIdProvider);
      held();
      await pumpFrames(tester, frames: 25);
      expect(
        (await db.select(db.mealPlanEntries).getSingle()).isLogged,
        isFalse,
      );
      expect(await db.select(db.pendingWrites).get(), isEmpty);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets(
    'account change during a delayed action rolls back and expires feedback',
    (WidgetTester tester) async {
      String user = 'local-user';
      late _Queue queue;
      final HearthDatabase db = await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.today,
        readPlanEntriesFromStore: true,
        foods: <Food>[_food()],
        entries: <MealPlanEntry>[_entry(logged: false)],
        extraOverrides: <Object>[
          currentUserIdProvider.overrideWith((Ref ref) => user),
          planRepositoryProvider.overrideWith((Ref ref) {
            final HearthDatabase db = ref.read(databaseProvider);
            queue = _Queue(db);
            return PlanRepository(
              database: db,
              store: PlanStore(db),
              queue: queue,
              userId: ref.read(currentUserIdProvider),
            );
          }),
        ],
      );
      final ProviderContainer container = _container(tester);
      final _Queue heldQueue = queue;
      heldQueue.gate = Completer<void>();
      await _press(tester, find.byKey(_toggle));
      expect(heldQueue.waiting, isTrue);
      user = 'another-user';
      container.invalidate(currentUserIdProvider);
      await pumpFrames(tester);
      heldQueue.gate!.complete();
      heldQueue.gate = null;
      await pumpFrames(tester, frames: 25);
      expect(
        (await db.select(db.mealPlanEntries).getSingle()).isLogged,
        isFalse,
      );
      expect(await db.select(db.pendingWrites).get(), isEmpty);
      expect(
        find.textContaining('This action expired.').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final Brightness brightness in Brightness.values) {
    for (final bool logged in <bool>[false, true]) {
      testWidgets(
        '${brightness.name} 320pt at 3x keeps ${logged ? "Unlog" : "Log"} Undo reachable for a screen reader',
        (WidgetTester tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures.allOn;
          final SemanticsHandle semantics = tester.ensureSemantics();
          final HearthDatabase db = await pumpHearthApp(
            tester,
            size: const Size(320, 568),
            textScale: 3,
            brightness: brightness,
            launchTarget: LaunchTarget.today,
            readPlanEntriesFromStore: true,
            foods: <Food>[_food()],
            entries: <MealPlanEntry>[_entry(logged: logged)],
          );
          final MealPlanEntryRow before = await db
              .select(db.mealPlanEntries)
              .getSingle();
          await _press(tester, find.byKey(_toggle));
          await tester.pump(const Duration(seconds: 40));
          await pumpFrames(tester);
          final Finder undo = find.text('Undo');
          expect(undo.hitTestable(), findsOneWidget);
          expect(
            tester.getSemantics(find.widgetWithText(TextButton, 'Undo')).label,
            contains('Undo'),
          );
          await _press(tester, undo);
          final MealPlanEntryRow after = await db
              .select(db.mealPlanEntries)
              .getSingle();
          expect(after.copyWith(updatedAt: before.updatedAt), before);
          expect(find.text('Change undone.').hitTestable(), findsOneWidget);
          semantics.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Undo survives navigation into the current food', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[_entry(logged: true)],
    );
    final MealPlanEntryRow before = await db
        .select(db.mealPlanEntries)
        .getSingle();
    await _press(tester, find.byKey(_toggle));
    await _press(
      tester,
      find.byKey(const ValueKey<String>('meal-open-$_entryId')),
    );
    expect(find.byType(FoodDetailScreen), findsOneWidget);
    await _press(tester, find.text('Undo'));
    final MealPlanEntryRow after = await db
        .select(db.mealPlanEntries)
        .getSingle();
    expect(after.copyWith(updatedAt: before.updatedAt), before);
    expect(find.text('Change undone.').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final String identity in <String>['account', 'household']) {
    testWidgets('$identity change and return permanently expire the old Undo', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures.allOn;
      String user = 'local-user';
      String home = 'local-household';
      final HearthDatabase db = await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.today,
        readPlanEntriesFromStore: true,
        foods: <Food>[_food()],
        entries: <MealPlanEntry>[_entry(logged: false)],
        extraOverrides: <Object>[
          currentUserIdProvider.overrideWith((Ref ref) => user),
          currentHouseholdIdProvider.overrideWith((Ref ref) => home),
        ],
      );
      final ProviderContainer container = _container(tester);
      await _press(tester, find.byKey(_toggle));
      final MealPlanEntryRow logged = await db
          .select(db.mealPlanEntries)
          .getSingle();
      final List<PendingWriteRow> queued = await db
          .select(db.pendingWrites)
          .get();
      if (identity == 'account') {
        user = 'other';
        container.invalidate(currentUserIdProvider);
      } else {
        home = 'other';
        container.invalidate(currentHouseholdIdProvider);
      }
      await pumpFrames(tester);
      user = 'local-user';
      home = 'local-household';
      container.invalidate(currentUserIdProvider);
      container.invalidate(currentHouseholdIdProvider);
      await pumpFrames(tester);
      await _press(tester, find.text('Undo'));
      expect(await db.select(db.mealPlanEntries).getSingle(), logged);
      expect(await db.select(db.pendingWrites).get(), queued);
      expect(
        find.textContaining('This action expired.').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Change undone.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rapid and held callbacks cannot log again after Undo', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[_entry(logged: false)],
    );
    final VoidCallback held = tester
        .widget<IconButton>(find.byKey(_toggle))
        .onPressed!;
    held();
    held();
    await pumpFrames(tester, frames: 25);
    expect((await db.select(db.mealPlanEntries).getSingle()).isLogged, isTrue);
    await _press(tester, find.text('Undo'));
    final List<PendingWriteRow> queued = await db
        .select(db.pendingWrites)
        .get();
    held();
    await pumpFrames(tester, frames: 20);
    expect((await db.select(db.mealPlanEntries).getSingle()).isLogged, isFalse);
    expect(await db.select(db.pendingWrites).get(), queued);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a held toggle refuses a meal corrected since its frame', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[_entry(logged: true)],
    );
    final ProviderContainer container = _container(tester);
    final VoidCallback held = tester
        .widget<IconButton>(find.byKey(_toggle))
        .onPressed!;
    await container
        .read(planRepositoryProvider)
        .logEntry(
          _entryId,
          liveMacros: const Macros(kcal: 1),
          label: 'Ignored',
          portion: 2,
          liveCoverage: const NutrientCoverage.notRecorded(),
        );
    final MealPlanEntryRow corrected = await db
        .select(db.mealPlanEntries)
        .getSingle();
    final List<PendingWriteRow> queued = await db
        .select(db.pendingWrites)
        .get();
    held();
    await pumpFrames(tester, frames: 25);
    expect(await db.select(db.mealPlanEntries).getSingle(), corrected);
    expect(await db.select(db.pendingWrites).get(), queued);
    expect(
      find.text('This meal changed. Nothing was changed.'),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Undo explains a later correction without overwriting it', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.today,
      readPlanEntriesFromStore: true,
      foods: <Food>[_food()],
      entries: <MealPlanEntry>[_entry(logged: false)],
    );
    final ProviderContainer container = _container(tester);
    await _press(tester, find.byKey(_toggle));
    await container
        .read(planRepositoryProvider)
        .logEntry(
          _entryId,
          liveMacros: const Macros(kcal: 1),
          label: 'Ignored',
          portion: 2,
          liveCoverage: const NutrientCoverage.notRecorded(),
        );
    final MealPlanEntryRow corrected = await db
        .select(db.mealPlanEntries)
        .getSingle();
    final List<PendingWriteRow> queued = await db
        .select(db.pendingWrites)
        .get();
    await _press(tester, find.text('Undo'));
    expect(await db.select(db.mealPlanEntries).getSingle(), corrected);
    expect(await db.select(db.pendingWrites).get(), queued);
    expect(
      find.text('Cannot undo: this meal changed.').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Change undone.'), findsNothing);
  });

  for (final String failsAt in <String>['action', 'Undo']) {
    testWidgets(
      '$failsAt failure keeps a safe Retry and reports success only after commit',
      (WidgetTester tester) async {
        late _Queue queue;
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          readPlanEntriesFromStore: true,
          foods: <Food>[_food()],
          entries: <MealPlanEntry>[_entry(logged: true)],
          extraOverrides: <Object>[
            planRepositoryProvider.overrideWith((Ref ref) {
              final HearthDatabase db = ref.read(databaseProvider);
              queue = _Queue(db);
              return PlanRepository(
                database: db,
                store: PlanStore(db),
                queue: queue,
                userId: ref.read(currentUserIdProvider),
              );
            }),
          ],
        );
        final MealPlanEntryRow before = await db
            .select(db.mealPlanEntries)
            .getSingle();
        if (failsAt == 'action') queue.failures = 1;
        await _press(tester, find.byKey(_toggle));
        if (failsAt == 'action') {
          expect(await db.select(db.mealPlanEntries).getSingle(), before);
          expect(find.text('Meal unlogged.'), findsNothing);
          await _press(tester, find.text('Retry'));
        } else {
          queue.failures = 1;
        }
        final MealPlanEntryRow unlogged = await db
            .select(db.mealPlanEntries)
            .getSingle();
        expect(unlogged.isLogged, isFalse);
        await _press(tester, find.text('Undo'));
        if (failsAt == 'Undo') {
          expect(await db.select(db.mealPlanEntries).getSingle(), unlogged);
          expect(find.text('Change undone.'), findsNothing);
          await _press(tester, find.text('Retry'));
        }
        final MealPlanEntryRow restored = await db
            .select(db.mealPlanEntries)
            .getSingle();
        expect(restored.copyWith(updatedAt: before.updatedAt), before);
        expect(find.text('Change undone.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool failFirst in <bool>[false, true]) {
    testWidgets(
      '${failFirst ? "A failed" : "A successful"} action finishing after Day removal keeps its action',
      (WidgetTester tester) async {
        late _Queue queue;
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          readPlanEntriesFromStore: true,
          foods: <Food>[_food()],
          entries: <MealPlanEntry>[_entry(logged: false)],
          extraOverrides: <Object>[
            planRepositoryProvider.overrideWith((Ref ref) {
              final HearthDatabase db = ref.read(databaseProvider);
              queue = _Queue(db);
              return PlanRepository(
                database: db,
                store: PlanStore(db),
                queue: queue,
                userId: ref.read(currentUserIdProvider),
              );
            }),
          ],
        );
        queue.failures = failFirst ? 1 : 0;
        queue.gate = Completer<void>();
        await _press(tester, find.byKey(_toggle));
        expect(queue.waiting, isTrue);
        final NavigatorState navigator = Navigator.of(
          tester.element(find.byType(DayScreen)),
        );
        unawaited(
          navigator.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  const Scaffold(body: Center(child: Text('Another screen'))),
            ),
          ),
        );
        await pumpFrames(tester, frames: 20);
        expect(find.byType(DayScreen), findsNothing);
        queue.gate!.complete();
        queue.gate = null;
        await pumpFrames(tester, frames: 30);
        if (failFirst) {
          expect(
            (await db.select(db.mealPlanEntries).getSingle()).isLogged,
            isFalse,
          );
          await _press(tester, find.text('Retry'));
        }
        expect(
          (await db.select(db.mealPlanEntries).getSingle()).isLogged,
          isTrue,
        );
        await _press(tester, find.text('Undo'));
        expect(
          (await db.select(db.mealPlanEntries).getSingle()).isLogged,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool logged in <bool>[false, true]) {
    testWidgets(
      '${logged ? 'Unlog' : 'Log'} offers Undo that restores the exact prior meal',
      (WidgetTester tester) async {
        final HearthDatabase db = await pumpHearthApp(
          tester,
          launchTarget: LaunchTarget.today,
          readPlanEntriesFromStore: true,
          foods: <Food>[_food()],
          entries: <MealPlanEntry>[_entry(logged: logged)],
        );
        final MealPlanEntryRow before =
            (await db.select(db.mealPlanEntries).get()).single;
        await _press(tester, find.byKey(_toggle));
        expect(
          (await db.select(db.mealPlanEntries).get()).single.isLogged,
          !logged,
        );
        await _press(tester, find.text('Undo'));
        final MealPlanEntryRow after =
            (await db.select(db.mealPlanEntries).get()).single;
        expect(after.isLogged, before.isLogged);
        expect(after.isPlanned, before.isPlanned);
        expect(after.servings, before.servings);
        expect(after.servingOptionId, before.servingOptionId);
        expect(after.macroSnapshot, before.macroSnapshot);
        expect(after.loggedAt, before.loggedAt);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
