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

    // Exempt by line rather than by file: the two offenders here are the
    // bounds handed to a date picker, where a day either way is nothing and
    // the value is never used as a key. Exempting the whole file would also
    // exempt the line six below them that sets the shopping range from what
    // the picker returned, which is exactly a date key.
    const Map<String, List<String>> allowed = <String, List<String>>{
      'lib/features/shopping/shopping_screen.dart': <String>[
        'firstDate:',
        'lastDate:',
      ],
    };

    // Matched against the whole file rather than line by line, because
    // `dart format` wraps a call the moment it passes eighty columns and a
    // per-line pattern then sees only `.add(` on one line and the `Duration`
    // on the next.
    //
    // Hours count too when they are a multiple of a day: `Duration(hours: 24)`
    // is the same mistake spelled differently. Smaller amounts of hours are
    // ordinary elapsed time and are left alone.
    //
    // What this cannot see is a `Duration` held in a variable and added
    // later. Said plainly rather than papered over: the guard covers the
    // shape the mistake has actually taken every time so far, and the
    // boundary test in test/domain/planning/week_test.dart covers the
    // behaviour itself wherever the machine's zone has daylight saving.
    final RegExp offending = RegExp(
      r'\.\s*(add|subtract)\s*\(\s*(const\s+)?Duration\s*\(\s*'
      r'(days\s*:|hours\s*:\s*(24|48|72|96|120|168)\b|hours\s*:\s*\d+\s*\*\s*24\b)',
      multiLine: true,
    );

    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;

      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in offending.allMatches(source)) {
        final int line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        final String text = source
            .substring(match.start, match.end)
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ');

        final List<String>? exemptions = allowed[entity.path];
        if (exemptions != null) {
          // The matched line alone, not the statement around it. Scoped to
          // the statement, an exemption for a date picker's `firstDate:`
          // covered every other argument in the same call — including one
          // that really is a date key. Fails closed: if these ever wrap onto
          // two lines the exemption stops matching and someone has to look.
          final int from = source.lastIndexOf('\n', match.start) + 1;
          final int end = source.indexOf('\n', match.start);
          final String line = source.substring(
            from,
            end == -1 ? source.length : end,
          );
          if (exemptions.any(line.contains)) continue;
        }

        offenders.add('${entity.path}:$line  $text');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Adding days with a Duration is wrong on the two nights a year '
          'when a local day is not 24 hours long: the result lands beside '
          'midnight and belongs to the wrong date. Use addDays() from '
          'lib/domain/planning/week.dart, which steps the calendar '
          'instead:\n${offenders.join('\n')}',
    );
  });
}
