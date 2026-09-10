/// How a date reads in the planner (spec §5.6).
///
/// A bare day number is only legible next to the month it belongs to. The week
/// list showed "1" against a row that said nothing about September, which is
/// unreadable the moment a week straddles two months — and misleading rather
/// than merely terse, because the row above it might be the 30th of August.
library;

import 'week.dart';

/// Month and day, the way a US kitchen writes it: "9/1" for the first of
/// September.
///
/// No leading zeros: "9/1" is how it is said out loud, and "09/01" is a form
/// only a computer asks for.
String shortDate(DateTime date) => '${date.month}/${date.day}';

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The day of the week, spelled out.
///
/// Here rather than in each screen that needs it: three widgets carried a
/// private copy of this list, and a fourth was about to.
String weekdayName(DateTime date) => _weekdays[date.weekday - 1];

/// The month, spelled out.
String monthName(DateTime date) => _months[date.month - 1];

/// "Today", "Yesterday", "Tomorrow" — or null, for a day none of those name.
///
/// Counted on the calendar, never in elapsed hours: a local day is 23 or 25
/// of them twice a year, and `difference(...).inDays` made the day screen
/// call yesterday "Today" on the shorter one (review F05). [today] is
/// injectable so the rule can be tested without a clock.
///
/// Null rather than a fallback string, because the callers want different
/// ones — a header wants the weekday alone, a logging sheet wants the date
/// with it.
String? relativeDay(DateTime date, {DateTime? today}) =>
    switch (calendarDaysBetween(today ?? DateTime.now(), date)) {
      0 => 'Today',
      -1 => 'Yesterday',
      1 => 'Tomorrow',
      _ => null,
    };
