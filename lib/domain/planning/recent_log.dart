import 'package:meta/meta.dart';

import 'meal_plan.dart';

/// Something logged recently, offered for one-tap repeat (spec §5.6).
///
/// Research quoted in the spec: logging speed is the single biggest driver of
/// whether a tracker gets used — "every extra tap is a tax you pay three times
/// a day". Most days are mostly repeats, so the fastest path is not search at
/// all, it is the thing you had yesterday.
@immutable
class RecentLog {
  const RecentLog({
    required this.refType,
    required this.refId,
    required this.label,
    required this.servings,
    required this.lastLoggedAt,
    required this.timesLogged,
  });

  final PlanRefType refType;
  final String refId;

  /// What it was called when last logged, so the row reads correctly even if
  /// the source has since been renamed.
  final String label;

  /// The portion used last time — what a one-tap repeat should reuse.
  final double servings;

  final DateTime lastLoggedAt;

  /// How many times this has been logged, for ordering by habit rather than
  /// by recency alone.
  final int timesLogged;

  /// Identity for de-duplication: the same food logged five times is one row.
  String get key => '${refType.name}:$refId';
}

/// Builds the recents list from raw logged entries.
///
/// Kept pure so the ordering rule — the part that decides whether the right
/// thing is under your thumb — is testable without a database.
abstract final class RecentLogs {
  /// Collapses [entries] into one row per referenced thing, most useful first.
  ///
  /// Ordering is recency, plainly. Frequency is carried on the row for the UI
  /// to show, but is deliberately not blended into the sort: a "smart" ranking
  /// that reorders itself is worse than a predictable one you can build muscle
  /// memory against.
  static List<RecentLog> from(
    Iterable<MealPlanEntry> entries, {
    int limit = 8,
  }) {
    final Map<String, RecentLog> byRef = <String, RecentLog>{};

    for (final MealPlanEntry entry in entries) {
      final MacroSnapshot? snapshot = entry.macroSnapshot;
      if (!entry.isLogged || snapshot == null) continue;

      final String key = '${entry.refType.name}:${entry.refId}';
      final RecentLog? existing = byRef[key];

      if (existing == null) {
        byRef[key] = RecentLog(
          refType: entry.refType,
          refId: entry.refId,
          label: snapshot.label,
          servings: snapshot.servings,
          lastLoggedAt: snapshot.capturedAt,
          timesLogged: 1,
        );
        continue;
      }

      final bool isNewer = snapshot.capturedAt.isAfter(existing.lastLoggedAt);
      byRef[key] = RecentLog(
        refType: existing.refType,
        refId: existing.refId,
        // The most recent logging wins for label and portion: it is the best
        // guess at what you would repeat.
        label: isNewer ? snapshot.label : existing.label,
        servings: isNewer ? snapshot.servings : existing.servings,
        lastLoggedAt: isNewer ? snapshot.capturedAt : existing.lastLoggedAt,
        timesLogged: existing.timesLogged + 1,
      );
    }

    final List<RecentLog> recents = byRef.values.toList()
      ..sort(
        (RecentLog a, RecentLog b) => b.lastLoggedAt.compareTo(a.lastLoggedAt),
      );
    return recents.take(limit).toList(growable: false);
  }
}
