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
}
