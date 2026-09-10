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
/// The source with its comments blanked out, line numbers intact.
///
/// Both guards below read the file as text, and both of them explain the
/// mistake they are looking for by *writing it out* — so without this the
/// prose that documents the rule trips the rule. `calendarDaysBetween` was
/// reported as its own first offender.
///
/// Spaces rather than deletion, so a match's offset still names the right
/// line. Strings are not stripped: a `//` inside one is vanishingly rare
/// here and blanking it would be the more surprising behaviour.
String withoutComments(String source) {
  final StringBuffer out = StringBuffer();
  bool inBlock = false;
  for (final String line in source.split('\n')) {
    if (out.isNotEmpty) out.write('\n');
    String rest = line;
    final StringBuffer kept = StringBuffer();
    while (rest.isNotEmpty) {
      if (inBlock) {
        final int close = rest.indexOf('*/');
        if (close == -1) {
          kept.write(' ' * rest.length);
          rest = '';
        } else {
          kept.write(' ' * (close + 2));
          rest = rest.substring(close + 2);
          inBlock = false;
        }
        continue;
      }
      final int lineComment = rest.indexOf('//');
      final int blockOpen = rest.indexOf('/*');
      if (lineComment == -1 && blockOpen == -1) {
        kept.write(rest);
        rest = '';
      } else if (blockOpen != -1 &&
          (lineComment == -1 || blockOpen < lineComment)) {
        kept.write(rest.substring(0, blockOpen));
        rest = rest.substring(blockOpen);
        inBlock = true;
      } else {
        kept.write(rest.substring(0, lineComment));
        kept.write(' ' * (rest.length - lineComment));
        rest = '';
      }
    }
    out.write(kept);
  }
  return out.toString();
}

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

      final String source = withoutComments(entity.readAsStringSync());
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

  test('and no date is subtracted from another to count days', () {
    // The same fault read backwards, and the one the guard above was blind
    // to. `a.difference(b).inDays` measures *elapsed 24-hour spans*, so two
    // midnight keys a calendar day apart come to 0 on the 23-hour night —
    // and the day screen's header said "Today" on a day that was not.
    //
    // `addDays` already carries the reasoning at the top of week.dart. This
    // is the second spelling of the mistake it warns about, and until this
    // test existed nothing stopped it.
    final Directory lib = Directory('lib');

    // Anything that measures a real span of time is fine here: how long ago
    // something synced, how long a request has been waiting. It is only
    // counting *calendar days* that a Duration cannot do.
    final RegExp offending = RegExp(
      r'\.\s*difference\s*\([^;]{0,200}?\)\s*\.\s*inDays',
      multiLine: true,
    );

    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;

      final String source = withoutComments(entity.readAsStringSync());
      for (final RegExpMatch match in offending.allMatches(source)) {
        final int line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        final String text = source
            .substring(match.start, match.end)
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ');

        // UTC is the exemption, and it is the whole principle rather than a
        // whitelisted file: a UTC day is always twenty-four hours, so
        // subtracting two UTC dates *is* counting calendar days. That is how
        // `calendarDaysBetween` is implemented, and anything else rebuilding
        // its dates in UTC first is right for the same reason.
        if (text.contains('DateTime.utc')) continue;

        offenders.add('${entity.path}:$line  $text');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Counting calendar days with .difference().inDays is wrong on the '
          'two nights a year when a local day is 23 or 25 hours: yesterday '
          'comes out as today. Use calendarDaysBetween() from '
          'lib/domain/planning/week.dart, which compares the dates '
          'themselves:\n${offenders.join('\n')}',
    );
  });
}
