import 'package:drift/drift.dart';

import '../../domain/cooking/cook_session.dart';
import 'hearth_database.dart';

/// Reads and writes running cook timers (spec §5.2).
///
/// Local-only: timers are never queued for sync. A timer is about the pot in
/// front of you, and replaying it onto a partner's phone would be their pocket
/// buzzing for your oven.
class CookTimerStore {
  CookTimerStore(this._db);

  final HearthDatabase _db;

  /// Timers that are still worth showing.
  ///
  /// Anything more than [staleAfter] past due is dropped rather than
  /// resurrected: a timer from last week is not news, and a list that only
  /// grows is its own kind of broken. Something finished an hour ago still
  /// comes back — you want to know the braise is done, even late.
  static const Duration staleAfter = Duration(hours: 12);

  Future<List<CookTimer>> all({required DateTime now}) async {
    final List<CookTimerRow> rows =
        await (_db.select(_db.cookTimers)
              ..orderBy(<OrderClauseGenerator<$CookTimersTable>>[
                ($CookTimersTable t) => OrderingTerm.asc(t.startedAt),
              ]))
            .get();

    final List<CookTimer> kept = <CookTimer>[];
    final List<String> stale = <String>[];
    for (final CookTimerRow row in rows) {
      final CookTimer timer = _toTimer(row);
      if (timer.overdueBy(now) > staleAfter) {
        stale.add(timer.id);
      } else {
        kept.add(timer);
      }
    }
    if (stale.isNotEmpty) {
      await (_db.delete(
        _db.cookTimers,
      )..where(($CookTimersTable t) => t.id.isIn(stale))).go();
    }
    return kept;
  }

  Stream<List<CookTimer>> watch() => _db
      .select(_db.cookTimers)
      .watch()
      .map(
        (List<CookTimerRow> rows) => <CookTimer>[
          for (final CookTimerRow row in rows) _toTimer(row),
        ],
      );

  Future<void> upsert(CookTimer timer, {String? recipeTitle}) => _db
      .into(_db.cookTimers)
      .insertOnConflictUpdate(
        CookTimerRow(
          id: timer.id,
          label: timer.label,
          durationSeconds: timer.duration.inSeconds,
          startedAt: timer.startedAt,
          stepNumber: timer.stepNumber,
          stepId: timer.stepId,
          elapsedWhenPausedSeconds: timer.elapsedWhenPaused?.inSeconds,
          recipeTitle: recipeTitle,
        ),
      );

  Future<void> delete(String id) => (_db.delete(
    _db.cookTimers,
  )..where(($CookTimersTable t) => t.id.equals(id))).go();

  Future<void> clear() => _db.delete(_db.cookTimers).go();

  static CookTimer _toTimer(CookTimerRow row) => CookTimer(
    id: row.id,
    label: row.label,
    duration: Duration(seconds: row.durationSeconds),
    startedAt: row.startedAt,
    stepNumber: row.stepNumber,
    stepId: row.stepId,
    elapsedWhenPaused: row.elapsedWhenPausedSeconds == null
        ? null
        : Duration(seconds: row.elapsedWhenPausedSeconds!),
  );
}
