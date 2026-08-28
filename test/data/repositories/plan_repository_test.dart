import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

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
}
