import 'meal_plan.dart';

/// One continuous signed-in household session. Leaving it expires its actions,
/// even if the same person later signs in again.
class LogStateScope {
  LogStateScope({
    required this.userId,
    required this.householdId,
    bool Function()? stillCurrent,
  }) : _stillCurrent = stillCurrent;

  final String userId;
  final String householdId;
  final bool Function()? _stillCurrent;
  bool _active = true;

  bool get isActive {
    // A provider invalidation can precede its listeners' next frame. A caller
    // with live session state supplies this synchronous check at transaction
    // boundaries; a disposed owner also expires its actions permanently.
    if (_active && _stillCurrent != null) {
      try {
        if (!_stillCurrent()) _active = false;
      } catch (_) {
        _active = false;
      }
    }
    return _active;
  }

  void invalidate() => _active = false;
}

/// An in-memory receipt, accepted only by the repository that issued it.
/// The repository retains the exact storage record and its connection revision.
class LogStateChange {
  const LogStateChange({required this.before, required this.after});

  final MealPlanEntry before;
  final MealPlanEntry after;
}

enum UndoLogStateResult { restored, alreadyRestored, changed, expired }
