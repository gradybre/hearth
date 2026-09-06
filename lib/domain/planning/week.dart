/// Week and day helpers.
///
/// The week starts Monday (spec §5.6), and every date used as a key is
/// normalised to midnight local time so that "today" is a single value rather
/// than whatever moment the code happened to run.
library;

/// Strips the time from a date, leaving a stable day key.
DateTime dayKey(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// [days] later than [date], on the calendar rather than on the clock.
///
/// A local day is 23 or 25 hours long on the two nights a year that daylight
/// saving changes, so adding `Duration(days: n)` — which is exactly `n × 24`
/// hours — lands an hour either side of midnight and belongs to the wrong
/// date. Every date in this app is a midnight key, so that is not a display
/// nicety: it is the difference between Sunday's plan and Monday's.
///
/// The `DateTime` constructor normalises overflow, so this crosses months and
/// years without arithmetic of its own, and negative [days] walk backwards.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// The Monday on or before [moment].
///
/// `DateTime.weekday` is 1 for Monday, so stepping back `weekday - 1` days
/// walks to the start of the week without special-casing Sunday — which is
/// the bug this helper exists to prevent.
DateTime startOfWeek(DateTime moment) {
  final DateTime day = dayKey(moment);
  return addDays(day, -(day.weekday - DateTime.monday));
}

/// The seven days of the week containing [moment], Monday first.
List<DateTime> weekOf(DateTime moment) {
  final DateTime monday = startOfWeek(moment);
  return <DateTime>[
    for (int i = 0; i < DateTime.daysPerWeek; i++) addDays(monday, i),
  ];
}

/// True when the two moments fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);
