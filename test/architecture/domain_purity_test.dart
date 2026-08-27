import 'dart:io';

import 'package:test/test.dart';

/// Enforces the layering rule in CLAUDE.md: `lib/domain/` is pure Dart.
///
/// Keeping Flutter out of the domain is what makes the §9.1 unit tests cheap —
/// they run without a widget binding — and it stops UI concerns leaking into
/// the maths that macro accuracy depends on.
void main() {
  test('lib/domain contains no Flutter imports', () {
    final Directory domain = Directory('lib/domain');
    expect(
      domain.existsSync(),
      isTrue,
      reason:
          'lib/domain should exist; is the test running from the repo root?',
    );

    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in domain.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trim();
        final bool isDirective =
            line.startsWith('import ') || line.startsWith('export ');
        if (!isDirective) continue;
        if (line.contains('package:flutter/') ||
            line.contains('package:flutter_test/') ||
            line.contains('dart:ui')) {
          offenders.add('${entity.path}:${i + 1}  $line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'lib/domain must stay Flutter-free. Move UI concerns into '
          'lib/features or lib/app instead:\n${offenders.join('\n')}',
    );
  });
}
