/// Keeps the screen awake while cooking (spec §5.2).
///
/// An interface rather than a direct call so cook-along is testable without a
/// platform channel, and so a widget test does not have to pretend to be a
/// phone to exercise the screen it cares about.
abstract interface class ScreenKeeper {
  /// Asks the OS not to dim or lock the screen.
  Future<void> keepAwake();

  /// Hands the screen back. Must be called when cook mode ends, including
  /// when it ends by the user backing out — a phone left awake in a pocket is
  /// a flat battery by evening.
  Future<void> release();
}

/// A cook timer alert that survives the app being backgrounded (spec §5.2).
///
/// Cooking is one of the two low-signal moments the app is built around: the
/// phone goes face down on the counter and the cook walks away. An in-app
/// countdown cannot reach them there, so the alert has to be scheduled with
/// the OS ahead of time rather than fired when the timer "notices".
abstract interface class TimerAlerts {
  /// Whether the user has granted permission to alert them.
  ///
  /// Asked for at the moment the first timer starts, not at app launch: a
  /// permission prompt makes sense standing at the stove and is noise on a
  /// first run.
  Future<bool> requestPermission();

  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  });

  /// Cancels a scheduled alert — the timer was dismissed, paused, or the
  /// session ended.
  Future<void> cancel(String id);

  Future<void> cancelAll();
}
