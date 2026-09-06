import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';

/// Undo puts back exactly what was there (spec §4, R01).
///
/// A logged entry's snapshot is **already multiplied by the portion** — it is
/// what was eaten, not what one serving contains. Undo used to hand that total
/// back through the ordinary logging door, which takes a *per-serving* figure
/// and scales it, so two servings of a 100 kcal meal came back as 400. At one
/// serving the arithmetic is invisible, which is why it survived being used.
///
/// A restored meal is not a new meal. It is the same eating, put back — so it
/// keeps the portion, the slot, the label, the original moment it was eaten,
/// and every one of the seven numbers exactly.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late PlanRepository repository;
  DateTime clock = DateTime.utc(2026, 8, 27, 18, 30);
  int nextId = 0;

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

  /// Logs [servings] portions of something worth [perServing] each.
  Future<MealPlanEntry> logMeal({
    required double servings,
    Macros perServing = const Macros(
      kcal: 100,
      proteinG: 8,
      carbG: 12,
      fatG: 3,
      fiberG: 2.5,
    ),
  }) => repository.add(
    date: today,
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'recipe-1',
    servings: servings,
    loggedMacros: perServing,
    // This test is not about coverage; saying so beats letting the
    // repository infer a completeness nothing checked.
    loggedCoverage: const NutrientCoverage.notRecorded(),
    label: 'Guard stew',
  );

  group('the arithmetic', () {
    test('`add` scales, which is why a total cannot go through it', () async {
      // A characterisation of `add`'s contract rather than a guard: it is
      // green on both sides of the fix, because `add` has not changed and
      // should not. It is here so the next reader can see *why* the old route
      // was wrong without reconstructing it — `loggedMacros` is documented as
      // "the macros for ONE serving", and a frozen snapshot is already a
      // total. The guard against the defect returning is the gesture test in
      // `day_gestures_test.dart`, which fails on the old implementation.
      final MealPlanEntry logged = await logMeal(servings: 2);
      expect(logged.macroSnapshot!.macros.kcal, 200);

      await repository.removeEntry(logged.id);
      final MealPlanEntry viaAdd = await repository.add(
        date: today,
        slot: logged.slot,
        refType: logged.refType,
        refId: logged.refId,
        servings: logged.servings,
        loggedMacros: logged.macroSnapshot!.macros,
        // This test is not about coverage; saying so beats letting the
        // repository infer a completeness nothing checked.
        loggedCoverage: const NutrientCoverage.notRecorded(),
        label: logged.macroSnapshot!.label,
      );

      expect(
        viaAdd.macroSnapshot!.macros.kcal,
        400,
        reason: 'the per-serving door scales what is already a total',
      );
    });
    test('two servings of a 100 kcal meal come back as 200, not 400', () async {
      // The headline case, through the door a restore should use.
      final MealPlanEntry logged = await logMeal(servings: 2);
      expect(logged.macroSnapshot!.macros.kcal, 200);

      await repository.removeEntry(logged.id);
      final MealPlanEntry restored = await repository.restore(logged);

      expect(restored.macroSnapshot!.macros.kcal, 200);
      expect(restored.contribution(), logged.contribution());
    });

    test('and half a serving comes back as half, not a quarter', () async {
      // The same bug in the other direction: below one serving, an Undo
      // *shrank* the meal.
      final MealPlanEntry logged = await logMeal(servings: 0.5);
      expect(logged.macroSnapshot!.macros.kcal, 50);

      await repository.removeEntry(logged.id);
      final MealPlanEntry restored = await repository.restore(logged);

      expect(restored.macroSnapshot!.macros.kcal, 50);
    });

    test('and every one of the seven survives, unknowns included', () async {
      final MealPlanEntry logged = await logMeal(servings: 2);
      await repository.removeEntry(logged.id);
      final MealPlanEntry restored = await repository.restore(logged);

      final Macros back = restored.macroSnapshot!.macros;
      expect(back.proteinG, 16);
      expect(back.carbG, 24);
      expect(back.fatG, 6);
      expect(back.fiberG, 5);
      // Never asked, and still never asked.
      expect(back.sodiumMg, isNull);
      expect(back.cholesterolMg, isNull);
    });
  });

  group('what else a restored meal keeps', () {
    test('the portion, the slot, the label and the day', () async {
      final MealPlanEntry logged = await logMeal(servings: 1.5);
      await repository.removeEntry(logged.id);
      final MealPlanEntry restored = await repository.restore(logged);

      expect(restored.servings, 1.5);
      expect(restored.slot, MealSlot.dinner);
      expect(restored.dayId, logged.dayId);
      expect(restored.macroSnapshot!.label, 'Guard stew');
      expect(restored.isLogged, isTrue);
    });

    test('and the moment it was actually eaten', () async {
      // A new sync mutation timestamp is a different fact from when the meal
      // happened. Restoring at breakfast time must not move last night's
      // dinner to this morning.
      final MealPlanEntry logged = await logMeal(servings: 1);
      final DateTime ateAt = logged.loggedAt!;

      await repository.removeEntry(logged.id);
      clock = clock.add(const Duration(hours: 14));
      final MealPlanEntry restored = await repository.restore(logged);

      expect(restored.loggedAt, ateAt);
      expect(restored.macroSnapshot!.capturedAt, ateAt);
    });

    test('and a planned entry comes back planned, not logged', () async {
      final MealPlanEntry planned = await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'food-1',
        servings: 1,
      );

      await repository.removeEntry(planned.id);
      final MealPlanEntry restored = await repository.restore(planned);

      expect(restored.isLogged, isFalse);
      expect(restored.isPlanned, isTrue);
      expect(restored.macroSnapshot, isNull);
    });
  });

  group('doing it twice', () {
    test('does not leave two meals behind', () async {
      // A double-tap on Undo, or a retried queued action.
      final MealPlanEntry logged = await logMeal(servings: 2);
      await repository.removeEntry(logged.id);

      await repository.restore(logged);
      await repository.restore(logged);

      final List<MealPlanEntry> entries = await repository.entriesFor(today);
      expect(entries, hasLength(1));
      expect(entries.single.macroSnapshot!.macros.kcal, 200);
    });
  });

  group('what the server is told', () {
    test('the delete never leaves, because the undo supersedes it', () async {
      // The comment used to claim the upsert replays *after* the delete. It
      // does not: `enqueue` drops earlier pending writes for the same row, so
      // the delete is superseded and never sent. Same destination, different
      // mechanism — and a later change that leaned on per-entity ordering
      // would have been built on a promise the queue does not make.
      final MealPlanEntry logged = await logMeal(servings: 2);
      await repository.removeEntry(logged.id);
      await repository.restore(logged);

      final List<PendingWrite> queued = await queue.pending();
      final List<PendingWrite> forEntry = queued
          .where((PendingWrite w) => w.entityId == logged.id)
          .toList();

      expect(forEntry, hasLength(1));
      expect(forEntry.single.operation, WriteOperation.upsert);
    });

    test('and what it carries is the total that was eaten', () async {
      final MealPlanEntry logged = await logMeal(servings: 2);
      await repository.removeEntry(logged.id);
      await repository.restore(logged);

      final PendingWrite write = (await queue.pending()).lastWhere(
        (PendingWrite w) => w.entityId == logged.id,
      );

      final Map<String, Object?> snapshot =
          write.payload['macro_snapshot']! as Map<String, Object?>;

      expect(snapshot['kcal'], 200.0);
      expect(snapshot['fiber_g'], 5.0);
      // Never asked, and the queue does not invent an answer either.
      expect(snapshot['sodium_mg'], isNull);
    });
  });
}
