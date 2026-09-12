import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Records what each migration contains, so editing an applied one is caught.
///
/// Run after adding a migration:
///
/// ```bash
/// dart run tool/record_migrations.dart
/// ```
///
/// `test/architecture/migrations_are_history_test.dart` holds the repository
/// to this record. Adding a file is ordinary; *changing* one that is already
/// recorded is the thing being guarded against, because `supabase db push`
/// skips a version it has applied and the hosted database never sees it.
void main() {
  final Directory dir = Directory('supabase/migrations');
  final Map<String, String> hashes = <String, String>{
    for (final FileSystemEntity entity in dir.listSync())
      if (entity is File && entity.path.endsWith('.sql'))
        entity.uri.pathSegments.last: sha256
            .convert(entity.readAsBytesSync())
            .toString(),
  };

  final List<String> names = hashes.keys.toList()..sort();
  final String json = const JsonEncoder.withIndent('  ').convert(
    <String, String>{for (final String name in names) name: hashes[name]!},
  );
  File('${dir.path}/.applied.json').writeAsStringSync('$json\n');
  stdout.writeln('Recorded ${names.length} migrations.');
}
