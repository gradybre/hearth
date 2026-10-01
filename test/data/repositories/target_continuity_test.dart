import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/target_schedule.dart';
import 'package:hearth/domain/planning/week.dart';

const MacroTargets initial = MacroTargets(
  kcal: 2100.5,
  proteinG: 145.25,
  carbG: 225.75,
  fatG: 70.5,
  fiberG: 0,
  sodiumMg: null,
  cholesterolMg: 225.25,
);
const MacroTargets revised = MacroTargets(
  kcal: 2300,
  proteinG: 160,
  carbG: 260,
  fatG: 75,
  fiberG: null,
  sodiumMg: 0,
  cholesterolMg: null,
);
const MacroTargets exception = MacroTargets(
  kcal: 1900,
  proteinG: 125,
  carbG: 210,
  fatG: 60,
  fiberG: 28,
  sodiumMg: 1800,
  cholesterolMg: 0,
);

class FailingQueue extends PendingWriteStore {
  FailingQueue(super.db, {required this.failForTable});

  final String failForTable;

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
    if (entityTable == failForTable) throw StateError('Queue unavailable');
  }
}

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late PlanRepository repository;
  late DateTime now;
  final DateTime firstMonday = DateTime(2026, 9, 21);
  final DateTime currentMonday = DateTime(2026, 9, 28);

  PlanRepository forUser(String userId, {PendingWriteStore? writeQueue}) =>
      PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: writeQueue ?? queue,
        userId: userId,
        clock: () => now,
        idFactory: () => 'unused-random-id',
      );

  setUp(() {
    now = DateTime(2026, 9, 28, 12);
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = forUser('alice');
  });

  tearDown(() => db.close());

  test(
    'an exact week stays private and never opts into ongoing targets',
    () async {
      await repository.setTargets(currentMonday, initial);

      expect(
        (await repository.targetResolutionFor(currentMonday)).source,
        TargetSource.exactWeek,
      );
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), isNull);
      expect(await forUser('bob').targetsFor(currentMonday), isNull);
      expect(await db.select(db.ongoingMacroTargets).get(), isEmpty);
    },
  );

  test(
    'ongoing targets persist after closing and reopening the database',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'hearth-target-continuity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final File file = File('${directory.path}/targets.sqlite');

      PlanRepository on(HearthDatabase database) => PlanRepository(
        database: database,
        store: PlanStore(database),
        queue: PendingWriteStore(database),
        userId: 'alice',
        clock: () => now,
      );
      final HearthDatabase first = HearthDatabase.forTesting(
        NativeDatabase(file),
      );
      try {
        await on(first).setOngoingTargets(currentMonday, initial);
      } finally {
        await first.close();
      }
      final HearthDatabase reopened = HearthDatabase.forTesting(
        NativeDatabase(file),
      );
      addTearDown(reopened.close);

      final ResolvedTargets result = await on(reopened)
          .targetResolutionFor(DateTime(2027, 2, 3));
      expect(result.targets, initial);
      expect(result.source, TargetSource.ongoing);
      expect(result.ongoingBoundary!.weekStart, currentMonday);
      expect(await PendingWriteStore(reopened).count(), 1);
      expect(await reopened.select(reopened.macroTargets).get(), isEmpty);
    },
  );

  test('new ongoing saves store one boundary with all seven values', () async {
    await repository.setOngoingTargets(DateTime(2026, 10, 1, 19), initial);

    final OngoingMacroTargetRow row =
        (await db.select(db.ongoingMacroTargets).get()).single;
    final PendingWrite write = (await queue.pending()).single;
    expect(row.weekStartDate, currentMonday);
    expect(PlanMapper.ongoingTargetToDomain(row).targets, initial);
    expect(write.entityTable, 'ongoing_macro_targets');
    expect(write.entityId, row.id);
    expect(write.operation, WriteOperation.upsert);
    expect(write.payload, <String, Object?>{
      'id': row.id,
      'user_id': 'alice',
      'week_start_date': '2026-09-28',
      'is_stopped': false,
      'kcal': 2100.5,
      'protein_g': 145.25,
      'carb_g': 225.75,
      'fat_g': 70.5,
      'fiber_g': 0.0,
      'sodium_mg': null,
      'cholesterol_mg': 225.25,
      'updated_at': now.toUtc().toIso8601String(),
    });
    expect(await repository.targetsFor(firstMonday), isNull);
    for (int week = 0; week < 53; week++) {
      expect(
        await repository.targetsFor(addDays(currentMonday, 7 * week)),
        initial,
      );
    }
    expect(await db.select(db.macroTargets).get(), isEmpty);
    expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
    expect(await queue.count(), 1);
  });

  test(
    'enabling ongoing updates an existing current exception together',
    () async {
      await repository.setTargets(currentMonday, exception);
      final String originalId =
          (await db.select(db.macroTargets).get()).single.id;
      await repository.setOngoingTargets(currentMonday, initial);

      final ResolvedTargets result = await repository.targetResolutionFor(
        currentMonday,
      );
      expect(result.source, TargetSource.exactWeek);
      expect(result.targets, initial);
      expect(result.ongoingBoundary!.targets, initial);
      expect((await db.select(db.macroTargets).get()).single.id, originalId);
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), initial);
      final List<PendingWrite> writes = await queue.pending();
      expect(writes, hasLength(2));
      expect(
        writes.map((PendingWrite write) => write.entityTable),
        containsAll(<String>['macro_targets', 'ongoing_macro_targets']),
      );
      expect(
        writes.every((PendingWrite write) => write.payload['kcal'] == 2100.5),
        isTrue,
      );
    },
  );

  test(
    'past and future exceptions leave ongoing history and resumption intact',
    () async {
      now = DateTime(2026, 9, 21, 12);
      await repository.setOngoingTargets(firstMonday, initial);
      now = DateTime(2026, 9, 28, 12);
      await repository.setOngoingTargets(currentMonday, revised);
      await repository.setTargets(DateTime(2026, 9, 24), exception);
      await repository.setTargets(DateTime(2026, 10, 15), exception);

      expect(await repository.targetsFor(firstMonday), exception);
      expect(await repository.targetsFor(currentMonday), revised);
      expect(await repository.targetsFor(DateTime(2026, 10, 12)), exception);
      expect(await repository.targetsFor(DateTime(2026, 10, 19)), revised);
      expect(
        (await repository.targetResolutionFor(firstMonday))
            .ongoingBoundary!
            .targets,
        initial,
      );
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(2));
    },
  );

  test(
    'stopping preserves this week and future exceptions until restart',
    () async {
      now = DateTime(2026, 9, 21, 12);
      await repository.setOngoingTargets(firstMonday, initial);
      await repository.setTargets(DateTime(2026, 10, 12), exception);
      now = DateTime(2026, 9, 28, 12);
      await repository.stopOngoingTargets(DateTime(2026, 10, 1));

      final ResolvedTargets stopped = await repository.targetResolutionFor(
        currentMonday,
      );
      expect(stopped.source, TargetSource.exactWeek);
      expect(stopped.targets, initial);
      expect(stopped.ongoingBoundary!.isStopped, isTrue);
      expect(await repository.targetsFor(firstMonday), initial);
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), isNull);
      expect(await repository.targetsFor(DateTime(2026, 10, 12)), exception);
      expect(await repository.targetsFor(DateTime(2026, 10, 19)), isNull);

      final PendingWrite stop = (await queue.pending()).singleWhere(
        (PendingWrite write) =>
            write.entityTable == 'ongoing_macro_targets' &&
            write.payload['is_stopped'] == true,
      );
      expect(stop.payload['week_start_date'], '2026-09-28');
      for (final String field in <String>[
        'kcal',
        'protein_g',
        'carb_g',
        'fat_g',
        'fiber_g',
        'sodium_mg',
        'cholesterol_mg',
      ]) {
        expect(stop.payload.containsKey(field), isTrue);
        expect(stop.payload[field], isNull);
      }

      now = DateTime(2026, 10, 26, 12);
      await repository.setOngoingTargets(now, revised);
      expect(await repository.targetsFor(DateTime(2026, 11, 2)), revised);
      expect(await repository.targetsFor(firstMonday), initial);
      expect(await repository.targetsFor(currentMonday), initial);
      expect(await repository.targetsFor(DateTime(2026, 10, 19)), isNull);
      expect(await db.select(db.macroTargets).get(), hasLength(2));
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(3));
    },
  );

  test(
    'stopping preserves the current exception instead of the fallback',
    () async {
      await repository.setOngoingTargets(currentMonday, initial);
      await repository.setTargets(currentMonday, exception);
      await repository.stopOngoingTargets(currentMonday);

      expect(await repository.targetsFor(currentMonday), exception);
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), isNull);
    },
  );

  test(
    'stopping without targets writes no made-up exact-week values',
    () async {
      await repository.stopOngoingTargets(currentMonday);

      expect(await repository.targetsFor(currentMonday), isNull);
      expect(await db.select(db.macroTargets).get(), isEmpty);
      expect(
        (await db.select(db.ongoingMacroTargets).get()).single.isStopped,
        isTrue,
      );
      expect(await queue.count(), 1);
    },
  );

  test('current-week changes cannot start in a past or future week', () async {
    for (final DateTime invalid in <DateTime>[
      firstMonday,
      DateTime(2026, 10, 5),
    ]) {
      await expectLater(
        repository.setOngoingTargets(invalid, initial),
        throwsArgumentError,
      );
      await expectLater(
        repository.stopOngoingTargets(invalid),
        throwsArgumentError,
      );
    }
    expect(await db.select(db.ongoingMacroTargets).get(), isEmpty);
    expect(await db.select(db.macroTargets).get(), isEmpty);
    expect(await queue.count(), 0);
  });

  test(
    'the current week comes from the clock local calendar, including Sunday',
    () async {
      // The clock is an instant; persisted/effective weeks are calendar keys.
      // In New York this UTC instant is already Monday by UTC but still Sunday
      // locally. Converting the clock to local time keeps the intended week.
      now = DateTime(2026, 10, 4, 23, 59).toUtc();
      await repository.setOngoingTargets(currentMonday, initial);
      now = DateTime(2026, 10, 5, 0, 1).toUtc();
      await expectLater(
        repository.setOngoingTargets(currentMonday, revised),
        throwsArgumentError,
      );
      await repository.setOngoingTargets(DateTime(2026, 10, 5), revised);
      expect(await repository.targetsFor(currentMonday), initial);
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), revised);
    },
  );

  test(
    'two people keep independent ongoing choices and exact exceptions',
    () async {
      final PlanRepository bob = forUser('bob');
      await repository.setOngoingTargets(currentMonday, initial);
      await bob.setOngoingTargets(currentMonday, revised);
      await bob.setTargets(currentMonday, exception);
      await repository.stopOngoingTargets(currentMonday);

      expect(await repository.targetsFor(currentMonday), initial);
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), isNull);
      expect(await bob.targetsFor(currentMonday), exception);
      expect(await bob.targetsFor(DateTime(2026, 10, 5)), revised);
      expect(
        await forUser('charlie').targetsFor(DateTime(2026, 10, 5)),
        isNull,
      );
    },
  );

  test(
    'two devices derive the same distinct ongoing user/week identity',
    () async {
      await repository.setOngoingTargets(currentMonday, initial);
      final String firstId = (await queue.pending()).single.entityId;
      final HearthDatabase other = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(other.close);
      final PendingWriteStore otherQueue = PendingWriteStore(other);
      await PlanRepository(
        database: other,
        store: PlanStore(other),
        queue: otherQueue,
        userId: 'alice',
        clock: () => now,
        idFactory: () => 'different-device-random-id',
      ).setOngoingTargets(DateTime(2026, 10, 1), revised);

      expect((await otherQueue.pending()).single.entityId, firstId);
      expect(firstId, PlanStore.ongoingIdFor('alice', currentMonday));
      expect(firstId, isNot(PlanStore.idFor('alice', currentMonday)));
      expect(firstId, isNot(PlanStore.ongoingIdFor('bob', currentMonday)));
      expect(firstId, isNot(PlanStore.ongoingIdFor('alice', firstMonday)));
    },
  );

  test(
    'same-week revise, stop and restart keep one stable boundary identity',
    () async {
      await repository.setOngoingTargets(currentMonday, initial);
      final String id =
          (await db.select(db.ongoingMacroTargets).get()).single.id;
      await repository.setOngoingTargets(currentMonday, revised);
      await repository.stopOngoingTargets(currentMonday);
      await repository.setOngoingTargets(currentMonday, exception);

      final OngoingMacroTargetRow row =
          (await db.select(db.ongoingMacroTargets).get()).single;
      expect(row.id, id);
      expect(row.isStopped, isFalse);
      expect(PlanMapper.ongoingTargetToDomain(row).targets, exception);
      expect(await repository.targetsFor(currentMonday), exception);
      expect(
        (await queue.pending()).where(
          (PendingWrite write) => write.entityTable == 'ongoing_macro_targets',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a failed ongoing queue write restores the exact row and old outbox',
    () async {
      await repository.setTargets(currentMonday, exception);
      final PendingWrite previous = (await queue.pending()).single;
      final PlanRepository failing = forUser(
        'alice',
        writeQueue: FailingQueue(db, failForTable: 'ongoing_macro_targets'),
      );

      await expectLater(
        failing.setOngoingTargets(currentMonday, initial),
        throwsStateError,
      );
      expect(await repository.targetsFor(currentMonday), exception);
      expect(await db.select(db.ongoingMacroTargets).get(), isEmpty);
      final PendingWrite after = (await queue.pending()).single;
      expect(after.sequence, previous.sequence);
      expect(after.payload, previous.payload);
    },
  );

  test(
    'a failed stop rolls back its preserved week, boundary and queue',
    () async {
      now = DateTime(2026, 9, 21, 12);
      await repository.setOngoingTargets(firstMonday, initial);
      final PendingWrite previous = (await queue.pending()).single;
      now = DateTime(2026, 9, 28, 12);
      final PlanRepository failing = forUser(
        'alice',
        writeQueue: FailingQueue(db, failForTable: 'ongoing_macro_targets'),
      );

      await expectLater(
        failing.stopOngoingTargets(currentMonday),
        throwsStateError,
      );
      expect(await repository.targetsFor(DateTime(2026, 10, 5)), initial);
      expect(await db.select(db.macroTargets).get(), isEmpty);
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
      expect((await queue.pending()).single.payload, previous.payload);
    },
  );

  test(
    'an observer refreshes for remote changes in either target table',
    () async {
      final StreamIterator<int> observer = StreamIterator<int>(
        repository.watchTargetChanges(),
      );
      addTearDown(observer.cancel);
      expect(await observer.moveNext(), isTrue);
      final int initialRevision = observer.current;

      // Direct store writes stand in for remote apply: there is no local
      // outbox or meal-plan edit to invalidate a screen incidentally.
      await PlanStore(db).setOngoingTarget(
        boundary: OngoingTargetBoundary.active(
          userId: 'alice',
          weekStart: currentMonday,
          targets: initial,
        ),
        updatedAt: now,
      );
      expect(await observer.moveNext(), isTrue);
      final int ongoingRevision = observer.current;
      expect(ongoingRevision, greaterThan(initialRevision));
      expect(await repository.targetsFor(currentMonday), initial);

      await (db.update(db.ongoingMacroTargets)
            ..where(($OngoingMacroTargetsTable t) => t.userId.equals('alice')))
          .write(
            const OngoingMacroTargetsCompanion(kcal: Value<double?>(2400)),
          );
      expect(await observer.moveNext(), isTrue);
      expect(observer.current, greaterThan(ongoingRevision));
      expect((await repository.targetsFor(currentMonday))!.kcal, 2400);

      await PlanStore(db).setTargets(
        userId: 'alice',
        date: currentMonday,
        targets: exception,
        idFactory: () => 'unused',
        updatedAt: now,
      );
      expect(await observer.moveNext(), isTrue);
      final int exactRevision = observer.current;
      expect(await repository.targetsFor(currentMonday), exception);
      await (db.update(db.macroTargets)
            ..where(($MacroTargetsTable t) => t.userId.equals('alice')))
          .write(const MacroTargetsCompanion(fiberG: Value<double?>(null)));
      expect(await observer.moveNext(), isTrue);
      expect(observer.current, greaterThan(exactRevision));
      expect((await repository.targetsFor(currentMonday))!.fiberG, isNull);
      expect(await queue.count(), 0);
    },
  );

  test(
    'another person writing targets produces no observer revision',
    () async {
      final List<int> revisions = <int>[];
      final Completer<void> initialEmission = Completer<void>();
      final Completer<void> ownEmission = Completer<void>();
      final StreamSubscription<int> subscription = repository
          .watchTargetChanges()
          .listen((int revision) {
            revisions.add(revision);
            if (!initialEmission.isCompleted) initialEmission.complete();
            if (revisions.length == 2 && !ownEmission.isCompleted) {
              ownEmission.complete();
            }
          });
      addTearDown(subscription.cancel);
      await initialEmission.future;

      await forUser('bob').setOngoingTargets(currentMonday, revised);
      await forUser('bob').setTargets(currentMonday, exception);
      // Drain asynchronous Drift query invalidations before checking silence.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(revisions, <int>[1]);

      await repository.setOngoingTargets(currentMonday, initial);
      await ownEmission.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(revisions, <int>[1, 2]);
    },
  );
}
