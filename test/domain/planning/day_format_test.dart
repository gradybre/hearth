import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/planning/day_format.dart';

/// How a date reads (spec §5.6, review F05).
void main() {
  final DateTime tuesday = DateTime(2026, 9, 8);

  test('a weekday and a month are spelled out', () {
    expect(weekdayName(tuesday), 'Tuesday');
    expect(monthName(tuesday), 'September');
    expect(weekdayName(DateTime(2026, 9, 13)), 'Sunday');
    expect(monthName(DateTime(2026)), 'January');
    expect(monthName(DateTime(2026, 12, 31)), 'December');
  });

  group('relativeDay', () {
    test('names the three days worth naming', () {
      expect(relativeDay(tuesday, today: tuesday), 'Today');
      expect(relativeDay(DateTime(2026, 9, 7), today: tuesday), 'Yesterday');
      expect(relativeDay(DateTime(2026, 9, 9), today: tuesday), 'Tomorrow');
    });

    test('and answers null for the rest, rather than guessing one', () {
      // The callers want different fallbacks — a header wants the weekday
      // alone, the logging sheet wants a date with it — so this refuses to
      // pick one for them.
      expect(relativeDay(DateTime(2026, 9, 10), today: tuesday), isNull);
      expect(relativeDay(DateTime(2026, 9, 6), today: tuesday), isNull);
    });

    test('ignores the time of day on either side', () {
      expect(
        relativeDay(
          DateTime(2026, 9, 7, 23, 59),
          today: DateTime(2026, 9, 8, 0, 1),
        ),
        'Yesterday',
      );
    });

    test('crosses a month and a year boundary', () {
      expect(
        relativeDay(DateTime(2026, 8, 31), today: DateTime(2026, 9)),
        'Yesterday',
      );
      expect(
        relativeDay(DateTime(2026), today: DateTime(2025, 12, 31)),
        'Tomorrow',
      );
    });
  });
}
