/// How a date reads in the planner (spec §5.6).
///
/// A bare day number is only legible next to the month it belongs to. The week
/// list showed "1" against a row that said nothing about September, which is
/// unreadable the moment a week straddles two months — and misleading rather
/// than merely terse, because the row above it might be the 30th of August.
library;

/// Month and day, the way a US kitchen writes it: "9/1" for the first of
/// September.
///
/// No leading zeros: "9/1" is how it is said out loud, and "09/01" is a form
/// only a computer asks for.
String shortDate(DateTime date) => '${date.month}/${date.day}';
