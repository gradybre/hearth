/// When to try the house again (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
///
/// Pure arithmetic over a clock and a random source, deliberately: a backoff
/// with a real timer in it can only be tested by waiting, and a policy tested
/// by waiting is a policy nobody re-tests after changing it.
///
/// §6.1 asks for three things that pull against each other, and the third is
/// the one usually left out:
///
///  * **bounded retry with jitter**, not an unbounded rapid loop — a phone
///    reconnecting in a tight loop against a Raspberry Pi is a denial of
///    service somebody built by accident;
///  * **a manual retry** that always works, because a person who has just
///    plugged the Pi back in should not be made to wait out a backoff;
///  * **invalid credentials halt retry entirely.** Nothing about waiting makes
///    a wrong token right, and on some setups repeated failures get the client
///    banned — so the screen asks for a new token instead of hammering.
library;

import 'dart:math';

import 'package:meta/meta.dart';

import 'ha_session.dart';

/// What to do after a connection attempt ended.
@immutable
sealed class ReconnectDecision {
  const ReconnectDecision();
}

/// Wait this long, then try again.
@immutable
class RetryAfter extends ReconnectDecision {
  const RetryAfter(this.delay, {required this.attempt});

  final Duration delay;

  /// Which attempt the *next* one will be, counting from 1.
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is RetryAfter && other.delay == delay && other.attempt == attempt;

  @override
  int get hashCode => Object.hash(delay, attempt);

  @override
  String toString() => 'RetryAfter(${delay.inMilliseconds}ms, #$attempt)';
}

/// Stop, and tell somebody. Retrying cannot help.
@immutable
class StopRetrying extends ReconnectDecision {
  const StopRetrying(this.because);

  final HaSessionFailure because;

  @override
  bool operator ==(Object other) =>
      other is StopRetrying && other.because == because;

  @override
  int get hashCode => because.hashCode;

  @override
  String toString() => 'StopRetrying(${because.name})';
}

/// How long to wait before trying again, and whether to bother.
///
/// Immutable: each decision returns the policy to use for the next one, so a
/// caller cannot accidentally share attempt counts between two connections, and
/// a test can hold two policies at different points at once.
@immutable
class ReconnectPolicy {
  const ReconnectPolicy({
    this.attempt = 0,
    this.first = const Duration(seconds: 1),
    this.ceiling = const Duration(minutes: 5),
  });

  /// How many failures have been seen. Zero on a fresh connection.
  final int attempt;

  /// The wait after the first failure.
  final Duration first;

  /// The longest wait, however many failures there have been.
  ///
  /// A ceiling rather than unbounded growth: a phone that has been in a
  /// pocket all day should come back in minutes, not in however long doubling
  /// got to. Five minutes is also short enough that a Pi rebooting overnight
  /// is reconnected before anybody looks at the app.
  final Duration ceiling;

  /// What to do about [failure].
  ///
  /// [random] is injected so jitter is testable. Defaulting it inside the
  /// method rather than the constructor keeps the class `const`.
  ReconnectDecision after(HaSessionException failure, {Random? random}) {
    // §6.1: invalid credentials halt retry. This is checked before anything
    // else, because a rejected token with a small attempt count would
    // otherwise look like an ordinary early failure.
    if (!failure.isRetryable) return StopRetrying(failure.failure);

    final int next = attempt + 1;

    // Doubling, capped. Computed in milliseconds because Duration * int is
    // exact and doubling a Duration repeatedly is not obviously so.
    final int uncapped = first.inMilliseconds * (1 << min(attempt, 30));
    final int capped = min(uncapped, ceiling.inMilliseconds);

    // Full jitter: a uniform pick from zero to the capped delay, rather than
    // the delay plus a wobble. Two phones that lost the same Wi-Fi at the same
    // moment otherwise retry in lockstep for ever, and a household with two
    // phones is exactly this app's case.
    final Random source = random ?? Random();
    final int delay = capped <= 0 ? 0 : source.nextInt(capped + 1);

    return RetryAfter(Duration(milliseconds: delay), attempt: next);
  }

  /// The policy to use after [decision].
  ReconnectPolicy then(ReconnectDecision decision) => switch (decision) {
    RetryAfter(:final int attempt) => ReconnectPolicy(
      attempt: attempt,
      first: first,
      ceiling: ceiling,
    ),
    StopRetrying() => this,
  };

  /// A person pressed Retry, or the app came back to the foreground.
  ///
  /// The count goes back to zero, so a deliberate attempt is immediate. §6.1
  /// asks for a manual retry beside the automatic one, and a manual retry that
  /// still waits out five minutes is not one — somebody who has just plugged
  /// the Pi back in knows something the backoff does not.
  ReconnectPolicy get restarted =>
      ReconnectPolicy(first: first, ceiling: ceiling);

  @override
  bool operator ==(Object other) =>
      other is ReconnectPolicy &&
      other.attempt == attempt &&
      other.first == first &&
      other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(attempt, first, ceiling);
}
