/// Who is allowed to start a sync pass, and what happens to the ones turned
/// away (spec §7.1, B01).
///
/// A pass used to be guarded by a bare `if (_running) return;`, which dropped
/// the request outright. A write made while a pass was in flight then waited
/// for something else to trigger one — and the obvious something is another
/// write, which the user may not make for hours.
///
/// One flag rather than a queue: coalescing a burst into a single rerun is the
/// whole point. Saving a recipe queues several rows, and several reruns for
/// one save would be worse than the bug.
///
/// Kept apart from the controller so the rule can be read and tested on its
/// own — the controller's own path needs a signed-in session, a live database
/// and a platform binding before it reaches this decision at all.
class SyncGate {
  bool _running = false;
  bool _requestedDuringPass = false;

  bool get isRunning => _running;

  /// Whether the caller should start a pass now.
  ///
  /// A refusal is remembered rather than discarded: [finish] will say that a
  /// rerun is owed.
  bool start() {
    if (_running) {
      _requestedDuringPass = true;
      return false;
    }
    _running = true;
    return true;
  }

  /// Ends the pass, and says whether one more is owed.
  ///
  /// Owed once, however many requests arrived — and cleared as it is
  /// reported, so a rerun that is itself uneventful ends the chain rather than
  /// starting another.
  bool finish() {
    _running = false;
    final bool again = _requestedDuringPass;
    _requestedDuringPass = false;
    return again;
  }
}
