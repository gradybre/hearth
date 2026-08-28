/// Week and day helpers.
///
/// The week starts Monday (spec §5.6), and every date used as a key is
/// normalised to midnight local time so that "today" is a single value rather
/// than whatever moment the code happened to run.
library;

/// Strips the time from a date, leaving a stable day key.
DateTime dayKey(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// The Monday on or before [moment].
///
/// `DateTime.weekday` is 1 for Monday, so subtracting `weekday - 1` days walks
/// back to the start of the week without special-casing Sunday — which is the
/// bug this helper exists to prevent.
DateTime startOfWeek(DateTime moment) {
  final DateTime day = dayKey(moment);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// The seven days of the week containing [moment], Monday first.
List<DateTime> weekOf(DateTime moment) {
  final DateTime monday = startOfWeek(moment);
  return <DateTime>[
    for (int i = 0; i < DateTime.daysPerWeek; i++)
      // Adding days via DateTime rather than Duration keeps this correct
      // across daylight-saving boundaries, where a "day" is not 24 hours.
      DateTime(monday.year, monday.month, monday.day + i),
  ];
}

/// True when the two moments fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);
