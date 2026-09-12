import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// An applied migration is history, and history is not edited (rule 8).
///
/// Rule 8 says a migration is not done until it is pushed. The corollary is
/// the one that actually cost a session: once it *has* been pushed, the file
/// is a record of what the hosted database was told, and changing it changes
/// nothing about the hosted database while making the repository claim
/// otherwise.
///
/// It happened here. A function was appended to a migration that had already
/// been pushed. `supabase db push` skips a version it has applied, so the
/// hosted database never saw it; `supabase migration list` compares versions
/// rather than contents, so it went on reporting local and remote in
/// agreement; and `supabase db query` without `--linked` answers from the
/// local database, so the check that should have caught it agreed too. Three
/// checks, all green, all answering a question nobody had asked. The symptom
/// was a thermostat that could not be linked, with nothing in the message
/// pointing anywhere near a migration.
///
/// So the contents are recorded, and changing a recorded file fails here
/// instead — cheaply, locally, and with the fix in the failure message.
///
/// **Adding a migration is not a failure.** A new file is simply added to the
/// manifest. Only *changing* one that is already in it is caught.
void main() {
  final Directory dir = Directory('supabase/migrations');
  final File manifestFile = File('supabase/migrations/.applied.json');

  /// What the repository says each migration contained when it was pushed.
  Map<String, String> recorded() =>
      (jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>).map(
        (String name, dynamic hash) =>
            MapEntry<String, String>(name, hash as String),
      );

  Map<String, String> onDisk() => <String, String>{
    for (final FileSystemEntity entity in dir.listSync())
      if (entity is File && entity.path.endsWith('.sql'))
        entity.uri.pathSegments.last: sha256
            .convert(entity.readAsBytesSync())
            .toString(),
  };

  test('the manifest exists, or nothing below means anything', () {
    expect(
      manifestFile.existsSync(),
      isTrue,
      reason: 'supabase/migrations/.applied.json is missing',
    );
    expect(recorded(), isNotEmpty);
  });

  test('no migration that has been recorded has changed since', () {
    final Map<String, String> was = recorded();
    final Map<String, String> now = onDisk();

    final List<String> edited = <String>[
      for (final MapEntry<String, String> entry in was.entries)
        if (now.containsKey(entry.key) && now[entry.key] != entry.value)
          entry.key,
    ];

    expect(
      edited,
      isEmpty,
      reason:
          'These migrations have already been applied and have been edited '
          'since:\n  ${edited.join('\n  ')}\n\n'
          'The hosted database will never see the change — `supabase db push` '
          'skips a version it has applied. Put the change in a NEW migration '
          'instead, and restore these files. If the edit is only a comment, '
          're-record the manifest deliberately.',
    );
  });

  test('and none has been deleted', () {
    // A migration that vanishes takes a fresh `supabase db reset` out of step
    // with every database that already ran it, which is the same fault seen
    // from the other end.
    final Map<String, String> was = recorded();
    final Map<String, String> now = onDisk();

    final List<String> missing = <String>[
      for (final String name in was.keys)
        if (!now.containsKey(name)) name,
    ];
    expect(missing, isEmpty, reason: 'deleted migrations: $missing');
  });

  test('every migration on disk is recorded', () {
    // Otherwise the guard quietly stops covering whatever was added last,
    // which is always the file most likely to still be being edited.
    final Map<String, String> was = recorded();
    final List<String> unrecorded = <String>[
      for (final String name in onDisk().keys)
        if (!was.containsKey(name)) name,
    ];

    expect(
      unrecorded,
      isEmpty,
      reason:
          'Not in supabase/migrations/.applied.json:\n  '
          '${unrecorded.join('\n  ')}\n\n'
          'Add them with:\n'
          '  dart run tool/record_migrations.dart',
    );
  });
}
