import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import 'generated_migrations/schema.dart';

/// The recorded schema is this schema (CLAUDE.md rule 8's local half).
///
/// `supabase db reset` proves the *server's* SQL. Nothing proved the local
/// one — and the local database is the one that gets upgraded in place on a
/// phone that already holds a year of logs. A column added to a table without
/// `schemaVersion` being bumped is the quiet version of that: every fresh
/// install gets the new column because `createAll` reads today's tables, and
/// every existing device never does, because no migration step mentions it.
/// The two then disagree for ever, and the symptom is one device's query
/// failing on a column the other has.
///
/// `drift_schemas/drift_schema_v25.json` is what the schema is *recorded* as.
/// These two tests hold the recording and the code together from both ends.
///
/// When the schema changes: bump `schemaVersion`, add the migration step,
/// then re-run
///
///   dart run drift_dev schema dump lib/data/local/hearth_database.dart drift_schemas/
///   dart run drift_dev schema generate drift_schemas/ test/data/local/generated_migrations/
///
/// The second command is what gives the *next* change a real historical test:
/// once two snapshots exist, drift can build a database at the old one and
/// run the real migration against it, rather than approximating an old
/// database by dropping columns from a new one.
void main() {
  test('a snapshot exists for the version the code says it is', () {
    // The failure this catches is a version bumped and a snapshot forgotten:
    // the next release then has nothing to migrate *from* in a test, and the
    // gap is invisible until somebody needs it.
    final Directory dir = Directory('drift_schemas');
    expect(dir.existsSync(), isTrue, reason: 'drift_schemas/ is missing');

    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    final File snapshot = File(
      'drift_schemas/drift_schema_v${db.schemaVersion}.json',
    );
    expect(
      snapshot.existsSync(),
      isTrue,
      reason:
          'schemaVersion is ${db.schemaVersion} and there is no snapshot for '
          'it. Re-run the two drift_dev commands in this file\'s doc comment.',
    );

    // The file parses, so a truncated write is caught rather than discovered
    // by the verifier below with a stranger message.
    expect(
      jsonDecode(snapshot.readAsStringSync()),
      isA<Map<String, Object?>>(),
      reason: 'the snapshot is not readable JSON',
    );

    // And the *generated* helper knows about it, which is the second of the
    // two commands. Dumping a snapshot and forgetting to regenerate leaves
    // the verifier unable to build a database at the new version — a failure
    // that surfaces as `MissingSchemaException` at some later date, from a
    // test that has nothing to do with whoever caused it.
    //
    // Note `_meta.version` in the file is drift's *file format* version, not
    // the schema's. It is not what this is checking, and reading it would be
    // a check that looks like this one and is not.
    expect(
      GeneratedHelper.versions,
      contains(db.schemaVersion),
      reason:
          'drift_schemas/ has v${db.schemaVersion} but the generated helper '
          'does not. Re-run the second command in this file\'s doc comment.',
    );
  });

  test('and the live schema is the one recorded in it', () async {
    // The other end. A table changed without a version bump leaves this
    // snapshot describing a database that no longer exists, and every device
    // already installed never hears about the change.
    final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, db.schemaVersion);
  });
}
