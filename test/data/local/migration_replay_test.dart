import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/core/build_info.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';

/// Every upgrade step survives being replayed (CLAUDE.md rule 8's local half).
///
/// The failure this is for has already happened once, on a phone: v14 rebuilds
/// `recipe_photos` from the schema **as it stands today**, so it also creates
/// columns added in later versions; v17 then tried to add one of them again,
/// the run died, `user_version` never advanced, and every launch afterwards
/// replayed the same dying step. The app could not open its own database, and
/// the message was "duplicate column name: remote_path".
///
/// `migration_repair_test.dart` holds that one case. This holds the shape of
/// it across the whole range: a database sitting at *any* version, whose
/// tables already carry things a later step means to add, must upgrade to
/// today without throwing.
///
/// **What this is and is not.** It builds today's tables and then winds
/// `user_version` back, which is not a historical database — it is the
/// hardest version of one, since every column a step wants to add is already
/// there. That is exactly the half-applied state above, and it is the state
/// an interrupted upgrade leaves behind. A *true* historical test needs a
/// snapshot of the old schema to build from, drift can do that from two
/// snapshots, and `schema_snapshot_test.dart` starts the record at v25 so the
/// next schema change gets one. This covers the range that has no snapshots
/// and never will.
void main() {
  Future<File> databaseAt(int version) async {
    final Directory dir = await Directory.systemTemp.createTemp('hearth-mig');
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/hearth.sqlite');

    final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase(file));
    // Forces `createAll` to run, so the file holds today's tables.
    await db.customSelect('SELECT 1').get();
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
    return file;
  }

  group('an interrupted upgrade can always be finished', () {
    // Every version the app has ever had, not a sample: the one that broke a
    // phone was v17, and nobody would have picked it. The end is read from
    // the code rather than typed — hardcoding it means the newest historical
    // version is never replayed after a bump, which is a silent gap and the
    // worse of the two ways to get this wrong.
    for (int from = 1; from < BuildInfo.schemaVersion; from++) {
      test('a database left at v$from opens and finishes upgrading', () async {
        final File file = await databaseAt(from);
        final HearthDatabase db = HearthDatabase.forTesting(
          NativeDatabase(file),
        );
        addTearDown(db.close);

        // Reading is what triggers the migration, and what proves the
        // database is usable afterwards rather than merely not throwing
        // during the upgrade.
        await db.select(db.recipes).get();

        final QueryRow row = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(
          row.read<int>('user_version'),
          db.schemaVersion,
          reason: 'the upgrade did not reach today, so it will replay again',
        );
      });
    }
  });

  test('and a write queued before it is still queued after', () async {
    // The one that would cost data rather than a launch. A meal logged on a
    // train sits in `pending_writes` until there is signal; if the upgrade
    // that runs on the next launch drops or mangles that table, the meal is
    // gone and nothing says so — the queue is the only copy of a write that
    // has not reached the server.
    final File file = await databaseAt(13);

    final HearthDatabase before = HearthDatabase.forTesting(
      NativeDatabase(file),
    );
    await PendingWriteStore(before).enqueue(
      entityTable: 'meal_plan_entries',
      entityId: 'entry-1',
      operation: WriteOperation.upsert,
      payload: const <String, Object?>{'id': 'entry-1', 'servings': 2},
      queuedAt: DateTime.utc(2026, 9, 1),
    );
    // Wound back again, because enqueueing above opened the database and that
    // upgraded it. So this is not literally a row written by the v13 build —
    // there is no v13 schema to write one against, which is the same limit
    // the group above states. What it does hold is the half that can be
    // held: whatever is in the queue when an upgrade runs is still there,
    // intact, when it finishes.
    await before.customStatement('PRAGMA user_version = 13');
    await before.close();

    final HearthDatabase after = HearthDatabase.forTesting(
      NativeDatabase(file),
    );
    addTearDown(after.close);
    final List<PendingWrite> queued = await PendingWriteStore(after).pending();

    expect(queued, hasLength(1));
    expect(queued.single.entityId, 'entry-1');
    expect(
      queued.single.payload['servings'],
      2,
      reason: 'the payload survived the file but not its contents',
    );
  });
}
