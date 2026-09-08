import 'dart:io';

import 'package:drift/native.dart';
import 'package:hearth/core/build_info.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:test/test.dart';

/// The diagnostics panel reports this build, not a build (handoff §12.3).
///
/// `BuildInfo` is three hand-written constants, which is a deliberate trade —
/// no plugin, no async, nothing blank on the frame somebody screenshots — and
/// the whole of the risk it carries is drift. A version that has quietly
/// stopped matching is worse than no version at all: it sends whoever is
/// reading a bug report looking in the wrong release, at the exact moment
/// they are trusting the panel because they cannot see the device.
///
/// So each constant is held against the thing it claims to describe. Bumping
/// one is two lines in one commit; forgetting the second is a red suite
/// rather than a wrong answer six weeks later.
void main() {
  test('the app version is the one in pubspec.yaml', () {
    final List<String> lines = File('pubspec.yaml').readAsLinesSync();
    final String? declared = lines
        .where((String line) => line.startsWith('version:'))
        .map((String line) => line.split(':')[1].trim())
        .firstOrNull;

    expect(
      declared,
      isNotNull,
      reason: 'pubspec.yaml has no version line; is this the repo root?',
    );
    expect(
      BuildInfo.appVersion,
      declared,
      reason:
          'BuildInfo.appVersion and pubspec.yaml disagree, so Settings would '
          'report a build that does not exist. Change both.',
    );
  });

  test('the schema version is the database\'s own', () {
    // Read from the database class rather than restated, so this cannot pass
    // by two constants being equally wrong.
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);
    expect(BuildInfo.schemaVersion, db.schemaVersion);
  });

  test('and the export version is the exporter\'s own', () {
    expect(BuildInfo.exportFormatVersion, DataExport.formatVersion);
  });
}
