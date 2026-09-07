import 'package:flutter/foundation.dart';

import '../../domain/planning/meal_plan.dart';

/// Why the restaurant builder was opened, and what to do when it finishes
/// (spec §5.6, U04).
///
/// Building a meal from a menu starts on the day screen — you are standing in
/// a queue, on a particular day, about to eat a particular meal — and ends
/// three screens later in the recipe editor. Without carrying that, the
/// editor knows only that a recipe was written: it saves it and stops, and
/// the meal you were in the middle of logging is not logged. Worse, anything
/// that recovered the day and slot at the far end would recover *today's*, so
/// a dinner built for last Tuesday would silently become tonight's.
///
/// Passed through the routes rather than held in a provider on purpose. A
/// provider would outlive a cancelled build and be waiting, still set, the
/// next time the editor was opened from somewhere else entirely.
@immutable
class LoggingIntent {
  const LoggingIntent({
    required this.date,
    required this.slot,
    required this.eaten,
  });

  /// The day the meal belongs to. Never re-derived at the far end.
  final DateTime date;

  final MealSlot slot;

  /// Whether it was eaten, or is only planned.
  ///
  /// From the log sheet it was eaten — you are building it because you are
  /// about to eat it or just have. From the planner it is a plan.
  final bool eaten;

  /// What the button at the end of the build should say.
  ///
  /// Named for the meal rather than "Save": three screens after tapping "Ate
  /// out" it is worth saying what is about to happen, and that the day is not
  /// today's is the part most worth being explicit about.
  String get action => eaten ? 'Save and log $_slot' : 'Save and add to $_slot';

  String get _slot => switch (slot) {
    MealSlot.breakfast => 'breakfast',
    MealSlot.lunch => 'lunch',
    MealSlot.dinner => 'dinner',
    MealSlot.snack => 'snacks',
  };

  @override
  bool operator ==(Object other) =>
      other is LoggingIntent &&
      other.date == date &&
      other.slot == slot &&
      other.eaten == eaten;

  @override
  int get hashCode => Object.hash(date, slot, eaten);

  @override
  String toString() => 'LoggingIntent($date, $slot, eaten: $eaten)';
}
