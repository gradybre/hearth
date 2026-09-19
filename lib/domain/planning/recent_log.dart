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
    this.servingOptionId,
  });

  final PlanRefType refType;
  final String refId;

  /// What it was called when last logged, so the row reads correctly even if
  /// the source has since been renamed.
  final String label;

  /// The portion used last time — what a one-tap repeat should reuse.
  final double servings;

  /// Which of the food's servings [servings] counts, when it is not the
  /// food's first one (spec R12).
  ///
  /// The count and the row it counts only mean anything together. A
  /// package-derived amount is six of the row its label was reviewed
  /// against, and repeating that six against whichever row the food lists
  /// first records double the meal it claims to repeat — frozen history that
  /// spec §4 then forbids correcting.
  ///
  /// Null is the ordinary state and means exactly what it always meant: a
  /// count of the food's default serving.
  final String? servingOptionId;

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
          // From the entry rather than the snapshot: the reference is a live
          // pointer at a serving row, not part of what was frozen.
          servingOptionId: entry.servingOptionId,
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
        // Moves with the portion, null included: the newest logging naming
        // no row means the default one, and keeping the older id would
        // repeat a portion in a serving that meal was never counted in.
        servingOptionId: isNewer
            ? entry.servingOptionId
            : existing.servingOptionId,
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
