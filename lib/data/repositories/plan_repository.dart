import 'package:uuid/uuid.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/recent_log.dart';
import '../../domain/planning/week.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
import '../local/plan_store.dart';
import '../mappers/plan_mapper.dart';

/// The only thing features talk to for planning and logging (spec §5.6).
///
/// Logging is the operation this whole app is judged on, and the one that
/// writes history that can never be recomputed — so freezing the snapshot
/// happens here, in one place, rather than being left to a screen.
class PlanRepository {
  PlanRepository({
    required HearthDatabase database,
    required PlanStore store,
    required PendingWriteStore queue,
    required String userId,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _userId = userId,
       _now = clock ?? DateTime.now,
       _newId = idFactory ?? const Uuid().v4;

  static const String entriesTable = 'meal_plan_entries';
  static const String daysTable = 'meal_plan_days';
  static const String targetsTable = 'macro_targets';

  final HearthDatabase _db;
  final PlanStore _store;
  final PendingWriteStore _queue;
  final String _userId;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<List<MealPlanEntry>> entriesFor(DateTime date) =>
      _store.entriesForDay(userId: _userId, date: date);

  Future<Map<DateTime, List<MealPlanEntry>>> entriesBetween(
    DateTime from,
    DateTime to,
  ) => _store.entriesForRange(userId: _userId, from: from, to: to);

  Stream<void> watchChanges() => _store.watchChanges();

  /// Things logged recently, collapsed to one row each, for fast entry
  /// (spec §5.6).
  Future<List<RecentLog>> recentLogs({int limit = 8}) async {
    final List<MealPlanEntry> logged = await _store.recentlyLogged(
      userId: _userId,
    );
    return RecentLogs.from(logged, limit: limit);
  }

  /// Logs something again with the portion it was last logged at — the
  /// one-tap repeat.
  Future<MealPlanEntry> logAgain({
    required RecentLog recent,
    required DateTime date,
    required MealSlot slot,
    required Macros liveMacros,
    double? portion,
  }) => add(
    date: date,
    slot: slot,
    refType: recent.refType,
    refId: recent.refId,
    servings: portion ?? recent.servings,
    // Macros are recomputed from the current library rather than copied from
    // the old snapshot: repeating a meal should record what that food is
    // today, not what it was when first logged.
    loggedMacros: liveMacros,
    label: recent.label,
  );

  Future<MacroTargets?> targetsFor(DateTime date) =>
      _store.targetsFor(userId: _userId, date: date);

  /// Adds something to a slot, either as a plan or as a straight log.
  ///
  /// [loggedMacros] is the macros for ONE serving as they stand right now.
  /// Supplying it logs the entry immediately and freezes the snapshot; leaving
  /// it null adds a planned entry that can be confirmed later. Logging without
  /// a plan is a first-class path (spec §5.6) — eating something unplanned
  /// should not require inventing a plan first.
  Future<MealPlanEntry> add({
    required DateTime date,
    required MealSlot slot,
    required PlanRefType refType,
    required String refId,
    required double servings,
    Macros? loggedMacros,
    String? label,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanDayRow day = await _store.ensureDay(
        userId: _userId,
        date: date,
        idFactory: _newId,
        updatedAt: now,
      );
      await _queueDay(day, now);

      MealPlanEntry entry = MealPlanEntry(
        id: _newId(),
        dayId: day.id,
        slot: slot,
        refType: refType,
        refId: refId,
        servings: servings,
        isPlanned: loggedMacros == null,
      );

      if (loggedMacros != null) {
        entry = entry.log(
          liveMacros: loggedMacros,
          at: now,
          label: label ?? '',
        );
      }

      await _store.upsertEntry(entry, updatedAt: now);
      await _queueEntry(entry, now);
      return entry;
    });
  }

  /// Confirms a planned entry as eaten — the one-tap path (spec §5.6).
  ///
  /// [liveMacros] is per serving; the portion may be adjusted at the same time.
  /// The snapshot written here is permanent: editing the recipe or food later
  /// must never change it (spec §4).
  Future<MealPlanEntry?> logEntry(
    String entryId, {
    required Macros liveMacros,
    required String label,
    double? portion,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanEntry? existing = await _store.entryById(entryId);
      if (existing == null) return null;

      final MealPlanEntry logged = existing.log(
        liveMacros: liveMacros,
        at: now,
        label: label,
        portion: portion,
      );
      await _store.upsertEntry(logged, updatedAt: now);
      await _queueEntry(logged, now);
      return logged;
    });
  }

  /// Changes a planned entry's portion or slot.
  ///
  /// Never touches a snapshot: [MealPlanEntry.copyWith] carries it through
  /// untouched, so moving a logged meal to another slot cannot rewrite what it
  /// recorded.
  Future<MealPlanEntry?> updateEntry(
    String entryId, {
    double? servings,
    MealSlot? slot,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanEntry? existing = await _store.entryById(entryId);
      if (existing == null) return null;

      final MealPlanEntry updated = existing.copyWith(
        servings: servings,
        slot: slot,
      );
      await _store.upsertEntry(updated, updatedAt: now);
      await _queueEntry(updated, now);
      return updated;
    });
  }

  Future<void> removeEntry(String entryId) async {
    final DateTime now = _now();
    await _db.transaction(() async {
      await _store.deleteEntry(entryId);
      await _queue.enqueue(
        entityTable: entriesTable,
        entityId: entryId,
        operation: WriteOperation.delete,
        payload: <String, Object?>{'id': entryId},
        queuedAt: now,
      );
    });
  }

  /// Assigns one recipe or food to the same slot across several days at once
  /// (spec §5.6's meal-prep assignment).
  ///
  /// One action, not one per day: "this batch is my dinner Mon/Tue/Wed" is a
  /// single decision, and making the user repeat it three times is the kind of
  /// tax the success bar is measured against. Entries are added as planned,
  /// not logged — a batch you have cooked is not a batch you have eaten.
  Future<List<MealPlanEntry>> assignAcrossDays({
    required Iterable<DateTime> dates,
    required MealSlot slot,
    required PlanRefType refType,
    required String refId,
    required double servings,
  }) async {
    final List<MealPlanEntry> created = <MealPlanEntry>[];
    for (final DateTime date in dates) {
      created.add(
        await add(
          date: date,
          slot: slot,
          refType: refType,
          refId: refId,
          servings: servings,
        ),
      );
    }
    return created;
  }

  /// Copies everything on [from] onto each of [to] (spec §5.6's copy day).
  ///
  /// Copies arrive as PLANNED, never logged, however they started life:
  /// copying Monday's dinner onto Thursday says you intend to eat it again,
  /// not that you already have. Writing a snapshot here would be inventing
  /// history (§4).
  Future<int> copyDay({
    required DateTime from,
    required Iterable<DateTime> to,
  }) async {
    final List<MealPlanEntry> source = await entriesFor(from);
    if (source.isEmpty) return 0;

    int copied = 0;
    for (final DateTime target in to) {
      if (dayKey(target) == dayKey(from)) continue;
      for (final MealPlanEntry entry in source) {
        await add(
          date: target,
          slot: entry.slot,
          refType: entry.refType,
          refId: entry.refId,
          servings: entry.servings,
        );
        copied++;
      }
    }
    return copied;
  }

  /// Sets the macro targets for [date]'s week.
  Future<void> setTargets(DateTime date, MacroTargets targets) async {
    final DateTime now = _now();
    await _db.transaction(() async {
      final String id = await _store.setTargets(
        userId: _userId,
        date: date,
        targets: targets,
        idFactory: _newId,
        updatedAt: now,
      );
      await _queue.enqueue(
        entityTable: targetsTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: PlanMapper.targetsToJson(
          id: id,
          userId: _userId,
          weekStart: date,
          targets: targets,
          updatedAt: now,
        ),
        queuedAt: now,
      );
    });
  }

  Future<void> _queueEntry(MealPlanEntry entry, DateTime now) => _queue.enqueue(
    entityTable: entriesTable,
    entityId: entry.id,
    operation: WriteOperation.upsert,
    payload: PlanMapper.entryToJson(entry, updatedAt: now),
    queuedAt: now,
  );

  Future<void> _queueDay(MealPlanDayRow day, DateTime now) => _queue.enqueue(
    entityTable: daysTable,
    entityId: day.id,
    operation: WriteOperation.upsert,
    payload: PlanMapper.dayToJson(day: day, userId: _userId),
    queuedAt: now,
  );
}
