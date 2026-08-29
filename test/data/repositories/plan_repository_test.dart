import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late PlanRepository repository;
  DateTime clock = DateTime.utc(2026, 8, 27, 18, 30);
  int nextId = 0;

  // Thursday.
  final DateTime today = DateTime(2026, 8, 27);

  setUp(() {
    clock = DateTime.utc(2026, 8, 27, 18, 30);
    nextId = 0;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: queue,
      userId: 'user-1',
      clock: () => clock,
      idFactory: () => 'id-${nextId++}',
    );
  });

  tearDown(() => db.close());

  group('planning', () {
    test('an added entry is planned, not logged', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );

      expect(entry.isPlanned, isTrue);
      expect(entry.isLogged, isFalse);
      expect(entry.macroSnapshot, isNull);
      expect(await repository.entriesFor(today), hasLength(1));
    });

    test('the day row is created lazily on first use', () async {
      expect(await repository.entriesFor(today), isEmpty);
      await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 1,
      );
      expect(await repository.entriesFor(today), hasLength(1));
    });

    test('entries land on the day they were added to, not today', () async {
      // Backdating: any day is editable (spec §5.6).
      final DateTime yesterday = DateTime(2026, 8, 26);
      await repository.add(
        date: yesterday,
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 1,
      );

      expect(await repository.entriesFor(yesterday), hasLength(1));
      expect(await repository.entriesFor(today), isEmpty);
    });
  });

  group('logging freezes history (spec §4)', () {
    test('logging without a plan is a first-class path', () async {
      // Eating something unplanned must not require inventing a plan first.
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.snack,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 2,
        loggedMacros: const Macros(kcal: 100, proteinG: 17),
        label: 'Greek yogurt',
      );

      expect(entry.isLogged, isTrue);
      expect(entry.macroSnapshot!.macros.kcal, 200);
      expect(entry.macroSnapshot!.servings, 2);
      expect(entry.macroSnapshot!.label, 'Greek yogurt');
    });

    test(
      'confirming a planned entry is one call and freezes the snapshot',
      () async {
        final MealPlanEntry planned = await repository.add(
          date: today,
          slot: MealSlot.dinner,
          refType: PlanRefType.recipe,
          refId: 'recipe-1',
          servings: 1,
        );

        final MealPlanEntry? logged = await repository.logEntry(
          planned.id,
          liveMacros: const Macros(kcal: 938, proteinG: 98, fatG: 60),
          label: 'Braised short ribs',
        );

        expect(logged!.isLogged, isTrue);
        expect(logged.loggedAt, clock);
        expect(logged.macroSnapshot!.macros.kcal, 938);
      },
    );

    test('the portion can be adjusted at log time', () async {
      final MealPlanEntry planned = await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );

      final MealPlanEntry? logged = await repository.logEntry(
        planned.id,
        liveMacros: const Macros(kcal: 400),
        label: 'Dinner',
        portion: 0.5,
      );

      expect(logged!.macroSnapshot!.macros.kcal, 200);
      expect(logged.macroSnapshot!.servings, 0.5);
    });

    test('the snapshot survives a reload from the database', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1.5,
        loggedMacros: const Macros(kcal: 400, proteinG: 30, carbG: 12, fatG: 9),
        label: 'Chicken and rice',
      );

      final MealPlanEntry reloaded = (await repository.entriesFor(today))
          .single;

      expect(reloaded.id, entry.id);
      expect(reloaded.macroSnapshot!.macros.kcal, 600);
      expect(reloaded.macroSnapshot!.macros.proteinG, 45);
      expect(reloaded.macroSnapshot!.servings, 1.5);
      expect(reloaded.macroSnapshot!.label, 'Chicken and rice');
      expect(reloaded.contribution().kcal, 600);
    });

    test('moving a logged entry to another slot never rewrites it', () async {
      final MealPlanEntry logged = await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
        loggedMacros: const Macros(kcal: 400),
        label: 'Dinner',
      );

      await repository.updateEntry(logged.id, slot: MealSlot.lunch);
      final MealPlanEntry moved = (await repository.entriesFor(today)).single;

      expect(moved.slot, MealSlot.lunch);
      expect(moved.macroSnapshot!.macros.kcal, 400);
      expect(moved.macroSnapshot, logged.macroSnapshot);
    });
  });

  group('sync queue', () {
    test('adding queues the day and the entry', () async {
      await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );

      final List<PendingWrite> pending = await queue.pending();
      expect(
        pending.map((PendingWrite w) => w.entityTable),
        containsAll(<String>['meal_plan_days', 'meal_plan_entries']),
      );
    });

    test('the queued log carries the frozen snapshot', () async {
      await repository.add(
        date: today,
        slot: MealSlot.snack,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 1,
        loggedMacros: const Macros(kcal: 100),
        label: 'Yogurt',
      );

      final PendingWrite write = (await queue.pending()).firstWhere(
        (PendingWrite w) => w.entityTable == 'meal_plan_entries',
      );
      final Map<String, Object?> snapshot =
          write.payload['macro_snapshot']! as Map<String, Object?>;

      expect(snapshot['kcal'], 100);
      expect(snapshot['label'], 'Yogurt');
      expect(write.payload['is_logged'], isTrue);
    });

    test('removing an entry queues a delete', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );
      await repository.removeEntry(entry.id);

      expect(await repository.entriesFor(today), isEmpty);
      final PendingWrite write = (await queue.pending()).firstWhere(
        (PendingWrite w) => w.entityId == entry.id,
      );
      expect(write.operation, WriteOperation.delete);
    });
  });

  group('fast entry (spec §5.6)', () {
    test('recents surface what was logged, newest first', () async {
      await repository.add(
        date: today,
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-yogurt',
        servings: 1,
        loggedMacros: const Macros(kcal: 100),
        label: 'Greek yogurt',
      );
      clock = clock.add(const Duration(hours: 1));
      await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 2,
        loggedMacros: const Macros(kcal: 400),
        label: 'Short ribs',
      );

      final List<RecentLog> recents = await repository.recentLogs();
      expect(recents.map((RecentLog r) => r.label), <String>[
        'Short ribs',
        'Greek yogurt',
      ]);
      expect(recents.first.servings, 2);
    });

    test('a planned entry never becomes a recent', () async {
      await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );
      expect(await repository.recentLogs(), isEmpty);
    });

    test('logging again reuses the last portion', () async {
      await repository.add(
        date: today,
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-yogurt',
        servings: 1.5,
        loggedMacros: const Macros(kcal: 100),
        label: 'Greek yogurt',
      );

      final RecentLog recent = (await repository.recentLogs()).single;
      clock = clock.add(const Duration(days: 1));
      final MealPlanEntry repeat = await repository.logAgain(
        recent: recent,
        date: today.add(const Duration(days: 1)),
        slot: MealSlot.breakfast,
        liveMacros: const Macros(kcal: 100),
      );

      expect(repeat.servings, 1.5);
      expect(repeat.isLogged, isTrue);
      expect(repeat.macroSnapshot!.macros.kcal, 150);
    });

    test(
      'logging again records current macros, not the old snapshot',
      () async {
        // Repeating a meal should record what that food is today. If the food's
        // calories were corrected since, the repeat must use the correction.
        await repository.add(
          date: today,
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'food-yogurt',
          servings: 1,
          loggedMacros: const Macros(kcal: 100),
          label: 'Greek yogurt',
        );

        final RecentLog recent = (await repository.recentLogs()).single;
        clock = clock.add(const Duration(days: 1));
        final MealPlanEntry repeat = await repository.logAgain(
          recent: recent,
          date: today.add(const Duration(days: 1)),
          slot: MealSlot.breakfast,
          liveMacros: const Macros(kcal: 130),
        );

        expect(repeat.macroSnapshot!.macros.kcal, 130);
      },
    );

    test('the original log is untouched by the repeat', () async {
      await repository.add(
        date: today,
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-yogurt',
        servings: 1,
        loggedMacros: const Macros(kcal: 100),
        label: 'Greek yogurt',
      );
      final RecentLog recent = (await repository.recentLogs()).single;

      clock = clock.add(const Duration(days: 1));
      await repository.logAgain(
        recent: recent,
        date: today.add(const Duration(days: 1)),
        slot: MealSlot.breakfast,
        liveMacros: const Macros(kcal: 130),
      );

      // Yesterday still says what it always said (spec §4).
      expect(
        (await repository.entriesFor(today)).single.macroSnapshot!.macros.kcal,
        100,
      );
    });
  });

  group('meal-prep assignment (spec §5.6)', () {
    test('one action places a recipe on several days', () async {
      final List<DateTime> days = <DateTime>[
        today,
        today.add(const Duration(days: 1)),
        today.add(const Duration(days: 2)),
      ];

      final List<MealPlanEntry> created = await repository.assignAcrossDays(
        dates: days,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1.5,
      );

      expect(created, hasLength(3));
      for (final DateTime day in days) {
        final MealPlanEntry entry = (await repository.entriesFor(day)).single;
        expect(entry.slot, MealSlot.dinner);
        expect(entry.servings, 1.5);
      }
    });

    test('assigned entries are planned, not logged', () async {
      // A batch you have cooked is not a batch you have eaten.
      await repository.assignAcrossDays(
        dates: <DateTime>[today],
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );

      final MealPlanEntry entry = (await repository.entriesFor(today)).single;
      expect(entry.isLogged, isFalse);
      expect(entry.macroSnapshot, isNull);
    });
  });

  group('copy day (spec §5.6)', () {
    Future<void> seedSource() async {
      await repository.add(
        date: today,
        slot: MealSlot.breakfast,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 1,
        loggedMacros: const Macros(kcal: 100),
        label: 'Yogurt',
      );
      await repository.add(
        date: today,
        slot: MealSlot.dinner,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 2,
      );
    }

    test('copies every entry onto each target day', () async {
      await seedSource();
      final DateTime tomorrow = today.add(const Duration(days: 1));
      final DateTime dayAfter = today.add(const Duration(days: 2));

      final int copied = await repository.copyDay(
        from: today,
        to: <DateTime>[tomorrow, dayAfter],
      );

      expect(copied, 4);
      expect(await repository.entriesFor(tomorrow), hasLength(2));
      expect(await repository.entriesFor(dayAfter), hasLength(2));
    });

    test('copies arrive planned even when the source was logged', () async {
      // Copying Monday's dinner onto Thursday says you intend to eat it
      // again, not that you already have — writing a snapshot would be
      // inventing history (spec §4).
      await seedSource();
      final DateTime tomorrow = today.add(const Duration(days: 1));

      await repository.copyDay(from: today, to: <DateTime>[tomorrow]);

      final List<MealPlanEntry> copies = await repository.entriesFor(tomorrow);
      expect(copies.every((MealPlanEntry e) => !e.isLogged), isTrue);
      expect(
        copies.every((MealPlanEntry e) => e.macroSnapshot == null),
        isTrue,
      );
    });

    test('portions and slots carry across', () async {
      await seedSource();
      final DateTime tomorrow = today.add(const Duration(days: 1));
      await repository.copyDay(from: today, to: <DateTime>[tomorrow]);

      final List<MealPlanEntry> copies = await repository.entriesFor(tomorrow);
      final MealPlanEntry dinner = copies.firstWhere(
        (MealPlanEntry e) => e.slot == MealSlot.dinner,
      );
      expect(dinner.servings, 2);
      expect(dinner.refType, PlanRefType.recipe);
    });

    test('the source day is left alone', () async {
      await seedSource();
      await repository.copyDay(
        from: today,
        to: <DateTime>[today.add(const Duration(days: 1))],
      );

      final List<MealPlanEntry> source = await repository.entriesFor(today);
      expect(source, hasLength(2));
      expect(
        source
            .firstWhere((MealPlanEntry e) => e.slot == MealSlot.breakfast)
            .isLogged,
        isTrue,
      );
    });

    test('copying a day onto itself does nothing', () async {
      await seedSource();
      final int copied = await repository.copyDay(
        from: today,
        to: <DateTime>[today],
      );

      expect(copied, 0);
      expect(await repository.entriesFor(today), hasLength(2));
    });

    test('copying an empty day is a no-op', () async {
      final int copied = await repository.copyDay(
        from: today,
        to: <DateTime>[today.add(const Duration(days: 1))],
      );
      expect(copied, 0);
    });
  });

  group('targets', () {
    const MacroTargets targets = MacroTargets(
      kcal: 2200,
      proteinG: 180,
      carbG: 220,
      fatG: 70,
    );

    test('are stored against the week, not the day', () async {
      await repository.setTargets(today, targets);

      // Thursday's targets are Monday's targets.
      expect(await repository.targetsFor(DateTime(2026, 8, 24)), targets);
      expect(await repository.targetsFor(DateTime(2026, 8, 30)), targets);
    });

    test('do not leak into the next week', () async {
      await repository.setTargets(today, targets);
      expect(await repository.targetsFor(DateTime(2026, 9, 1)), isNull);
    });

    test(
      'setting them twice in a week updates rather than duplicates',
      () async {
        await repository.setTargets(today, targets);
        clock = clock.add(const Duration(hours: 1));
        await repository.setTargets(
          DateTime(2026, 8, 28),
          const MacroTargets(kcal: 2400, proteinG: 180, carbG: 220, fatG: 70),
        );

        expect((await repository.targetsFor(today))!.kcal, 2400);
        final List<PendingWrite> targetWrites = (await queue.pending())
            .where((PendingWrite w) => w.entityTable == 'macro_targets')
            .toList();
        expect(targetWrites, hasLength(1));
      },
    );

    test('an unset week has no targets rather than zeros', () async {
      expect(await repository.targetsFor(today), isNull);
    });
  });

  group('a day is identified by the day, not by chance', () {
    test('two devices derive the same id for the same date', () async {
      // The server keys meal_plan_days on (user_id, day). Random ids would
      // give two devices two rows for the same Tuesday, and the second could
      // never sync — its meals lost to a conflict that never resolves.
      final String a = PlanRepository.dayIdFor(
        userId: 'user-1',
        date: DateTime(2026, 8, 28, 9),
      );
      final String b = PlanRepository.dayIdFor(
        userId: 'user-1',
        date: DateTime(2026, 8, 28, 23, 59),
      );

      expect(a, b, reason: 'the time of day is not part of the identity');
    });

    test('different users and different days do not collide', () {
      final String mine = PlanRepository.dayIdFor(
        userId: 'user-1',
        date: DateTime(2026, 8, 28),
      );
      final String theirs = PlanRepository.dayIdFor(
        userId: 'user-2',
        date: DateTime(2026, 8, 28),
      );
      final String tomorrow = PlanRepository.dayIdFor(
        userId: 'user-1',
        date: DateTime(2026, 8, 29),
      );

      expect(mine, isNot(theirs));
      expect(mine, isNot(tomorrow));
    });

    test('it is a real uuid, because the column is one', () {
      expect(
        PlanRepository.dayIdFor(userId: 'user-1', date: DateTime(2026, 8, 28)),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('the day row a repository creates uses it', () async {
      await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.recipe,
        refId: 'recipe-1',
        servings: 1,
      );

      final List<PendingWrite> writes = await queue.pending();
      final PendingWrite day = writes.firstWhere(
        (PendingWrite w) => w.entityTable == PlanRepository.daysTable,
      );

      expect(
        day.entityId,
        PlanRepository.dayIdFor(userId: 'user-1', date: today),
      );
    });
  });
}
