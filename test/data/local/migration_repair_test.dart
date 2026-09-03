import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

/// Opening a database that a half-finished upgrade left behind.
///
/// v14 ends with `alterTable(TableMigration(recipePhotos))`, which recreates
/// that table from the schema **as it stands today** — so it also creates
/// columns added in later versions. v17 then tries to add one of those again,
/// the run dies, and `user_version` never advances. Every launch after that
/// replays v14 against a table that already has everything, and the app can
/// no longer open its own database.
///
/// That is not hypothetical: it is what put "The recipe library could not be
/// read — duplicate column name: remote_path" on a phone.
void main() {
  Future<File> databaseAt(int version, {required bool modernPhotos}) async {
    final Directory dir = await Directory.systemTemp.createTemp('hearth-rep');
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/hearth.sqlite');

    final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    if (!modernPhotos) {
      for (final String c in <String>[
        'remote_path',
        'sync_attempts',
        'sync_error',
        'attempted_path',
      ]) {
        await db.customStatement('ALTER TABLE recipe_photos DROP COLUMN $c');
      }
    }
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
    return file;
  }

  Future<int> openAndRead(File file) async {
    final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase(file));
    final List<QueryRow> rows = await db
        .customSelect('PRAGMA user_version')
        .get();
    final int version = rows.single.data.values.first! as int;
    // The thing the phone could not do: read the library.
    await db.select(db.recipes).get();
    await db.close();
    return version;
  }

  /// Read from the database rather than written down here. Every schema bump
  /// used to break these three, which taught the next person to edit the
  /// number rather than to ask why a migration test was failing.
  final int current = HearthDatabase.forTesting(NativeDatabase.memory())
      .schemaVersion;

  test(
    'a database whose columns ran ahead of its version still opens',
    () async {
      // The exact state on the phone: version says v13, but recipe_photos
      // already carries every modern column because v14's alterTable put them
      // there before a later step failed.
      final File file = await databaseAt(13, modernPhotos: true);

      expect(await openAndRead(file), current);
    },
  );

  test('and so does an honest old one', () async {
    // The ordinary path must keep working — the repair must not become a
    // reason to skip a column that genuinely is missing.
    final File file = await databaseAt(13, modernPhotos: false);

    expect(await openAndRead(file), current);
  });

  test('opening twice is not a second migration', () async {
    final File file = await databaseAt(13, modernPhotos: true);
    await openAndRead(file);

    expect(await openAndRead(file), current);
  });
}
