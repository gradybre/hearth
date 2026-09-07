import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/planning/day_progress.dart';

/// Two phones setting the same week's targets (spec §7.1).
///
/// `macro_targets` is unique on (user_id, week_start_date) and keyed on a
/// random id. Both phones in a household decide this week's targets on their
/// own, offline; each mints its own id for the same constrained pair; and the
/// second to reach the server is refused by the unique key — for ever, because
/// nothing about retrying changes the id it is carrying.
///
/// Days, shopping lines and remembered ingredient answers all derive their ids
/// from the thing the key is on, for exactly this reason. This one did not.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  /// One phone, with its own database and its own idea of a random id.
  Future<String> idWrittenBy(String device) async {
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    final PendingWriteStore queue = PendingWriteStore(db);
    await PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: queue,
      userId: 'user-1',
      idFactory: () => 'random-on-$device',
      clock: () => DateTime.utc(2026, 9, 7, 12),
    ).setTargets(DateTime(2026, 9, 7), targets);

    return (await queue.pending()).single.entityId;
  }

  test('agree on the row, rather than each inventing one', () async {
    final String fromA = await idWrittenBy('phone-a');
    final String fromB = await idWrittenBy('phone-b');

    expect(
      fromA,
      fromB,
      reason:
          'two ids for one (user, week) — the unique key refuses whichever '
          'reaches the server second, and retrying carries the same id',
    );
  });

  test('and the id is derived from the pair the key is on', () async {
    final String monday = await idWrittenBy('phone-a');

    // A different week is a different row.
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);
    final PendingWriteStore queue = PendingWriteStore(db);
    await PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: queue,
      userId: 'user-1',
      idFactory: () => 'random',
      clock: () => DateTime.utc(2026, 9, 14, 12),
    ).setTargets(DateTime(2026, 9, 14), targets);

    expect((await queue.pending()).single.entityId, isNot(monday));
  });

  test(
    'and a week that arrives under another id updates, not collides',
    () async {
      // The pull half of the same defect, and the worse one: the local table
      // carries the same unique key, and applying by primary key means a row
      // written on the other phone — under its own random id — throws on the
      // way in and takes the whole table's pull with it.
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final RemoteRows rows = RemoteRows(db);

      Map<String, Object?> arriving(String id, double kcal) =>
          <String, Object?>{
            'id': id,
            'user_id': 'user-1',
            'week_start_date': '2026-09-07',
            'kcal': kcal,
            'protein_g': 150,
            'carb_g': 200,
            'fat_g': 70,
            'updated_at': '2026-09-07T12:00:00.000Z',
          };

      await rows.applyTargets(arriving('id-from-phone-a', 2000));
      await rows.applyTargets(arriving('id-from-phone-b', 2200));

      final List<MacroTargetRow> stored = await db
          .select(db.macroTargets)
          .get();
      expect(stored, hasLength(1), reason: 'one week, one row');
      expect(stored.single.kcal, 2200, reason: 'the later write should win');
    },
  );
}
