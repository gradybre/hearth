import '../models/macros.dart';
import 'week.dart';

/// What one day of a week amounts to, from the week's point of view
/// (review §7.2).
///
/// Keeps genuine zero, missing saved history, an unlogged plan and an untouched
/// day apart. None of those can substitute for another in a weekly average.
enum DayLogState {
  /// Something was logged, and it came to something.
  logged,

  /// Something was logged and it came to nothing — a fast, stated.
  ///
  /// The distinction §7.2 asks for, and the one the week used to lose: this
  /// was filtered out with `!macros.isZero` and so left out of the average's
  /// denominator, which reported the other days' mean as the week's and was
  /// therefore higher than anybody ate.
  loggedAsNothing,

  /// Some saved intake is known, but at least one log lost its snapshot.
  loggedIncomplete,

  /// Logged meals exist, but none has its saved nutrition available.
  loggedUnavailable,

  /// On the plan, not yet eaten. A projection, not a result.
  plannedOnly,

  /// Nothing at all. Either it has not happened or nobody said.
  untouched,
}

/// One day, summarised for a row.
class WeekDay {
  const WeekDay({
    required this.date,
    required this.eaten,
    required this.planned,
    required this.loggedCount,
    required this.plannedCount,
    this.missingSnapshotCount = 0,
  });

  final DateTime date;

  /// Known saved intake. Zero can be a real logged amount or an additive
  /// placeholder for absent history — [state] is what tells those apart.
  final Macros eaten;

  /// What the unlogged plan would add if it were eaten as planned.
  final Macros planned;

  final int loggedCount;
  final int plannedCount;
  final int missingSnapshotCount;

  DayLogState get state {
    if (loggedCount > 0) {
      if (missingSnapshotCount >= loggedCount) {
        return DayLogState.loggedUnavailable;
      }
      if (missingSnapshotCount > 0) return DayLogState.loggedIncomplete;
      return eaten.isZero ? DayLogState.loggedAsNothing : DayLogState.logged;
    }
    return plannedCount > 0 ? DayLogState.plannedOnly : DayLogState.untouched;
  }

  /// Whether this day belongs in the week's average.
  ///
  /// A complete saved day counts, even when its amount is genuinely zero.
  /// A missing snapshot leaves that day's intake unavailable or incomplete,
  /// so neither it nor an untouched day belongs in the denominator.
  bool get countsTowardAverage => loggedCount > 0 && missingSnapshotCount == 0;

  bool isToday(DateTime now) => isSameDay(date, now);
}

/// Seven days, and what they come to together.
class WeekSummary {
  WeekSummary(this.days)
    : _counted = days
          .where((WeekDay d) => d.countsTowardAverage)
          .toList(growable: false);

  final List<WeekDay> days;

  /// The days in the denominator, worked out once.
  ///
  /// Three getters want this and a row rebuild asks all three, so computing
  /// it per call was three walks and three lists for one answer.
  final List<WeekDay> _counted;

  /// How many days have logged meals, including unavailable saved history.
  int get loggedDays => days.where((WeekDay day) => day.loggedCount > 0).length;

  /// Days with complete snapshot availability, including genuine logged zero.
  int get averagedDays => _counted.length;

  int get incompleteDays => days
      .where(
        (WeekDay day) => day.loggedCount > 0 && day.missingSnapshotCount > 0,
      )
      .length;

  /// Days with no logs at all. Incomplete logged days have their own count.
  ///
  /// Disclosed rather than assumed (review §7.2): an average over five days
  /// of a seven-day week reads as an average over seven unless it says
  /// otherwise.
  int get daysNotLogged => days.length - loggedDays;

  /// The mean of the logged days, or null when none are.
  ///
  /// An average rather than a sum: targets are daily, so a total of seven
  /// days against one day's target would be meaningless.
  Macros? get dailyAverage {
    final List<WeekDay> counted = _counted;
    if (counted.isEmpty) return null;
    return Macros.sum(counted.map((WeekDay d) => d.eaten))
        .scaledBy(1 / counted.length);
  }

  bool get isEmpty => loggedDays == 0;
}
