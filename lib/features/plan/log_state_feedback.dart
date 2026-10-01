import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/widgets/undo_snackbar.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/planning/log_state_change.dart';

/// Expected refusal at the tap (for example, the source was just deleted).
class LogStateUnavailable implements Exception {
  const LogStateUnavailable(this.message);
  final String message;
}

/// Feedback belongs to the app messenger, not the row/route which started it.
/// Each built button owns one intent: retained and rapid callbacks cannot issue
/// another action after it succeeds. Retry repeats only a failed transaction.
class LogStateFeedback {
  LogStateFeedback(BuildContext context, {required this.entryId})
    : _messenger = ScaffoldMessenger.of(context),
      _accessibleNavigation = MediaQuery.accessibleNavigationOf(context),
      container = ProviderScope.containerOf(context, listen: false) {
    _session = _sessions[container] ??= _LogSession(container);
    scope = _session.current;
    repository = container.read(planRepositoryProvider);
  }

  static final Expando<_LogSession> _sessions = Expando<_LogSession>();
  final ScaffoldMessengerState _messenger;
  final bool _accessibleNavigation;
  final ProviderContainer container;
  final String entryId;
  late final _LogSession _session;
  late final LogStateScope scope;
  late final PlanRepository repository;
  bool _busy = false;
  bool _completed = false;
  bool _undoBusy = false;

  bool get _current => _messenger.mounted && scope.isActive;

  Future<void> run(Future<LogStateChange?> Function() change) async {
    if (_busy || _completed) return;
    if (!_current) {
      _expired();
      return;
    }
    if (!_claimEntry()) return;
    _busy = true;
    try {
      final LogStateChange? receipt = await change();
      if (!_current) {
        _expired();
        return;
      }
      if (receipt == null) {
        _completed = true;
        _show('This meal changed. Nothing was changed.');
        return;
      }
      _completed = true;
      _refresh();
      _show(
        receipt.after.isLogged ? 'Meal logged.' : 'Meal unlogged.',
        action: 'Undo',
        onAction: () => _undo(receipt),
      );
    } on LogStateUnavailable catch (error) {
      if (_current) {
        _show(error.message);
      } else {
        _expired();
      }
    } catch (_) {
      if (_current) {
        _show(
          'Could not save the change. Try again.',
          action: 'Retry',
          onAction: () => run(change),
        );
      } else {
        _expired();
      }
    } finally {
      _busy = false;
      _releaseEntry();
    }
  }

  Future<void> _undo(LogStateChange receipt) async {
    if (_undoBusy) return;
    if (!_current) {
      _expired();
      return;
    }
    if (!_claimEntry()) return;
    _undoBusy = true;
    try {
      final UndoLogStateResult result = await repository.undoLogState(
        receipt,
        scope: scope,
      );
      if (!_current) {
        _expired();
        return;
      }
      switch (result) {
        case UndoLogStateResult.restored:
        case UndoLogStateResult.alreadyRestored:
          _refresh();
          _show('Change undone.');
        case UndoLogStateResult.changed:
          _refresh();
          _show('Cannot undo: this meal changed.');
        case UndoLogStateResult.expired:
          _expired();
      }
    } catch (_) {
      if (_current) {
        _show(
          'Could not undo. Try again.',
          action: 'Retry',
          onAction: () => _undo(receipt),
        );
      } else {
        _expired();
      }
    } finally {
      _undoBusy = false;
      _releaseEntry();
    }
  }

  bool _claimEntry() {
    final LogStateFeedback? pending = _session.pending[entryId];
    // The row can rebuild while a database write is pending. Debounce that
    // new button too, so a duplicate refusal cannot replace the real Undo.
    if (pending != null && identical(pending.scope, scope)) return false;
    _session.pending[entryId] = this;
    return true;
  }

  void _releaseEntry() {
    if (identical(_session.pending[entryId], this)) {
      _session.pending.remove(entryId);
    }
  }

  void _refresh() {
    container.invalidate(dayEntriesProvider);
    container.invalidate(weekEntriesProvider);
    container.invalidate(recentLogsProvider);
    container.invalidate(mealRecentLogsProvider);
  }

  void _expired() => _show('This action expired. Open the day and try again.');

  void _show(
    String message, {
    String? action,
    Future<void> Function()? onAction,
  }) {
    if (!_messenger.mounted) return;
    _messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // The action gets a whole line, including at the largest system text.
          // Ordinary Undo keeps Hearth's window; screen readers and Retry
          // keep their action until it is used or explicitly dismissed.
          duration: undoWindow,
          persist:
              action == 'Retry' || (action != null && _accessibleNavigation),
          showCloseIcon: true,
          content: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(message),
                if (action != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SnackBarAction(
                      label: action,
                      onPressed: () {
                        _messenger.hideCurrentSnackBar();
                        // The native action dismisses its own bar after this
                        // callback. Present any immediate expiry only after
                        // that dismissal, including accessible navigation.
                        if (onAction != null) {
                          unawaited(Future<void>.microtask(onAction));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
  }
}

/// Shared per provider container so a household change expires all receipts,
/// including those held by routes that have already gone away. Returning to
/// an earlier identity starts a new scope; it cannot revive an old action.
class _LogSession {
  _LogSession(this.container) {
    container.listen(planRepositoryProvider, (
      PlanRepository? before,
      PlanRepository after,
    ) {
      if (before != null && !identical(before, after)) _scope?.invalidate();
    });
    container.listen(currentUserIdProvider, (String? before, String after) {
      if (before != after) _scope?.invalidate();
    });
    container.listen(currentHouseholdIdProvider, (
      String? before,
      String after,
    ) {
      if (before != after) _scope?.invalidate();
    });
    container.listen(accountProvider, (before, after) {
      if (before?.hasValue == true &&
          after.hasValue &&
          ((before?.value == null) != (after.value == null) ||
              before?.value?.userId != after.value?.userId ||
              before?.value?.householdId != after.value?.householdId)) {
        _scope?.invalidate();
      }
    });
  }

  final ProviderContainer container;
  final Map<String, LogStateFeedback> pending = <String, LogStateFeedback>{};
  LogStateScope? _scope;
  LogStateScope get current {
    if (_scope?.isActive != true) {
      final String userId = container.read(currentUserIdProvider);
      final String householdId = container.read(currentHouseholdIdProvider);
      final PlanRepository repository = container.read(planRepositoryProvider);
      _scope = LogStateScope(
        userId: userId,
        householdId: householdId,
        stillCurrent: () =>
            container.read(currentUserIdProvider) == userId &&
            container.read(currentHouseholdIdProvider) == householdId &&
            identical(container.read(planRepositoryProvider), repository),
      );
    }
    return _scope!;
  }
}
