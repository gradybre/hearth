import 'dart:io';

import 'package:test/test.dart';

/// A day is not twenty-four hours (spec §5.7, R08).
///
/// `lib/domain/planning/week.dart` has said so since it was written — `weekOf`
/// steps through dates with the `DateTime` constructor and carries a comment
/// explaining why. Four other places added days with a `Duration` anyway, and
/// on the two nights a year when a local day is 23 or 25 hours long, those
/// land an hour either side of midnight and the range covers the wrong day.
///
/// A boundary test would only catch this on a machine whose zone actually has
/// daylight saving — CI runs in UTC, where every day really is 24 hours and
/// the bug is invisible. So the convention is enforced by reading the source,
/// which works everywhere.
void main() {
  test('no date is advanced by a Duration of days', () {
    final Directory lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'lib/ should exist; is the test running from the repo root?',
    );

    // Bounds handed to a date picker, where a day either way is nothing and
    // the value is never used as a key.
    const Set<String> allowed = <String>{
      'lib/features/shopping/shopping_screen.dart',
    };

    final RegExp offending = RegExp(
      r'\.(add|subtract)\(\s*const\s+Duration\(\s*days:|'
      r'\.(add|subtract)\(\s*Duration\(\s*days:',
    );

    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (allowed.contains(entity.path)) continue;

      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (offending.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Adding days with a Duration is wrong on the two nights a year '
          'when a local day is not 24 hours long: the result lands at 01:00 '
          'or 23:00 and belongs to the wrong date. Use addDays() from '
          'lib/domain/planning/week.dart, which steps the calendar '
          'instead:\n${offenders.join('\n')}',
    );
  });
}
