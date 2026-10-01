import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/log_state_change.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

final DateTime _now = DateTime.utc(2026, 10, 1, 12);
const Macros _macros = Macros(
  kcal: 170,
  proteinG: 17,
  carbG: 11,
  fatG: 6,
  fiberG: 3,
  sodiumMg: 42,
  cholesterolMg: 8,
);
final ServingOption _pot = ServingOption(
  id: 'pot',
  label: 'Old 170 g pot',
  amount: Quantity.of(170, Units.gram),
  macros: _macros,
);
const NutrientCoverage _coverage = NutrientCoverage(
  <MinorNutrient, MinorCoverage>{
    MinorNutrient.fiber: MinorCoverage.partial,
    MinorNutrient.sodium: MinorCoverage.complete,
    MinorNutrient.cholesterol: MinorCoverage.notRecorded,
  },
);

class _Queue extends PendingWriteStore {
  _Queue(super.db);
  bool fail = false;
  void Function()? afterEnqueue;

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
    afterEnqueue?.call();
    if (fail) throw StateError('Storage unavailable');
  }
}

class _Fixture {
  _Fixture([HearthDatabase? database])
    : db = database ?? HearthDatabase.forTesting(NativeDatabase.memory()) {
    store = PlanStore(db);
    queue = _Queue(db);
    repo = PlanRepository(
      database: db,
      store: store,
      queue: queue,
      userId: 'me',
      clock: () => _now,
      idFactory: () => 'meal',
    );
  }
  final HearthDatabase db;
  late final PlanStore store;
  late final _Queue queue;
  late final PlanRepository repo;
  final LogStateScope scope = LogStateScope(userId: 'me', householdId: 'home');

  Future<MealPlanEntry> seed({
    bool logged = false,
    LoggedPortion? portion,
  }) async {
    await FoodStore(db).upsert(
      Food(
        id: 'yogurt',
        name: 'Original yogurt',
        servingOptions: <ServingOption>[_pot],
        source: FoodSource.manual,
      ),
      updatedAt: _now,
    );
    final MealPlanEntry entry = await repo.add(
      date: _now,
      slot: MealSlot.lunch,
      refType: PlanRefType.food,
      refId: 'yogurt',
      servings: portion?.servings ?? 1.5,
      servingOptionId: 'pot',
    );
    if (logged) {
      await repo.logEntry(
        entry.id,
        liveMacros: _macros,
        label: 'Name when eaten',
        liveCoverage: _coverage,
        loggedPortion: portion,
        usesApproximatePackage: true,
      );
    }
    return read();
  }

  Future<MealPlanEntry> read() async => (await store.entryById('meal'))!;
  Future<MealPlanEntryRow> raw() => db.select(db.mealPlanEntries).getSingle();
  Future<List<PendingWriteRow>> pending() => db.select(db.pendingWrites).get();
  Future<LogStateChange> toggle(MealPlanEntry expected) async =>
      (await repo.changeLogState(
        expected: expected,
        logged: !expected.isLogged,
        scope: scope,
        liveMacros: _macros,
        label: 'Current name',
        liveCoverage: _coverage,
        usesApproximatePackage: true,
      ))!;
  Future<UndoLogStateResult> undo(LogStateChange receipt) =>
      repo.undoLogState(receipt, scope: scope);
}

void _sameMeal(MealPlanEntryRow actual, MealPlanEntryRow expected) {
  // Sync has a new write time; every part of the actual meal is restored.
  expect(actual.copyWith(updatedAt: expected.updatedAt), expected);
  expect(actual.macroSnapshot, expected.macroSnapshot);
}

void main() {
  late _Fixture f;
  bool closed = false;
  setUp(() {
    f = _Fixture();
    closed = false;
  });
  tearDown(() async {
    if (!closed) await f.db.close();
  });

  Map<String, Object?> withFutureEvidence() => <String, Object?>{
    ...LoggedPortion.tryCapture(
      amount: 1.5,
      unit: PortionUnit.serving(_pot),
      servings: 1.5,
      standard: _pot,
    )!.toJson(),
    'future': <String, Object?>{
      'parts': <Object?>[
        1,
        <String, Object?>{'a': 'first', 'b': true},
        null,
      ],
      'known_null': null,
      'empty': <String, Object?>{},
    },
  };

  Future<LogStateChange> logFutureEvidence() async {
    final MealPlanEntry entry = await f.seed();
    return (await f.repo.changeLogState(
      expected: entry,
      logged: true,
      scope: f.scope,
      liveMacros: _macros,
      label: 'Current name',
      liveCoverage: _coverage,
      loggedPortion: LoggedPortion.fromJson(withFutureEvidence()),
    ))!;
  }

  test(
    'conflicting duplicate JSON members are conservatively content changes',
    () async {
      await f.seed(logged: true);
      await f.store.prepareLogStateTracking();
      final String raw = (await f.raw()).macroSnapshot!;
      final String first =
          '${raw.substring(0, raw.length - 1)},"future":{"a":1,"a":2}}';
      await f.db
          .update(f.db.mealPlanEntries)
          .write(
            MealPlanEntriesCompanion(macroSnapshot: Value<String?>(first)),
          );
      final int revision = (await f.store.logState('meal'))!.revision;
      // Repeating byte-for-byte history remains a no-op, even if ambiguous.
      await f.db
          .update(f.db.mealPlanEntries)
          .write(
            MealPlanEntriesCompanion(macroSnapshot: Value<String?>(first)),
          );
      expect((await f.store.logState('meal'))!.revision, revision);
      final String second = first.replaceFirst('"a":1,"a":2', '"a":2,"a":1');
      expect(
        (jsonDecode(first) as Map<String, Object?>)['future'],
        <String, Object?>{'a': 2},
      );
      expect(
        (jsonDecode(second) as Map<String, Object?>)['future'],
        <String, Object?>{'a': 1},
      );
      await f.db
          .update(f.db.mealPlanEntries)
          .write(
            MealPlanEntriesCompanion(macroSnapshot: Value<String?>(second)),
          );
      expect((await f.store.logState('meal'))!.revision, revision + 1);
    },
  );

  test('whitespace, nested object order and integer/real JSON echoes keep Undo valid', () async {
    final LogStateChange receipt = await logFutureEvidence();
    final int revision = (await f.store.logState('meal'))!.revision;
    Object? reordered(Object? value) => switch (value) {
      Map<String, Object?>() => <String, Object?>{
        for (final String key in value.keys.toList().reversed)
          key: reordered(value[key]),
      },
      List<Object?>() => value.map(reordered).toList(),
      int() => value.toDouble(),
      _ => value,
    };
    final Object? echoed = reordered(
      jsonDecode((await f.raw()).macroSnapshot!),
    );
    await f.db
        .update(f.db.mealPlanEntries)
        .write(
          MealPlanEntriesCompanion(
            macroSnapshot: Value<String?>(
              const JsonEncoder.withIndent('  ').convert(echoed),
            ),
            updatedAt: Value<DateTime>(_now.add(const Duration(seconds: 1))),
          ),
        );
    expect((await f.store.logState('meal'))!.revision, revision);
    expect(await f.undo(receipt), UndoLogStateResult.restored);
  });

  for (final String mutation in <String>[
    'unknown value',
    'array order',
    'missing vs null',
    'empty object vs array',
    'boolean vs number',
    'SQL null vs JSON null',
    'invalid JSON',
  ]) {
    test(
      '$mutation is a content edit even when restored in the same clock tick',
      () async {
        final LogStateChange receipt = await logFutureEvidence();
        final MealPlanEntryRow original = await f.raw();
        final int revision = (await f.store.logState('meal'))!.revision;
        final Map<String, Object?> changed =
            jsonDecode(original.macroSnapshot!) as Map<String, Object?>;
        final Map<String, Object?> portion =
            changed['logged_portion']! as Map<String, Object?>;
        final Map<String, Object?> future =
            portion['future']! as Map<String, Object?>;
        String? raw;
        switch (mutation) {
          case 'unknown value':
            future['extra'] = 'new fact';
            raw = jsonEncode(changed);
          case 'array order':
            future['parts'] = (future['parts']! as List<Object?>).reversed
                .toList();
            raw = jsonEncode(changed);
          case 'missing vs null':
            future.remove('known_null');
            raw = jsonEncode(changed);
          case 'empty object vs array':
            future['empty'] = <Object?>[];
            raw = jsonEncode(changed);
          case 'boolean vs number':
            ((future['parts']! as List<Object?>)[1]!
                    as Map<String, Object?>)['b'] =
                1;
            raw = jsonEncode(changed);
          case 'SQL null vs JSON null':
            await f.db
                .update(f.db.mealPlanEntries)
                .write(
                  const MealPlanEntriesCompanion(
                    macroSnapshot: Value<String?>(null),
                  ),
                );
            final int atNull = (await f.store.logState('meal'))!.revision;
            await f.db
                .update(f.db.mealPlanEntries)
                .write(
                  const MealPlanEntriesCompanion(
                    macroSnapshot: Value<String?>('null'),
                  ),
                );
            expect((await f.store.logState('meal'))!.revision, atNull + 1);
            raw = 'null';
          case 'invalid JSON':
            raw = '{invalid';
        }
        await f.db
            .update(f.db.mealPlanEntries)
            .write(
              MealPlanEntriesCompanion(macroSnapshot: Value<String?>(raw)),
            );
        expect(
          (await f.store.logState('meal'))!.revision,
          greaterThan(revision),
        );
        await f.db
            .into(f.db.mealPlanEntries)
            .insertOnConflictUpdate(original.toCompanion(false));
        final List<PendingWriteRow> queued = await f.pending();
        expect(await f.undo(receipt), UndoLogStateResult.changed);
        expect(await f.raw(), original);
        expect(await f.pending(), queued);
      },
    );
  }

  test('a closed connection expires its receipt instead of offering a storage retry', () async {
    final LogStateChange receipt = await f.toggle(await f.seed());
    await f.db.close();
    closed = true;
    expect(await f.undo(receipt), UndoLogStateResult.expired);
  });

  test('restored logged time is explicit UTC in the sync outbox', () async {
    final MealPlanEntry entry = await f.seed(logged: true);
    final LogStateChange receipt = await f.toggle(entry);
    expect(await f.undo(receipt), UndoLogStateResult.restored);
    final PendingWrite write = (await f.queue.pending()).singleWhere(
      (PendingWrite w) => w.entityTable == PlanRepository.entriesTable,
    );
    expect(
      write.payload['logged_at'],
      entry.loggedAt!.toUtc().toIso8601String(),
    );
  });

  for (final bool logged in <bool>[false, true]) {
    test(
      '${logged ? "Unlog" : "Log"} Undo survives its own server timestamp and JSON echo',
      () async {
        final MealPlanEntry entry = await f.seed(logged: logged);
        final MealPlanEntryRow before = await f.raw();
        final LogStateChange receipt = await f.toggle(entry);
        final List<PendingWrite> queued = await f.queue.pending();
        final PendingWrite action = queued.singleWhere(
          (PendingWrite w) => w.entityTable == PlanRepository.entriesTable,
        );
        for (final PendingWrite write in queued) {
          await f.queue.markSynced(write.sequence);
        }
        final Map<String, Object?> echoed = <String, Object?>{
          ...action.payload,
          'updated_at': _now.add(const Duration(seconds: 1)).toIso8601String(),
        };
        if (echoed['macro_snapshot'] case final Map<String, Object?> snapshot) {
          echoed['macro_snapshot'] = <String, Object?>{
            for (final String key in snapshot.keys.toList().reversed)
              key: snapshot[key],
          };
        }
        await RemoteRows(f.db).applyEntry(echoed);
        expect(await f.undo(receipt), UndoLogStateResult.restored);
        _sameMeal(await f.raw(), before);
      },
    );

    test(
      'a held ${logged ? "Unlog" : "Log"} after a sync tombstone is refused without writes',
      () async {
        final MealPlanEntry entry = await f.seed(logged: logged);
        await RemoteRows(f.db).applyEntry(<String, Object?>{
          'id': entry.id,
          'is_deleted': true,
          'updated_at': _now.toIso8601String(),
        });
        final List<PendingWriteRow> queued = await f.pending();
        expect(
          await f.repo.changeLogState(
            expected: entry,
            logged: !logged,
            scope: f.scope,
            liveMacros: _macros,
            label: 'Stale',
            liveCoverage: _coverage,
          ),
          isNull,
        );
        expect(await f.db.select(f.db.mealPlanEntries).get(), isEmpty);
        expect(await f.pending(), queued);
      },
    );

    test(
      'exact ${logged ? "Unlog" : "Log"} roundtrip and repeated Undo is write-free',
      () async {
        final MealPlanEntry entry = await f.seed(logged: logged);
        final MealPlanEntryRow before = await f.raw();
        final LogStateChange receipt = await f.toggle(entry);
        expect((await f.read()).isLogged, !logged);
        expect(await f.undo(receipt), UndoLogStateResult.restored);
        _sameMeal(await f.raw(), before);
        final List<PendingWriteRow> pending = await f.pending();
        expect(await f.undo(receipt), UndoLogStateResult.alreadyRestored);
        expect(await f.pending(), pending);
      },
    );
  }

  test(
    'Unlog Undo restores a spontaneous log without inventing a plan',
    () async {
      final MealPlanEntry entry = await f.repo.add(
        date: _now,
        slot: MealSlot.snack,
        refType: PlanRefType.recipe,
        refId: 'recipe',
        servings: 1.25,
        loggedMacros: _macros,
        label: 'Unplanned supper',
        loggedCoverage: _coverage,
      );
      expect(entry.isPlanned, isFalse);
      final MealPlanEntryRow before = await f.raw();
      final LogStateChange receipt = await f.toggle(entry);
      expect(await f.undo(receipt), UndoLogStateResult.restored);
      _sameMeal(await f.raw(), before);
      expect((await f.read()).isPlanned, isFalse);
    },
  );

  for (final (String name, double amount, PortionUnit unit)
      in <(String, double, PortionUnit)>[
        ('125 g', 125, const PortionUnit.raw(Units.gram)),
        ('4 oz', 4, const PortionUnit.raw(Units.ounce)),
        ('named serving', 0.75, PortionUnit.serving(_pot)),
      ]) {
    test(
      'Unlog Undo retains $name, seven values, coverage and original times after Move',
      () async {
        final double count = amount * unit.size.canonicalAmount / 170;
        final LoggedPortion portion = LoggedPortion.tryCapture(
          amount: amount,
          unit: unit,
          servings: count,
          standard: _pot,
        )!;
        final MealPlanEntry entry = await f.seed(
          logged: true,
          portion: portion,
        );
        await f.repo.move(
          entry,
          date: DateTime(2026, 9, 27),
          slot: MealSlot.dinner,
        );
        final MealPlanEntryRow before = await f.raw();
        final LogStateChange receipt = await f.toggle(await f.read());
        // The library really changes after Unlog: new name, weight, density,
        // nutrition, then deletion. Undo restores saved evidence independently.
        final FoodStore foods = FoodStore(f.db);
        await foods.upsert(
          Food(
            id: 'yogurt',
            name: 'Replacement yogurt',
            gramsPerMillilitre: 9,
            servingOptions: <ServingOption>[
              ServingOption(
                id: 'pot',
                label: 'New pot',
                amount: Quantity.of(300, Units.gram),
                macros: const Macros(kcal: 999),
              ),
            ],
            source: FoodSource.manual,
          ),
          updatedAt: _now,
        );
        await foods.softDelete('yogurt', updatedAt: _now);
        expect((await foods.byId('yogurt'))!.isDeleted, isTrue);
        expect(await f.undo(receipt), UndoLogStateResult.restored);
        _sameMeal(await f.raw(), before);
        final MacroSnapshot snapshot = (await f.read()).macroSnapshot!;
        expect(snapshot.loggedPortion!.enteredAmount, amount);
        expect(snapshot.loggedPortion!.enteredUnit.id, unit.id);
        expect(snapshot.label, 'Name when eaten');
        expect(snapshot.macros, _macros.scaledBy(count));
        expect(snapshot.coverage, _coverage);
        expect(snapshot.usesApproximatePackageNutrition, isTrue);
        expect(snapshot.capturedAt, _now);
        expect((await f.read()).loggedAt!.day, 27);
      },
    );
  }

  for (final bool legacy in <bool>[false, true]) {
    test(
      'restores ${legacy ? "old omitted" : "unknown nested"} snapshot JSON verbatim and queues it intact',
      () async {
        await f.seed(logged: true);
        final Map<String, Object?> json =
            jsonDecode((await f.raw()).macroSnapshot!) as Map<String, Object?>;
        if (legacy) {
          json.remove('fiber_g');
          json.remove('coverage');
          json.remove('captured_at');
        } else {
          json['future'] = <String, Object?>{
            'a': <Object>[1, 'two'],
          };
          json['logged_portion'] = <String, Object?>{
            'version': 777,
            'raw': '125 g',
          };
          (json['coverage']! as Map<String, Object?>)['future'] =
              'unrecognized';
        }
        final String raw = const JsonEncoder.withIndent('  ').convert(json);
        await (f.db.update(
          f.db.mealPlanEntries,
        )).write(MealPlanEntriesCompanion(macroSnapshot: Value<String?>(raw)));
        final LogStateChange receipt = await f.toggle(await f.read());
        expect(await f.undo(receipt), UndoLogStateResult.restored);
        expect((await f.raw()).macroSnapshot, raw);
        final PendingWrite write = (await f.queue.pending()).singleWhere(
          (PendingWrite w) => w.entityTable == PlanRepository.entriesTable,
        );
        expect(write.payload['macro_snapshot'], json);
      },
    );
  }

  test(
    'current input freezes on Log; Undo does not derive it from old history',
    () async {
      final MealPlanEntry entry = await f.seed();
      final LoggedPortion portion = LoggedPortion.tryCapture(
        amount: 1.5,
        unit: PortionUnit.serving(_pot),
        servings: 1.5,
        standard: _pot,
      )!;
      final LogStateChange receipt = (await f.repo.changeLogState(
        expected: entry,
        logged: true,
        scope: f.scope,
        liveMacros: const Macros(kcal: 345),
        label: 'Updated yogurt',
        liveCoverage: const NutrientCoverage.allUnknown(),
        loggedPortion: portion,
        usesApproximatePackage: true,
      ))!;
      expect((await f.read()).macroSnapshot!.macros.kcal, 517.5);
      expect((await f.read()).macroSnapshot!.loggedPortion, portion);
      expect(await f.undo(receipt), UndoLogStateResult.restored);
      expect((await f.read()).macroSnapshot, isNull);
    },
  );

  for (final String later in <String>[
    'portion',
    'move',
    'delete',
    'relog',
    'direct ABA',
    'sync ABA',
    'same-id reinsert',
    'foreign owner',
  ]) {
    test(
      'Undo refuses $later without a row or outbox write, even on the same clock',
      () async {
        final LogStateChange receipt = await f.toggle(
          await f.seed(logged: true),
        );
        final MealPlanEntryRow after = await f.raw();
        switch (later) {
          case 'portion':
            await f.repo.updateEntry('meal', servings: 3);
          case 'move':
            await f.repo.move(
              await f.read(),
              date: DateTime(2026, 10, 2),
              slot: MealSlot.snack,
            );
          case 'delete':
            await f.repo.removeEntry('meal');
          case 'relog':
            await f.repo.logEntry(
              'meal',
              liveMacros: _macros,
              label: 'Another log',
              liveCoverage: _coverage,
            );
          case 'direct ABA':
            await f.db
                .into(f.db.mealPlanEntries)
                .insertOnConflictUpdate(after.copyWith(servings: 8));
            await f.db.into(f.db.mealPlanEntries).insertOnConflictUpdate(after);
          case 'sync ABA':
            final Map<String, Object?> json = PlanMapper.entryToJson(
              await f.read(),
              updatedAt: _now,
            );
            await RemoteRows(f.db)
                .applyEntry(<String, Object?>{...json, 'servings': 9});
            await RemoteRows(f.db).applyEntry(json);
          case 'same-id reinsert':
            await f.store.deleteEntry('meal');
            await f.db.into(f.db.mealPlanEntries).insert(after);
          case 'foreign owner':
            await f.db
                .update(f.db.mealPlanDays)
                .write(
                  const MealPlanDaysCompanion(userId: Value<String>('other')),
                );
        }
        final List<MealPlanEntryRow> beforeUndo = await f.db
            .select(f.db.mealPlanEntries)
            .get();
        final List<PendingWriteRow> pending = await f.pending();
        expect(await f.undo(receipt), UndoLogStateResult.changed);
        expect(await f.db.select(f.db.mealPlanEntries).get(), beforeUndo);
        expect(await f.pending(), pending);
      },
    );
  }

  test('stale duplicate Log and corrected expected state cannot mint another receipt', () async {
    final MealPlanEntry entry = await f.seed();
    await f.toggle(entry);
    final List<PendingWriteRow> pending = await f.pending();
    expect(
      await f.repo.changeLogState(
        expected: entry,
        logged: true,
        scope: f.scope,
        liveMacros: _macros,
        label: 'Stale',
        liveCoverage: _coverage,
      ),
      isNull,
    );
    expect(await f.pending(), pending);
    final MealPlanEntry logged = await f.read();
    await f.repo.logEntry(
      'meal',
      liveMacros: _macros,
      label: 'Ignored correction label',
      liveCoverage: _coverage,
      portion: 3,
    );
    expect(
      await f.repo.changeLogState(
        expected: logged,
        logged: false,
        scope: f.scope,
      ),
      isNull,
    );
  });

  test('foreign entry and foreign session never get receipts', () async {
    final MealPlanEntry entry = await f.seed();
    final List<PendingWriteRow> pending = await f.pending();
    final PlanRepository other = PlanRepository(
      database: f.db,
      store: f.store,
      queue: f.queue,
      userId: 'other',
    );
    expect(
      await other.changeLogState(
        expected: entry,
        logged: true,
        scope: LogStateScope(userId: 'other', householdId: 'home'),
        liveMacros: _macros,
        label: 'Wrong',
        liveCoverage: _coverage,
      ),
      isNull,
    );
    expect(
      await f.repo.changeLogState(
        expected: entry,
        logged: true,
        scope: LogStateScope(userId: 'other', householdId: 'home'),
        liveMacros: _macros,
        label: 'Wrong',
        liveCoverage: _coverage,
      ),
      isNull,
    );
    expect(await f.pending(), pending);
  });

  test(
    'receipt requires issuing repository and exact active session',
    () async {
      final LogStateChange receipt = await f.toggle(await f.seed());
      final PlanRepository other = PlanRepository(
        database: f.db,
        store: f.store,
        queue: f.queue,
        userId: 'me',
      );
      expect(
        await other.undoLogState(receipt, scope: f.scope),
        UndoLogStateResult.expired,
      );
      expect(
        await f.repo.undoLogState(
          receipt,
          scope: LogStateScope(userId: 'me', householdId: 'home'),
        ),
        UndoLogStateResult.expired,
      );
      f.scope.invalidate();
      final List<PendingWriteRow> pending = await f.pending();
      expect(await f.undo(receipt), UndoLogStateResult.expired);
      expect(await f.pending(), pending);
    },
  );

  test('failed action and failed Undo roll back row, outbox and revision; same receipt retries', () async {
    final MealPlanEntry entry = await f.seed(logged: true);
    await f.store.prepareLogStateTracking();
    final MealPlanEntryRow original = await f.raw();
    final List<PendingWriteRow> pending = await f.pending();
    final int revision = (await f.store.logState('meal'))!.revision;
    f.queue.fail = true;
    await expectLater(f.toggle(entry), throwsStateError);
    _sameMeal(await f.raw(), original);
    expect(await f.pending(), pending);
    expect((await f.store.logState('meal'))!.revision, revision);
    f.queue.fail = false;
    final LogStateChange receipt = await f.toggle(entry);
    final MealPlanEntryRow unlogged = await f.raw();
    final List<PendingWriteRow> pendingUnlogged = await f.pending();
    f.queue.fail = true;
    await expectLater(f.undo(receipt), throwsStateError);
    expect(await f.raw(), unlogged);
    expect(await f.pending(), pendingUnlogged);
    f.queue.fail = false;
    expect(await f.undo(receipt), UndoLogStateResult.restored);
    _sameMeal(await f.raw(), original);
  });

  test(
    'identity change during the transaction rolls back action and Undo',
    () async {
      final MealPlanEntry entry = await f.seed();
      final MealPlanEntryRow before = await f.raw();
      final List<PendingWriteRow> pending = await f.pending();
      f.queue.afterEnqueue = f.scope.invalidate;
      expect(
        await f.repo.changeLogState(
          expected: entry,
          logged: true,
          scope: f.scope,
          liveMacros: _macros,
          label: 'Current',
          liveCoverage: _coverage,
        ),
        isNull,
      );
      expect(await f.raw(), before);
      expect(await f.pending(), pending);
      final LogStateScope fresh = LogStateScope(
        userId: 'me',
        householdId: 'home',
      );
      f.queue.afterEnqueue = null;
      final LogStateChange receipt = (await f.repo.changeLogState(
        expected: entry,
        logged: true,
        scope: fresh,
        liveMacros: _macros,
        label: 'Current',
        liveCoverage: _coverage,
      ))!;
      final MealPlanEntryRow logged = await f.raw();
      final List<PendingWriteRow> queuedLogged = await f.pending();
      f.queue.afterEnqueue = fresh.invalidate;
      expect(
        await f.repo.undoLogState(receipt, scope: fresh),
        UndoLogStateResult.expired,
      );
      expect(await f.raw(), logged);
      expect(await f.pending(), queuedLogged);
    },
  );

  test(
    'concurrent setup, taps and Undo serialize without duplicate writes',
    () async {
      final MealPlanEntry entry = await f.seed();
      await Future.wait(<Future<void>>[
        f.store.prepareLogStateTracking(),
        PlanStore(f.db).prepareLogStateTracking(),
      ]);
      final List<LogStateChange?> receipts = await Future.wait(
        List<Future<LogStateChange?>>.generate(
          2,
          (_) => f.repo.changeLogState(
            expected: entry,
            logged: true,
            scope: f.scope,
            liveMacros: _macros,
            label: 'Current',
            liveCoverage: _coverage,
          ),
        ),
      );
      expect(receipts.whereType<LogStateChange>(), hasLength(1));
      final LogStateChange receipt = receipts
          .whereType<LogStateChange>()
          .single;
      final int sequence = (await f.pending()).last.sequence;
      final List<UndoLogStateResult> outcomes = await Future.wait(
        <Future<UndoLogStateResult>>[f.undo(receipt), f.undo(receipt)],
      );
      expect(outcomes, everyElement(UndoLogStateResult.restored));
      expect((await f.pending()).last.sequence, sequence + 1);
    },
  );

  test(
    'rolled-back direct change leaves Undo valid after queued write was synced',
    () async {
      final LogStateChange receipt = await f.toggle(await f.seed());
      for (final PendingWrite write in await f.queue.pending()) {
        await f.queue.markSynced(write.sequence);
      }
      await expectLater(
        f.db.transaction(() async {
          await f.db
              .update(f.db.mealPlanEntries)
              .write(
                const MealPlanEntriesCompanion(servings: Value<double>(8)),
              );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await f.undo(receipt), UndoLogStateResult.restored);
    },
  );

  test(
    'connection reopen drops TEMP identity and cannot accept an old receipt',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'hearth-log-undo-',
      );
      final File file = File('${directory.path}/db.sqlite');
      final _Fixture first = _Fixture(
        HearthDatabase.forTesting(NativeDatabase(file)),
      );
      final LogStateChange receipt = await first.toggle(await first.seed());
      final String connection = (await first.store.logState('meal'))!
          .connection;
      await first.db.close();
      final _Fixture reopened = _Fixture(
        HearthDatabase.forTesting(NativeDatabase(file)),
      );
      try {
        await reopened.store.prepareLogStateTracking();
        expect(
          (await reopened.store.logState('meal'))!.connection,
          isNot(connection),
        );
        expect(
          await reopened.repo.undoLogState(receipt, scope: first.scope),
          UndoLogStateResult.expired,
        );
        expect((await reopened.read()).isLogged, isTrue);
        final List<QueryRow> persisted = await reopened.db
            .customSelect(
              "SELECT name FROM main.sqlite_master WHERE name LIKE 'hearth_log_state_%'",
            )
            .get();
        expect(persisted, isEmpty);
      } finally {
        await reopened.db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
