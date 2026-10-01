import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/sync/record_sync.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/data/sync/sync_scope.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/target_schedule.dart';

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

RemoteRecord boundary({
  String id = 'alice-boundary',
  String userId = 'alice',
  String week = '2026-09-28',
  MacroTargets? targets = initial,
  required DateTime at,
}) => RemoteRecord(
  id: id,
  updatedAt: at,
  payload: <String, Object?>{
    'id': id,
    'user_id': userId,
    'week_start_date': week,
    'is_stopped': targets == null,
    'kcal': targets?.kcal,
    'protein_g': targets?.proteinG,
    'carb_g': targets?.carbG,
    'fat_g': targets?.fatG,
    'fiber_g': targets?.fiberG,
    'sodium_mg': targets?.sodiumMg,
    'cholesterol_mg': targets?.cholesterolMg,
    'updated_at': at.toIso8601String(),
  },
);

void main() {
  const SyncScope alice = SyncScope(userId: 'alice', householdId: 'our-home');
  const SyncScope bob = SyncScope(userId: 'bob', householdId: 'our-home');
  final DateTime monday = DateTime(2026, 9, 28);
  final DateTime nextMonday = DateTime(2026, 10, 5);
  final DateTime t0 = DateTime.utc(2026, 9, 28, 12);
  final DateTime t1 = DateTime.utc(2026, 9, 28, 13);
  final DateTime t2 = DateTime.utc(2026, 9, 28, 14);
  late HearthDatabase db;
  late PendingWriteStore queue;
  late PreferenceStore preferences;
  late _TargetGateway gateway;
  late SyncScope current;

  PlanRepository plan(
    HearthDatabase database, {
    String userId = 'alice',
    DateTime? clock,
  }) => PlanRepository(
    database: database,
    store: PlanStore(database),
    queue: PendingWriteStore(database),
    userId: userId,
    clock: () => clock ?? t1,
  );

  RecordSync sync() => RecordSync(
    engine: SyncEngine(queue: queue, gateway: gateway),
    rows: RemoteRows(db),
    queue: queue,
    preferences: preferences,
    scope: () => current,
  );

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    preferences = PreferenceStore(db);
    current = alice;
    gateway = _TargetGateway(() => current);
  });
  tearDown(() => db.close());

  test(
    'a second device receives ongoing values, stop and future exception',
    () async {
      final HearthDatabase sender = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(sender.close);
      final PendingWriteStore senderQueue = PendingWriteStore(sender);
      final SyncEngine push = SyncEngine(queue: senderQueue, gateway: gateway);
      final PlanRepository writer = plan(sender);

      await writer.setOngoingTargets(monday, initial);
      await writer.setTargets(DateTime(2026, 10, 12), revised);
      expect((await push.push()).isFullyDrained, isTrue);
      await sync().pull();

      expect(await plan(db).targetsFor(nextMonday), initial);
      expect(await plan(db).targetsFor(DateTime(2026, 10, 12)), revised);
      expect(
        (await plan(db).targetResolutionFor(nextMonday)).source,
        TargetSource.ongoing,
      );

      await plan(sender, clock: t2).stopOngoingTargets(monday);
      expect((await push.push()).isFullyDrained, isTrue);
      await sync().pull();

      expect(await plan(db).targetsFor(monday), initial);
      expect(await plan(db).targetsFor(nextMonday), isNull);
      expect(await plan(db).targetsFor(DateTime(2026, 10, 12)), revised);
      expect(await plan(db).targetsFor(DateTime(2026, 10, 19)), isNull);
      final ResolvedTargets stopped = await plan(db)
          .targetResolutionFor(nextMonday);
      expect(stopped.ongoingBoundary!.isStopped, isTrue);
      expect(await db.select(db.macroTargets).get(), hasLength(2));
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
      expect(await queue.count(), 0);
    },
  );

  test(
    'a newer remote revision replaces all seven values, including nulls',
    () async {
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[boundary(at: t0)];
      await sync().pull();
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
        boundary(at: t1, targets: revised),
      ];
      await sync().pull();

      expect(await plan(db).targetsFor(nextMonday), revised);
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
    },
  );

  test(
    'a newer remote boundary meets the existing user/week under another id',
    () async {
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
        boundary(id: 'older-device-id', at: t0),
      ];
      await sync().pull();
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
        boundary(id: 'server-id', at: t1, targets: revised),
      ];
      await sync().pull();

      expect(await plan(db).targetsFor(nextMonday), revised);
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
    },
  );

  test('an older remote active boundary cannot restart a newer stop', () async {
    gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
      boundary(at: t2, targets: null),
    ];
    await sync().pull();
    gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[boundary(at: t0)];
    await sync().pull();

    expect(await plan(db).targetsFor(nextMonday), isNull);
    expect(
      (await plan(db).targetResolutionFor(nextMonday))
          .ongoingBoundary!
          .isStopped,
      isTrue,
    );
  });

  test('an older alternate-id boundary cannot restart a newer stop', () async {
    gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
      boundary(id: 'newer-stop-id', at: t2, targets: null),
    ];
    await sync().pull();
    gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
      boundary(id: 'older-active-id', at: t0),
    ];
    await sync().pull();

    expect(await plan(db).targetsFor(nextMonday), isNull);
    expect(
      (await plan(db).targetResolutionFor(nextMonday))
          .ongoingBoundary!
          .isStopped,
      isTrue,
    );
  });

  test(
    'a queued local choice survives a newer remote record with the same id',
    () async {
      await plan(db).setOngoingTargets(monday, initial);
      final PendingWrite pending = (await queue.pending()).single;
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
        boundary(id: pending.entityId, at: t2, targets: null),
      ];
      await sync().pull();

      expect(await plan(db).targetsFor(nextMonday), initial);
      expect((await queue.pending()).single.payload, pending.payload);
    },
  );

  test('an alternate server id cannot erase an unsent local stop', () async {
    await plan(db).setOngoingTargets(monday, initial);
    await plan(db).stopOngoingTargets(monday);
    final List<PendingWrite> pending = await queue.pending();
    gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
      boundary(id: 'other-device-id', at: t2, targets: revised),
    ];
    await sync().pull();

    expect(await plan(db).targetsFor(monday), initial);
    expect(await plan(db).targetsFor(nextMonday), isNull);
    expect(
      (await queue.pending()).map((PendingWrite write) => write.payload),
      pending.map((PendingWrite write) => write.payload),
    );
  });

  test(
    'switching accounts uses private data and independent checkpoints',
    () async {
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[
        boundary(at: t0),
        boundary(id: 'bob-boundary', userId: 'bob', at: t0, targets: revised),
      ];
      await sync().pull();
      expect(await plan(db).targetsFor(nextMonday), initial);
      expect(await plan(db, userId: 'bob').targetsFor(nextMonday), isNull);
      await sync().pull();
      expect(gateway.asked['ongoing_macro_targets'], isNotNull);

      current = bob;
      await sync().pull();
      expect(gateway.asked['ongoing_macro_targets'], isNull);
      expect(await plan(db, userId: 'bob').targetsFor(nextMonday), revised);
      expect(await plan(db).targetsFor(nextMonday), initial);
      expect(await plan(db, userId: 'charlie').targetsFor(nextMonday), isNull);
    },
  );

  test(
    'an account switch during the ongoing fetch discards that response',
    () async {
      gateway.rows['ongoing_macro_targets'] = <RemoteRecord>[boundary(at: t0)];
      gateway.onFetch = (String table) {
        if (table == 'ongoing_macro_targets') current = bob;
      };
      final PullResult result = await sync().pull();

      expect(result.abandonedScope, isTrue);
      expect(await db.select(db.ongoingMacroTargets).get(), isEmpty);
      expect(
        await preferences.read(alice.watermarkKeyFor('ongoing_macro_targets')),
        isNull,
      );
    },
  );
}

/// Supplies scoped server batches, as Supabase RLS does. Checkpoint arguments
/// are recorded independently; each test controls the batch it wants returned.
class _TargetGateway implements RemoteGateway {
  _TargetGateway(this.scope);

  final SyncScope Function() scope;
  final Map<String, List<RemoteRecord>> rows = <String, List<RemoteRecord>>{};
  final Map<String, DateTime?> asked = <String, DateTime?>{};
  void Function(String table)? onFetch;

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) async {
    final List<RemoteRecord> records = rows.putIfAbsent(
      entityTable,
      () => <RemoteRecord>[],
    );
    records.removeWhere((RemoteRecord record) => record.id == entityId);
    if (operation == WriteOperation.upsert) {
      records.add(
        RemoteRecord(
          id: entityId,
          updatedAt: DateTime.parse(payload['updated_at']! as String),
          payload: Map<String, Object?>.of(payload),
        ),
      );
    }
  }

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async {
    asked[entityTable] = since;
    final List<RemoteRecord> response = <RemoteRecord>[
      for (final RemoteRecord record in rows[entityTable] ?? <RemoteRecord>[])
        if (record.payload['user_id'] == scope().userId) record,
    ];
    onFetch?.call(entityTable);
    return response;
  }

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async => const <RemoteRecord>[];
}
