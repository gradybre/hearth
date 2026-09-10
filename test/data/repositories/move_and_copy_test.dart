import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';

/// Correcting a meal filed to the wrong day, and repeating one (review N02).
///
/// Until now the entry sheet offered two things: change the portion, or
/// remove it. So a lunch logged to Sunday when it was eaten on Saturday had
/// to be deleted and logged again — and logging again freezes *today's*
/// definition of the food over what was actually eaten, which is the one
/// thing non-negotiable 3 exists to prevent. Correcting a date must not be a
/// way to rewrite nutrition.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late PlanRepository repository;
  DateTime clock = DateTime.utc(2026, 8, 27, 18, 30);
  int nextId = 0;

  // Thursday, and the Saturday two days after it.
  final DateTime thursday = DateTime(2026, 8, 27);
  final DateTime saturday = DateTime(2026, 8, 29);

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

  const Macros perServing = Macros(
    kcal: 300,
    proteinG: 20,
    carbG: 30,
    fatG: 10,
  );

  /// A meal eaten on Thursday lunchtime, two servings of it.
  Future<MealPlanEntry> logLunch() => repository.add(
    date: thursday,
    slot: MealSlot.lunch,
    refType: PlanRefType.food,
    refId: 'f-1',
    servings: 2,
    loggedMacros: perServing,
    loggedCoverage: NutrientCoverage.ofOne(perServing),
    label: '1 bowl',
  );

  group('moving a meal to the day it was eaten on', () {
    test('carries the frozen snapshot, not a fresh one', () async {
      // The whole point. `add` would re-cost from the food as it stands now;
      // this is the same record, filed differently.
      final MealPlanEntry logged = await logLunch();
      final MacroSnapshot? before = logged.macroSnapshot;

      final MealPlanEntry moved = await repository.move(
        logged,
        date: saturday,
        slot: MealSlot.dinner,
      );

      expect(moved.id, logged.id, reason: 'a move is not a new record');
      expect(moved.macroSnapshot?.macros, before?.macros);
      expect(moved.macroSnapshot?.capturedAt, before?.capturedAt);
      expect(moved.servings, 2);
      expect(moved.isLogged, isTrue);
    });

    test('and files it under the new day and slot', () async {
      final MealPlanEntry logged = await logLunch();

      await repository.move(logged, date: saturday, slot: MealSlot.dinner);

      expect(await repository.entriesFor(thursday), isEmpty);
      final List<MealPlanEntry> after = await repository.entriesFor(saturday);
      expect(after.single.id, logged.id);
      expect(after.single.slot, MealSlot.dinner);
    });

    test('re-dating when it was eaten, and keeping the time of day', () async {
      // Otherwise the entry is filed under Saturday while its own timestamp
      // says Thursday, and everything that reads one disagrees with
      // everything that reads the other.
      final MealPlanEntry logged = await logLunch();
      final DateTime was = logged.loggedAt!.toLocal();

      final MealPlanEntry moved = await repository.move(
        logged,
        date: saturday,
        slot: MealSlot.dinner,
      );

      final DateTime now = moved.loggedAt!.toLocal();
      expect(dayKey(now), dayKey(saturday));
      expect(now.hour, was.hour);
      expect(now.minute, was.minute);
    });

    test('a planned meal moves without acquiring a timestamp', () async {
      // Nothing has been eaten, so there is no moment to correct.
      final MealPlanEntry planned = await repository.add(
        date: thursday,
        slot: MealSlot.lunch,
        refType: PlanRefType.recipe,
        refId: 'r-1',
        servings: 1,
      );

      final MealPlanEntry moved = await repository.move(
        planned,
        date: saturday,
        slot: MealSlot.breakfast,
      );

      expect(moved.loggedAt, isNull);
      expect(moved.isPlanned, isTrue);
      expect(moved.macroSnapshot, isNull);
    });

    test('and the move reaches the other phone', () async {
      // A move that never leaves this device is a meal on two days.
      final MealPlanEntry logged = await logLunch();
      // Drained rather than cleared, so what is counted afterwards is what
      // the move queued and not what logging it did.
      for (final PendingWrite write in await queue.pending(now: clock)) {
        await queue.markSynced(write.sequence);
      }

      await repository.move(logged, date: saturday, slot: MealSlot.dinner);

      final List<PendingWrite> pending = await queue.pending(now: clock);
      expect(
        pending.any(
          (PendingWrite w) =>
              w.entityTable == 'meal_plan_entries' && w.entityId == logged.id,
        ),
        isTrue,
        reason: 'the moved entry was never queued',
      );
      expect(
        pending.any((PendingWrite w) => w.entityTable == 'meal_plan_days'),
        isTrue,
        reason:
            'the destination day is a foreign key the server has never seen',
      );
    });
  });

  group('planning the same meal again', () {
    test('makes a planned entry, with no snapshot to inherit', () async {
      // A copy is a meal nobody has eaten. Snapshots freeze at log time and
      // at no other time, so carrying one forward would give that column a
      // second meaning.
      final MealPlanEntry logged = await logLunch();

      final MealPlanEntry copy = await repository.copyAsPlanned(
        logged,
        date: saturday,
        slot: MealSlot.dinner,
      );

      expect(copy.id, isNot(logged.id));
      expect(copy.isPlanned, isTrue);
      expect(copy.isLogged, isFalse);
      expect(copy.macroSnapshot, isNull);
      expect(copy.loggedAt, isNull);
    });

    test('keeping what and how much, on the day asked for', () async {
      final MealPlanEntry logged = await logLunch();

      final MealPlanEntry copy = await repository.copyAsPlanned(
        logged,
        date: saturday,
        slot: MealSlot.dinner,
      );

      expect(copy.refType, logged.refType);
      expect(copy.refId, logged.refId);
      expect(copy.servings, 2);
      expect((await repository.entriesFor(saturday)).single.id, copy.id);
    });

    test('and leaves the original exactly where it was', () async {
      final MealPlanEntry logged = await logLunch();

      await repository.copyAsPlanned(
        logged,
        date: saturday,
        slot: MealSlot.dinner,
      );

      final MealPlanEntry still = (await repository.entriesFor(thursday))
          .single;
      expect(still.id, logged.id);
      expect(still.isLogged, isTrue);
      expect(still.macroSnapshot?.macros, logged.macroSnapshot?.macros);
    });
  });
}
