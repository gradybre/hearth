import '../models/macros.dart';
import 'week.dart';

/// What one day of a week amounts to, from the week's point of view
/// (review §7.2).
///
/// Four states rather than two, because "nothing" is three different facts
/// and the week has to keep them apart. Somebody who fasted on Saturday
/// logged their Saturday; somebody who forgot did not; and a Friday that has
/// not happened yet is neither.
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
  });

  final DateTime date;

  /// What was logged. Zero both when nothing was logged and when what was
  /// logged came to nothing — [state] is what tells those apart.
  final Macros eaten;

  /// What the unlogged plan would add if it were eaten as planned.
  final Macros planned;

  final int loggedCount;
  final int plannedCount;

  DayLogState get state {
    if (loggedCount > 0) {
      return eaten.isZero ? DayLogState.loggedAsNothing : DayLogState.logged;
    }
    return plannedCount > 0 ? DayLogState.plannedOnly : DayLogState.untouched;
  }

  /// Whether this day belongs in the week's average.
  ///
  /// Having logged is the test, not having eaten. A day nobody logged cannot
  /// be averaged — there is no number — but a day logged as nothing has a
  /// number, and it is zero.
  bool get countsTowardAverage => loggedCount > 0;

  bool isToday(DateTime now) => isSameDay(date, now);
}

/// Seven days, and what they come to together.
class WeekSummary {
  const WeekSummary(this.days);

  final List<WeekDay> days;

  List<WeekDay> get _counted =>
      days.where((WeekDay d) => d.countsTowardAverage).toList(growable: false);

  /// How many days are in the average's denominator.
  int get loggedDays => _counted.length;

  /// How many are not, and so are quietly missing from it.
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
