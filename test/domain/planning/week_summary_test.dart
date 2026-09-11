import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/week_summary.dart';

/// What a week's seven days come to (review §7.2).
///
/// The rule the screen had wrong: it decided a day was logged by looking at
/// whether its macros were non-zero. A fast is a logged day whose macros are
/// zero, so it fell out of the denominator and the week reported the other
/// days' mean as the household's daily average — higher than anybody ate,
/// and silently.
void main() {
  final DateTime monday = DateTime(2026, 9, 7);

  WeekDay day(
    int offset, {
    Macros eaten = Macros.zero,
    Macros planned = Macros.zero,
    int loggedCount = 0,
    int plannedCount = 0,
  }) => WeekDay(
    date: monday.add(Duration(days: offset)),
    eaten: eaten,
    planned: planned,
    loggedCount: loggedCount,
    plannedCount: plannedCount,
  );

  const Macros aDay = Macros(kcal: 2000, proteinG: 150, carbG: 200, fatG: 70);

  group('what each day is', () {
    test('food logged is a logged day', () {
      expect(day(0, eaten: aDay, loggedCount: 3).state, DayLogState.logged);
    });

    test('nothing logged, deliberately, is also a logged day', () {
      // The case the screen lost. An entry exists and it says zero.
      final WeekDay fast = day(5, loggedCount: 1);
      expect(fast.state, DayLogState.loggedAsNothing);
      expect(fast.countsTowardAverage, isTrue);
    });

    test('a plan with nothing logged is a projection', () {
      expect(
        day(4, planned: aDay, plannedCount: 2).state,
        DayLogState.plannedOnly,
      );
    });

    test('and a day nobody touched is neither', () {
      final WeekDay empty = day(6);
      expect(empty.state, DayLogState.untouched);
      expect(empty.countsTowardAverage, isFalse);
    });

    test('a planned day does not count towards the average', () {
      // Nothing was eaten, so there is no number to average. Counting it as
      // a zero would drag the week down for a dinner that has not happened.
      expect(day(4, planned: aDay, plannedCount: 2).countsTowardAverage, false);
    });
  });

  group('the average', () {
    test('divides by the days that were logged, fast included', () {
      final WeekSummary week = WeekSummary(<WeekDay>[
        for (int i = 0; i < 4; i++) day(i, eaten: aDay, loggedCount: 3),
        day(4, planned: aDay, plannedCount: 1),
        day(5, loggedCount: 1),
        day(6),
      ]);

      expect(week.loggedDays, 5);
      // Four days at 2,000 and one at nothing is 1,600 a day, not 2,000.
      expect(week.dailyAverage!.kcal, closeTo(1600, 0.001));
      expect(week.dailyAverage!.proteinG, closeTo(120, 0.001));
    });

    test('and says how many days it could not see', () {
      final WeekSummary week = WeekSummary(<WeekDay>[
        for (int i = 0; i < 4; i++) day(i, eaten: aDay, loggedCount: 3),
        day(4, planned: aDay, plannedCount: 1),
        day(5, loggedCount: 1),
        day(6),
      ]);

      expect(week.daysNotLogged, 2);
    });

    test('is absent rather than zero when nothing was logged at all', () {
      // Zero is a claim about what was eaten. "Nobody said" is not.
      final WeekSummary week = WeekSummary(<WeekDay>[
        for (int i = 0; i < 7; i++) day(i),
      ]);

      expect(week.dailyAverage, isNull);
      expect(week.isEmpty, isTrue);
      expect(week.daysNotLogged, 7);
    });

    test('a week of fasts averages zero rather than nothing', () {
      // Seven logged days at zero is a real answer, and a different one from
      // seven days nobody logged.
      final WeekSummary week = WeekSummary(<WeekDay>[
        for (int i = 0; i < 7; i++) day(i, loggedCount: 1),
      ]);

      expect(week.isEmpty, isFalse);
      expect(week.loggedDays, 7);
      expect(week.dailyAverage!.kcal, 0);
    });
  });
}
