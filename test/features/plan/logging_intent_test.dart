import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/features/plan/logging_intent.dart';

/// Carrying the meal through the restaurant builder (spec §5.6, U04).
void main() {
  final DateTime lastTuesday = DateTime(2026, 9, 1);

  test('defaults follow calendar dates, not elapsed hours', () {
    final DateTime today = DateTime(2026, 3, 8, 23, 30);
    expect(
      LoggingIntent.forMeal(
        date: DateTime(2026, 3, 9),
        slot: MealSlot.dinner,
        today: today,
      ).eaten,
      isFalse,
    );
    expect(
      LoggingIntent.forMeal(
        date: DateTime(2026, 3, 8, 23, 59),
        slot: MealSlot.dinner,
        today: today,
      ).eaten,
      isTrue,
    );
    expect(
      LoggingIntent.forMeal(
        date: DateTime(2026, 3, 7),
        slot: MealSlot.dinner,
        today: today,
      ).eaten,
      isTrue,
    );
  });

  test('says what is about to happen, and to which meal', () {
    expect(
      LoggingIntent(date: _anyDay, slot: MealSlot.lunch, eaten: true).action,
      'Save and log lunch',
    );
    expect(
      LoggingIntent(date: _anyDay, slot: MealSlot.dinner, eaten: false).action,
      'Save and add to dinner',
    );
  });

  test('every slot has a word, including the one whose name is plural', () {
    for (final MealSlot slot in MealSlot.values) {
      final String action = LoggingIntent(
        date: lastTuesday,
        slot: slot,
        eaten: true,
      ).action;

      expect(action, startsWith('Save and log '));
      expect(
        action,
        isNot(contains('MealSlot')),
        reason: 'the enum leaked into a button label',
      );
    }
  });

  test('is a value, so a route can carry it and be compared', () {
    expect(
      LoggingIntent(date: lastTuesday, slot: MealSlot.dinner, eaten: true),
      LoggingIntent(date: lastTuesday, slot: MealSlot.dinner, eaten: true),
    );
    expect(
      LoggingIntent(date: lastTuesday, slot: MealSlot.dinner, eaten: true),
      isNot(
        LoggingIntent(
          date: DateTime(2026, 9, 8),
          slot: MealSlot.dinner,
          eaten: true,
        ),
      ),
    );
  });
}

final DateTime _anyDay = DateTime.utc(2026, 9, 1);
