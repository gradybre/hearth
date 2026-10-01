import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/cooking/cook_session.dart';

void main() {
  final DateTime start = DateTime.utc(2026, 10, 1, 18);
  CookTimer timer() => CookTimer(
    id: 'sauce-timer',
    label: 'Simmer sauce',
    duration: const Duration(minutes: 10),
    startedAt: start,
    stepId: 'sauce-step',
    stepNumber: 3,
  );

  test('adding time uses the running clock without restarting it', () {
    final DateTime now = start.add(const Duration(minutes: 4));
    final CookTimer changed = timer().addingTime(
      const Duration(minutes: 1),
      now: now,
    );
    expect(changed.remainingAt(now), const Duration(minutes: 7));
    expect(
      changed.remainingAt(now.add(const Duration(minutes: 2))),
      const Duration(minutes: 5),
    );
    expect(changed.startedAt, start);
    expect(changed.firesAt(), start.add(const Duration(minutes: 11)));
  });

  test('adding time to a paused timer keeps its frozen countdown', () {
    final CookTimer paused = timer().pausedAt(
      start.add(const Duration(minutes: 3)),
    );
    final DateTime later = start.add(const Duration(hours: 2));
    final CookTimer changed = paused.addingTime(
      const Duration(minutes: 5),
      now: later,
    );
    expect(changed.isPaused, isTrue);
    expect(changed.remainingAt(later), const Duration(minutes: 12));
    expect(
      changed.remainingAt(later.add(const Duration(days: 1))),
      const Duration(minutes: 12),
    );
    expect(changed.firesAt(), isNull);
  });

  test('adding time to a finished timer restarts from now', () {
    final DateTime later = start.add(const Duration(hours: 1));
    final CookTimer changed = timer().addingTime(
      const Duration(minutes: 5),
      now: later,
    );
    expect(changed.isPaused, isFalse);
    expect(changed.startedAt, later);
    expect(changed.remainingAt(later), const Duration(minutes: 5));
    expect(changed.firesAt(), later.add(const Duration(minutes: 5)));
  });

  test(
    'a restored timer paused past its deadline gains the full extension',
    () {
      // Older Pause callbacks could save this state between expiry and redraw.
      final CookTimer overdue = timer().pausedAt(
        start.add(const Duration(minutes: 12)),
      );
      final DateTime later = start.add(const Duration(hours: 1));
      expect(overdue.remainingAt(later), Duration.zero);
      final CookTimer changed = overdue.addingTime(
        const Duration(minutes: 1),
        now: later,
      );
      expect(changed.remainingAt(later), const Duration(minutes: 1));
      expect(
        changed.remainingAt(later.add(const Duration(hours: 1))),
        const Duration(minutes: 1),
      );
      expect(changed.isPaused, isTrue);
      expect(changed.firesAt(), isNull);
      expect(changed.id, overdue.id);
      expect(changed.stepId, overdue.stepId);
    },
  );

  for (final bool paused in <bool>[false, true]) {
    test('set time left preserves ${paused ? 'paused' : 'running'} state', () {
      final DateTime now = start.add(const Duration(minutes: 3));
      final CookTimer original = paused ? timer().pausedAt(now) : timer();
      final CookTimer changed = original.withTimeLeft(
        const Duration(minutes: 2, seconds: 15),
        now: now,
      );
      expect(changed.remainingAt(now), const Duration(minutes: 2, seconds: 15));
      expect(changed.isPaused, paused);
      expect(
        changed.remainingAt(now.add(const Duration(seconds: 15))),
        paused
            ? const Duration(minutes: 2, seconds: 15)
            : const Duration(minutes: 2),
      );
      expect(changed.id, original.id);
      expect(changed.label, original.label);
      expect(changed.stepId, original.stepId);
      expect(changed.stepNumber, original.stepNumber);
    });
  }

  test('setting time left on a finished timer starts that timer again', () {
    final DateTime later = start.add(const Duration(hours: 1));
    final CookTimer changed = timer().withTimeLeft(
      const Duration(seconds: 30),
      now: later,
    );
    expect(changed.id, 'sauce-timer');
    expect(changed.isDoneAt(later), isFalse);
    expect(changed.isDoneAt(later.add(const Duration(seconds: 30))), isTrue);
  });

  for (final Duration bad in <Duration>[
    Duration.zero,
    const Duration(seconds: -1),
  ]) {
    test('zero or negative time is rejected: $bad', () {
      expect(() => timer().addingTime(bad, now: start), throwsArgumentError);
      expect(() => timer().withTimeLeft(bad, now: start), throwsArgumentError);
    });
  }
}
