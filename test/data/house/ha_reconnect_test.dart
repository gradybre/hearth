import 'dart:math';

import 'package:hearth/data/house/ha_reconnect.dart';
import 'package:hearth/data/house/ha_session.dart';
import 'package:test/test.dart';

/// When to try the house again (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
void main() {
  const HaSessionException lost = HaSessionException(
    HaSessionFailure.connectionLost,
    'gone',
  );
  const HaSessionException rejected = HaSessionException(
    HaSessionFailure.credentialsRejected,
    'no',
  );

  /// Always picks the top of the range, so the cap is readable.
  Random ceilingPicker() => _Fixed(1.0);

  /// Always picks the bottom.
  Random floorPicker() => _Fixed(0.0);

  group('a wrong token is not a waiting problem', () {
    test('so it stops rather than backing off', () {
      // §6.1: invalid credentials halt retry. Nothing about waiting makes a
      // wrong token right, and on some setups hammering gets a client banned.
      expect(
        const ReconnectPolicy().after(rejected),
        const StopRetrying(HaSessionFailure.credentialsRejected),
      );
    });

    test('even on the very first failure', () {
      // Checked before the attempt count, or a rejected token on attempt one
      // looks like an ordinary early failure and gets retried.
      const ReconnectPolicy fresh = ReconnectPolicy();
      expect(fresh.attempt, 0);
      expect(fresh.after(rejected), isA<StopRetrying>());
    });

    test('and a lost connection is retried', () {
      expect(const ReconnectPolicy().after(lost), isA<RetryAfter>());
    });
  });

  group('the wait doubles, within reason', () {
    test('from the first delay', () {
      final RetryAfter first = const ReconnectPolicy().after(
        lost,
        random: ceilingPicker(),
      ) as RetryAfter;
      expect(first.delay, const Duration(seconds: 1));
      expect(first.attempt, 1);
    });

    test('and again each time', () {
      ReconnectPolicy policy = const ReconnectPolicy();
      final List<int> waits = <int>[];
      for (int i = 0; i < 5; i++) {
        final RetryAfter next =
            policy.after(lost, random: ceilingPicker()) as RetryAfter;
        waits.add(next.delay.inSeconds);
        policy = policy.then(next);
      }
      expect(waits, <int>[1, 2, 4, 8, 16]);
    });

    test('but never past the ceiling', () {
      // A phone in a pocket all day should come back in minutes, not in
      // however long doubling got to.
      ReconnectPolicy policy = const ReconnectPolicy();
      for (int i = 0; i < 40; i++) {
        policy = policy.then(policy.after(lost, random: ceilingPicker()));
      }
      final RetryAfter next =
          policy.after(lost, random: ceilingPicker()) as RetryAfter;
      expect(next.delay, const Duration(minutes: 5));
    });

    test('and the arithmetic does not overflow on a very long outage', () {
      // Shifting by the attempt count is fine until it is not. 1 << 64 is 0,
      // which would turn the longest outage into the shortest wait.
      const ReconnectPolicy weeksIn = ReconnectPolicy(attempt: 1000);
      final RetryAfter next =
          weeksIn.after(lost, random: ceilingPicker()) as RetryAfter;
      expect(next.delay, const Duration(minutes: 5));
    });
  });

  group('jitter, because a household has two phones', () {
    test('spreads the wait across the whole window', () {
      // Full jitter rather than a delay plus a wobble: two phones that lost
      // the same Wi-Fi at the same moment otherwise retry in lockstep for
      // ever, which is this app's actual case.
      const ReconnectPolicy policy = ReconnectPolicy(attempt: 4);
      final RetryAfter low =
          policy.after(lost, random: floorPicker()) as RetryAfter;
      final RetryAfter high =
          policy.after(lost, random: ceilingPicker()) as RetryAfter;

      expect(low.delay, Duration.zero);
      expect(high.delay, const Duration(seconds: 16));
    });

    test('and two policies at the same point do not agree', () {
      // The property that matters, asserted without pinning the generator:
      // across many draws the delays are not all identical.
      const ReconnectPolicy policy = ReconnectPolicy(attempt: 6);
      final Set<int> seen = <int>{};
      for (int i = 0; i < 40; i++) {
        seen.add(
          (policy.after(
            lost,
            random: Random(i),
          ) as RetryAfter).delay.inMilliseconds,
        );
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('a person pressing Retry knows something the backoff does not', () {
    test('so the wait goes back to the beginning', () {
      // Somebody who has just plugged the Pi back in should not be made to
      // wait out five minutes. A manual retry that still waits is not one.
      ReconnectPolicy policy = const ReconnectPolicy();
      for (int i = 0; i < 10; i++) {
        policy = policy.then(policy.after(lost, random: ceilingPicker()));
      }
      expect(policy.attempt, 10);

      final ReconnectPolicy afterTap = policy.restarted;
      expect(afterTap.attempt, 0);
      expect(
        (afterTap.after(lost, random: ceilingPicker()) as RetryAfter).delay,
        const Duration(seconds: 1),
      );
    });

    test('and the configured shape survives the restart', () {
      const ReconnectPolicy tuned = ReconnectPolicy(
        attempt: 5,
        first: Duration(milliseconds: 250),
        ceiling: Duration(seconds: 30),
      );
      expect(tuned.restarted.first, const Duration(milliseconds: 250));
      expect(tuned.restarted.ceiling, const Duration(seconds: 30));
    });
  });

  group('the policy is a value, not a counter somebody shares', () {
    test('so advancing one does not advance another', () {
      // Two connections must not share an attempt count. Immutability is what
      // makes that impossible rather than merely unlikely.
      const ReconnectPolicy start = ReconnectPolicy();
      final ReconnectPolicy advanced = start.then(
        start.after(lost, random: ceilingPicker()),
      );

      expect(start.attempt, 0);
      expect(advanced.attempt, 1);
    });

    test('and stopping leaves the policy where it was', () {
      const ReconnectPolicy policy = ReconnectPolicy(attempt: 3);
      expect(policy.then(policy.after(rejected)).attempt, 3);
    });
  });
}

/// A `Random` that always returns the same fraction of the range.
///
/// Not `Random(seed)`: a seeded generator pins the test to the implementation's
/// exact call pattern, so adding one unrelated draw later reshuffles every
/// expectation. This says what the test means — the top of the window, or the
/// bottom.
class _Fixed implements Random {
  _Fixed(this.fraction);

  final double fraction;

  @override
  int nextInt(int max) => ((max - 1) * fraction).round().clamp(0, max - 1);

  @override
  double nextDouble() => fraction;

  @override
  bool nextBool() => fraction >= 0.5;
}
