import 'package:hearth/domain/planning/week.dart';
import 'package:test/test.dart';

void main() {
  group('startOfWeek (spec §5.6: the week starts Monday)', () {
    test('a Monday is its own week start', () {
      final DateTime monday = DateTime(2026, 8, 24);
      expect(monday.weekday, DateTime.monday);
      expect(startOfWeek(monday), monday);
    });

    test('mid-week walks back to Monday', () {
      // Thursday 27 August 2026.
      expect(startOfWeek(DateTime(2026, 8, 27)), DateTime(2026, 8, 24));
    });

    test('Sunday belongs to the week that began six days earlier', () {
      // The classic off-by-one: a Sunday must not start its own week.
      final DateTime sunday = DateTime(2026, 8, 30);
      expect(sunday.weekday, DateTime.sunday);
      expect(startOfWeek(sunday), DateTime(2026, 8, 24));
    });

    test('the time of day is stripped', () {
      expect(
        startOfWeek(DateTime(2026, 8, 27, 23, 59, 59)),
        DateTime(2026, 8, 24),
      );
    });

    test('works across a month boundary', () {
      // Tuesday 1 September 2026 belongs to the week starting 31 August.
      expect(startOfWeek(DateTime(2026, 9, 1)), DateTime(2026, 8, 31));
    });

    test('works across a year boundary', () {
      // Friday 1 January 2027 belongs to the week starting 28 December 2026.
      expect(startOfWeek(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });
  });

  group('weekOf', () {
    test('returns seven days, Monday first', () {
      final List<DateTime> week = weekOf(DateTime(2026, 8, 27));
      expect(week, hasLength(7));
      expect(week.first, DateTime(2026, 8, 24));
      expect(week.first.weekday, DateTime.monday);
      expect(week.last, DateTime(2026, 8, 30));
      expect(week.last.weekday, DateTime.sunday);
    });

    test('the days are consecutive', () {
      final List<DateTime> week = weekOf(DateTime(2026, 8, 27));
      for (int i = 1; i < week.length; i++) {
        expect(week[i].difference(week[i - 1]).inDays, 1);
      }
    });

    test('spans a month boundary without gaps', () {
      final List<DateTime> week = weekOf(DateTime(2026, 9, 1));
      expect(week.first, DateTime(2026, 8, 31));
      expect(week[1], DateTime(2026, 9, 1));
    });
  });

  group('dayKey and isSameDay', () {
    test('dayKey strips the time', () {
      expect(dayKey(DateTime(2026, 8, 27, 18, 30)), DateTime(2026, 8, 27));
    });

    test('two moments on one day are the same day', () {
      expect(
        isSameDay(DateTime(2026, 8, 27, 0, 1), DateTime(2026, 8, 27, 23, 59)),
        isTrue,
      );
    });

    test('a minute past midnight is a different day', () {
      expect(
        isSameDay(DateTime(2026, 8, 27, 23, 59), DateTime(2026, 8, 28, 0, 1)),
        isFalse,
      );
    });
  });

  group('calendarDaysBetween (spec §5.7, review F05)', () {
    test('counts dates, not hours', () {
      expect(
        calendarDaysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 9)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)),
        -1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 8)),
        0,
      );
    });

    test('ignores the time of day on either side', () {
      // The day screen compares one midnight key against another; nothing
      // else should be able to change the answer.
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 8, 23, 59),
          DateTime(2026, 3, 9, 0, 1),
        ),
        1,
        reason: 'two minutes apart, but a day apart on the calendar',
      );
    });

    test('crosses months and years without arithmetic of its own', () {
      expect(calendarDaysBetween(DateTime(2026, 2, 28), DateTime(2026, 3)), 1);
      expect(calendarDaysBetween(DateTime(2025, 12, 31), DateTime(2026)), 1);
      // 2028 is a leap year, so February has a 29th to cross.
      expect(calendarDaysBetween(DateTime(2028, 2, 28), DateTime(2028, 3)), 2);
    });

    test('over a daylight-saving change, where a day is not 24 hours', () {
      // The bug itself. Same shape as the `addDays` case below: CI runs in
      // UTC where every day really is 24 hours, so this can only fail on a
      // machine whose zone actually changes — which is why the convention is
      // *also* enforced by reading the source, in
      // test/architecture/calendar_arithmetic_test.dart.
      final List<DateTime> transitions = <DateTime>[];
      DateTime day = DateTime(2026);
      while (day.year == 2026) {
        final DateTime next = DateTime(day.year, day.month, day.day + 1);
        if (next.timeZoneOffset != day.timeZoneOffset) transitions.add(day);
        day = next;
      }

      if (transitions.isEmpty) {
        markTestSkipped('this machine\'s timezone has no daylight saving');
        return;
      }

      for (final DateTime before in transitions) {
        final DateTime after = DateTime(
          before.year,
          before.month,
          before.day + 1,
        );

        expect(
          calendarDaysBetween(before, after),
          1,
          reason: 'crossing $before counted the wrong number of days',
        );
        expect(
          calendarDaysBetween(after, before),
          -1,
          reason: 'crossing $before backwards counted the wrong number',
        );
      }

      // And the old spelling misses it on at least one of them, so the
      // assertions above are not passing by luck.
      expect(
        transitions.any((DateTime before) {
          final DateTime after = DateTime(
            before.year,
            before.month,
            before.day + 1,
          );
          return after.difference(before).inDays != 1;
        }),
        isTrue,
        reason: 'no transition in this zone actually shortens a day',
      );
    });
  });

  group('addDays (spec §5.7, R08)', () {
    test('crosses a month without arithmetic of its own', () {
      expect(addDays(DateTime(2026, 1, 30), 3), DateTime(2026, 2, 2));
    });

    test('and a year, and a leap day', () {
      expect(addDays(DateTime(2026, 12, 30), 3), DateTime(2027, 1, 2));
      expect(addDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    });

    test('walks backwards when asked to', () {
      expect(addDays(DateTime(2026, 3, 2), -3), DateTime(2026, 2, 27));
    });

    test('leaves a midnight key at midnight', () {
      final DateTime moved = addDays(DateTime(2026, 3, 1), 10);
      expect(moved.hour, 0);
      expect(moved.minute, 0);
    });

    test('over a daylight-saving change, where a day is not 24 hours', () {
      // The bug itself, on any machine whose zone actually changes. CI runs
      // in UTC, where every day really is 24 hours and this cannot fail —
      // which is why the convention is also enforced by reading the source,
      // in test/architecture/calendar_arithmetic_test.dart.
      final List<DateTime> transitions = <DateTime>[];
      DateTime day = DateTime(2026);
      while (day.year == 2026) {
        final DateTime next = DateTime(day.year, day.month, day.day + 1);
        if (next.timeZoneOffset != day.timeZoneOffset) transitions.add(day);
        day = next;
      }

      if (transitions.isEmpty) {
        markTestSkipped('this machine\'s timezone has no daylight saving');
        return;
      }

      for (final DateTime before in transitions) {
        final DateTime after = addDays(before, 1);
        final DateTime expected = DateTime(
          before.year,
          before.month,
          before.day + 1,
        );

        // The calendar date, not the hour. Some zones shift at midnight
        // itself — Chile, Cuba, Iran, Egypt — so one midnight a year does not
        // exist there and Dart normalises it to 01:00. The production code is
        // right in those zones too, because `dayKey` normalises identically
        // and the keys still compare equal; it was only ever the assertion
        // that assumed midnight always exists.
        expect(
          after,
          expected,
          reason: 'crossing $before gave $after, not $expected',
        );

        // And where there *is* a midnight to land on, the old way misses it —
        // so the assertion above is not passing by luck.
        if (expected.hour == 0) {
          expect(
            before.add(const Duration(days: 1)),
            isNot(expected),
            reason: 'a Duration of 24 hours should not agree here',
          );
        }
      }
    });
  });
}
