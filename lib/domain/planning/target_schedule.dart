import 'package:meta/meta.dart';

import 'day_progress.dart';
import 'week.dart';

/// Targets explicitly saved for one person's single Monday-starting week.
///
/// Existing weekly rows remain exceptions; their presence never opts a person
/// into ongoing targets. Past and future week edits use this same record.
@immutable
final class ExactWeekTarget {
  ExactWeekTarget({
    required this.userId,
    required DateTime weekStart,
    required this.targets,
  }) : weekStart = startOfWeek(weekStart);

  final String userId;
  final DateTime weekStart;
  final MacroTargets targets;
}

/// A personal ongoing-target decision effective from one Monday onwards.
///
/// A boundary either carries the complete authored set of seven values or
/// explicitly stops carrying targets forward. Optional nutrient nulls belong
/// to [MacroTargets]; they never mean that the boundary is stopped.
///
/// Saving a new ongoing choice or stopping starts at the current week. The
/// repository enforces that write policy and, when stopping, preserves the
/// current week's values in an [ExactWeekTarget]. Historical boundaries remain
/// so resolving an earlier week cannot pick up a later decision.
@immutable
final class OngoingTargetBoundary {
  OngoingTargetBoundary.active({
    required this.userId,
    required DateTime weekStart,
    required MacroTargets targets,
  }) : weekStart = startOfWeek(weekStart),
       targets = targets;

  OngoingTargetBoundary.stopped({
    required this.userId,
    required DateTime weekStart,
  }) : weekStart = startOfWeek(weekStart),
       targets = null;

  final String userId;
  final DateTime weekStart;

  /// Null is an explicit stop, not permission to reuse an older boundary.
  final MacroTargets? targets;

  bool get isStopped => targets == null;
}

enum TargetSource { exactWeek, ongoing, none }

/// The targets for one person's week, without creating a saved weekly copy.
@immutable
final class ResolvedTargets {
  const ResolvedTargets._({
    required this.userId,
    required this.weekStart,
    required this.source,
    required this.targets,
    required this.ongoingBoundary,
  });

  final String userId;
  final DateTime weekStart;
  final TargetSource source;
  final MacroTargets? targets;

  /// Latest boundary on or before [weekStart], including an explicit stop.
  ///
  /// Kept even when an exact-week exception supplies [targets], so editing
  /// that week can distinguish the exception from the ongoing choice beneath
  /// it. Null means no ongoing decision yet for this person and week.
  final OngoingTargetBoundary? ongoingBoundary;
}

/// Resolves [date]'s week using exact-week targets before an ongoing fallback.
///
/// Reads only decisions belonging to [userId] and never uses a later boundary.
/// An exact-week exception lasts for that week only; the latest ongoing
/// boundary still determines other weeks. A stop suppresses the fallback
/// until a later active boundary, while existing exact-week exceptions win.
///
/// Inputs need not be sorted and are never changed. The seven authored values
/// are returned intact, including null and zero optional nutrients. No weekly
/// records, calculated targets or nutrition defaults are created here.
///
/// Storage is unique on (user, Monday) for each record type. Duplicate eligible
/// keys throw [StateError] rather than letting input order choose a winner.
/// Other users and future boundaries are ignored before this check, so they
/// cannot change or invalidate a historical answer.
ResolvedTargets resolveTargetsForWeek({
  required String userId,
  required DateTime date,
  Iterable<ExactWeekTarget> exactWeeks = const <ExactWeekTarget>[],
  Iterable<OngoingTargetBoundary> boundaries = const <OngoingTargetBoundary>[],
}) {
  final DateTime monday = startOfWeek(date);
  ExactWeekTarget? exact;
  for (final ExactWeekTarget week in exactWeeks) {
    if (week.userId != userId || week.weekStart != monday) continue;
    if (exact != null) {
      throw StateError(
        'More than one exact target for the same user and week.',
      );
    }
    exact = week;
  }

  OngoingTargetBoundary? latest;
  final Set<DateTime> seenWeeks = <DateTime>{};
  for (final OngoingTargetBoundary boundary in boundaries) {
    if (boundary.userId != userId || boundary.weekStart.isAfter(monday)) {
      continue;
    }
    if (!seenWeeks.add(boundary.weekStart)) {
      throw StateError(
        'More than one ongoing boundary for the same user and week.',
      );
    }
    if (latest == null || boundary.weekStart.isAfter(latest.weekStart)) {
      latest = boundary;
    }
  }

  final MacroTargets? targets = exact?.targets ?? latest?.targets;
  return ResolvedTargets._(
    userId: userId,
    weekStart: monday,
    source: exact != null
        ? TargetSource.exactWeek
        : targets != null
        ? TargetSource.ongoing
        : TargetSource.none,
    targets: targets,
    ongoingBoundary: latest,
  );
}
