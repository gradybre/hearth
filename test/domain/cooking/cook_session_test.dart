import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

final DateTime t0 = DateTime.utc(2026, 8, 28, 18);

CookSession aSession({int steps = 4}) => CookSession(
  recipe: aRecipe(
    steps: <RecipeStep>[
      for (int i = 1; i <= steps; i++) aStep('Step $i', stepNumber: i),
    ],
  ),
);

CookTimer aTimer({
  String id = 'timer-1',
  Duration duration = const Duration(minutes: 10),
  DateTime? startedAt,
}) => CookTimer(
  id: id,
  label: 'Simmer the sauce',
  duration: duration,
  startedAt: startedAt ?? t0,
);

void main() {
  group('timers are wall-clock, not ticked', () {
    test('remaining time is derived from when it started', () {
      // A counter ticked once a frame stops when the app is backgrounded —
      // which is exactly when the cook puts the phone down and walks away.
      final CookTimer timer = aTimer(duration: const Duration(minutes: 10));

      expect(
        timer.remainingAt(t0.add(const Duration(minutes: 4))),
        const Duration(minutes: 6),
      );
    });

    test('a timer left running while backgrounded is right on return', () {
      final CookTimer timer = aTimer(duration: const Duration(minutes: 10));
      final DateTime backFromTheKitchen = t0.add(const Duration(minutes: 25));

      expect(timer.isDoneAt(backFromTheKitchen), isTrue);
      expect(timer.remainingAt(backFromTheKitchen), Duration.zero);
      expect(timer.overdueBy(backFromTheKitchen), const Duration(minutes: 15));
    });

    test('remaining never goes negative', () {
      final CookTimer timer = aTimer(duration: const Duration(minutes: 1));
      expect(
        timer.remainingAt(t0.add(const Duration(hours: 3))),
        Duration.zero,
      );
    });

    test(
      'it reports when it will fire, for an alert that outlives the app',
      () {
        final CookTimer timer = aTimer(duration: const Duration(minutes: 10));
        expect(timer.firesAt(), t0.add(const Duration(minutes: 10)));
      },
    );
  });

  group('pausing', () {
    test('freezes the remaining time', () {
      final CookTimer running = aTimer(duration: const Duration(minutes: 10));
      final CookTimer paused = running.pausedAt(
        t0.add(const Duration(minutes: 3)),
      );

      expect(paused.isPaused, isTrue);
      expect(
        paused.remainingAt(t0.add(const Duration(hours: 2))),
        const Duration(minutes: 7),
        reason: 'a paused timer must not keep running',
      );
    });

    test('resuming keeps the elapsed time rather than starting over', () {
      final CookTimer paused = aTimer(duration: const Duration(minutes: 10))
          .pausedAt(t0.add(const Duration(minutes: 3)));

      final DateTime later = t0.add(const Duration(hours: 1));
      final CookTimer resumed = paused.resumedAt(later);

      expect(resumed.isPaused, isFalse);
      expect(resumed.remainingAt(later), const Duration(minutes: 7));
      expect(
        resumed.remainingAt(later.add(const Duration(minutes: 2))),
        const Duration(minutes: 5),
      );
    });

    test('a paused timer has nothing to schedule', () {
      expect(aTimer().pausedAt(t0).firesAt(), isNull);
    });
  });

  group('several timers at once (spec §5.2)', () {
    test('sauce, pasta, and oven run side by side', () {
      final CookSession session = aSession()
          .addTimer(aTimer(id: 'sauce', duration: const Duration(minutes: 20)))
          .addTimer(aTimer(id: 'pasta', duration: const Duration(minutes: 9)))
          .addTimer(aTimer(id: 'oven', duration: const Duration(minutes: 40)));

      expect(session.timers, hasLength(3));
    });

    test('the most overdue rings first', () {
      final CookSession session = aSession()
          .addTimer(aTimer(id: 'pasta', duration: const Duration(minutes: 9)))
          .addTimer(aTimer(id: 'sauce', duration: const Duration(minutes: 5)))
          .addTimer(aTimer(id: 'oven', duration: const Duration(minutes: 40)));

      final List<CookTimer> ringing = session.ringingAt(
        t0.add(const Duration(minutes: 10)),
      );

      expect(ringing.map((CookTimer t) => t.id), <String>[
        'sauce',
        'pasta',
      ], reason: 'the oven has not gone off yet');
    });

    test('a paused timer never rings', () {
      final CookSession session = aSession().addTimer(
        aTimer(duration: const Duration(minutes: 1)).pausedAt(t0),
      );
      expect(session.ringingAt(t0.add(const Duration(hours: 1))), isEmpty);
    });

    test('dismissing one leaves the others running', () {
      final CookSession session = aSession()
          .addTimer(aTimer(id: 'sauce'))
          .addTimer(aTimer(id: 'pasta'))
          .removeTimer('sauce');

      expect(session.timers.single.id, 'pasta');
    });
  });

  group('steps', () {
    test('advancing past the last step stays put', () {
      // Tap-anywhere-to-advance means a stray brush at the end must not throw
      // the cook out of the session they are still using.
      CookSession session = aSession(steps: 2).next().next().next();
      expect(session.currentStep, 1);

      session = session.previous().previous().previous();
      expect(session.currentStep, 0);
    });

    test('checking a step moves on with it', () {
      final CookSession session = aSession();
      final CookSession after = session.check(session.steps.first);

      expect(after.isChecked(after.steps.first), isTrue);
      expect(after.currentStep, 1);
    });

    test('checking without advancing is possible for going back over one', () {
      final CookSession session = aSession().goTo(2);
      final CookSession after = session.check(
        session.steps.first,
        advance: false,
      );
      expect(after.currentStep, 2);
    });

    test('unchecking leaves the position alone', () {
      final CookSession session = aSession();
      final CookSession after = session
          .check(session.steps.first)
          .uncheck(session.steps.first);

      expect(after.isChecked(after.steps.first), isFalse);
      expect(after.currentStep, 1);
    });

    test('the session is complete only once every step is ticked', () {
      CookSession session = aSession(steps: 3);
      expect(session.isComplete, isFalse);

      for (final RecipeStep step in session.steps) {
        session = session.check(step, advance: false);
      }
      expect(session.isComplete, isTrue);
      expect(session.checkedCount, 3);
    });

    test('a recipe with no steps is never "complete"', () {
      // Otherwise an empty recipe would offer to log itself the moment it
      // opened.
      expect(aSession(steps: 0).isComplete, isFalse);
      expect(aSession(steps: 0).step, isNull);
    });
  });

  group('the snapshot (spec §5.2)', () {
    test('the session keeps the recipe it started with', () {
      // A partner editing the shared recipe mid-cook must not move step 4
      // while you are standing at the stove reading it.
      final CookSession session = aSession(steps: 3);
      final Recipe edited = session.recipe.copyWith(title: 'Edited by partner');

      expect(session.recipe.title, isNot(edited.title));
      expect(session.steps, hasLength(3));
    });
  });
}
