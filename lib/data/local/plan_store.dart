import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import '../mappers/plan_mapper.dart';
import 'hearth_database.dart';

/// Local reads and writes for the planner (spec §5.6).
///
/// Everything here is user-scoped: plans, logs, and targets are private per
/// person, and portions are independent. Two people in a household never share
/// a row in these tables.
class PlanStore {
  PlanStore(this._db);

  final HearthDatabase _db;

  /// The day row for [date], creating it if this is the first thing put there.
  ///
  /// Days are created lazily: an untouched day has no row, so a fresh week
  /// costs nothing until something is planned or logged into it.
  Future<MealPlanDayRow> ensureDay({
    required String userId,
    required DateTime date,
    required String Function() idFactory,
    required DateTime updatedAt,
  }) async {
    final DateTime key = dayKey(date);
    final MealPlanDayRow? existing = await _dayRow(userId: userId, date: key);
    if (existing != null) return existing;

    final String id = idFactory();
    await _db
        .into(_db.mealPlanDays)
        .insert(
          MealPlanDaysCompanion.insert(
            id: id,
            userId: userId,
            day: key,
            updatedAt: updatedAt,
          ),
        );
    return (await _dayRow(userId: userId, date: key))!;
  }

  Future<MealPlanDayRow?> _dayRow({
    required String userId,
    required DateTime date,
  }) =>
      (_db.select(_db.mealPlanDays)..where(
            ($MealPlanDaysTable d) =>
                d.userId.equals(userId) & d.day.equals(dayKey(date)),
          ))
          .getSingleOrNull();

  Future<MealPlanDayRow?> dayFor({
    required String userId,
    required DateTime date,
  }) => _dayRow(userId: userId, date: date);

  /// Entries on a day, in slot order then insertion order.
  Future<List<MealPlanEntry>> entriesForDay({
    required String userId,
    required DateTime date,
  }) async {
    final MealPlanDayRow? day = await _dayRow(userId: userId, date: date);
    if (day == null) return const <MealPlanEntry>[];

    final List<MealPlanEntryRow> rows =
        await (_db.select(_db.mealPlanEntries)
              ..where(($MealPlanEntriesTable e) => e.dayId.equals(day.id))
              ..orderBy(<OrderClauseGenerator<$MealPlanEntriesTable>>[
                ($MealPlanEntriesTable e) => OrderingTerm.asc(e.updatedAt),
              ]))
            .get();
    return rows.map(PlanMapper.entryToDomain).toList(growable: false);
  }

  /// Entries across a date range, for the week view.
  Future<Map<DateTime, List<MealPlanEntry>>> entriesForRange({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final List<MealPlanDayRow> days =
        await (_db.select(_db.mealPlanDays)..where(
              ($MealPlanDaysTable d) =>
                  d.userId.equals(userId) &
                  d.day.isBiggerOrEqualValue(dayKey(from)) &
                  d.day.isSmallerOrEqualValue(dayKey(to)),
            ))
            .get();
    if (days.isEmpty) return <DateTime, List<MealPlanEntry>>{};

    final Map<String, DateTime> dayById = <String, DateTime>{
      for (final MealPlanDayRow d in days) d.id: dayKey(d.day),
    };
    final List<MealPlanEntryRow> rows =
        await (_db.select(_db.mealPlanEntries)
              ..where(($MealPlanEntriesTable e) => e.dayId.isIn(dayById.keys))
              ..orderBy(<OrderClauseGenerator<$MealPlanEntriesTable>>[
                ($MealPlanEntriesTable e) => OrderingTerm.asc(e.updatedAt),
              ]))
            .get();

    final Map<DateTime, List<MealPlanEntry>> byDay =
        <DateTime, List<MealPlanEntry>>{
          for (final DateTime date in dayById.values) date: <MealPlanEntry>[],
        };
    for (final MealPlanEntryRow row in rows) {
      final DateTime? date = dayById[row.dayId];
      if (date == null) continue;
      byDay[date]!.add(PlanMapper.entryToDomain(row));
    }
    return byDay;
  }

  /// The most recently logged entries, newest first.
  ///
  /// Reads a bounded window of rows rather than the whole history: recents
  /// only needs the last handful, and this query sits on the logging path
  /// where a wait is paid three times a day.
  Future<List<MealPlanEntry>> recentlyLogged({
    required String userId,
    int scanLimit = 60,
  }) async {
    final List<MealPlanDayRow> days = await (_db.select(
      _db.mealPlanDays,
    )..where(($MealPlanDaysTable d) => d.userId.equals(userId))).get();
    if (days.isEmpty) return const <MealPlanEntry>[];

    final List<MealPlanEntryRow> rows =
        await (_db.select(_db.mealPlanEntries)
              ..where(
                ($MealPlanEntriesTable e) =>
                    e.dayId.isIn(days.map((MealPlanDayRow d) => d.id)) &
                    e.isLogged.equals(true),
              )
              ..orderBy(<OrderClauseGenerator<$MealPlanEntriesTable>>[
                ($MealPlanEntriesTable e) => OrderingTerm.desc(e.loggedAt),
              ])
              ..limit(scanLimit))
            .get();
    return rows.map(PlanMapper.entryToDomain).toList(growable: false);
  }

  /// Watches every plan change, so an open day or week view refreshes itself.
  Stream<void> watchChanges() =>
      _db.select(_db.mealPlanEntries).watch().map((_) {});

  Future<void> upsertEntry(
    MealPlanEntry entry, {
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.mealPlanEntries)
        .insertOnConflictUpdate(PlanMapper.entryToCompanion(entry, updatedAt));
  }

  /// Removes an entry outright.
  ///
  /// Unlike recipes and foods, a plan entry is not history worth keeping once
  /// removed — it is the plan itself. A *logged* entry is history, and the UI
  /// is what decides whether removing one is offered.
  Future<void> deleteEntry(String id) async {
    await (_db.delete(
      _db.mealPlanEntries,
    )..where(($MealPlanEntriesTable e) => e.id.equals(id))).go();
  }

  Future<MealPlanEntry?> entryById(String id) async {
    final MealPlanEntryRow? row = await (_db.select(
      _db.mealPlanEntries,
    )..where(($MealPlanEntriesTable e) => e.id.equals(id))).getSingleOrNull();
    return row == null ? null : PlanMapper.entryToDomain(row);
  }

  // ── Targets ───────────────────────────────────────────────────────────────

  /// The targets covering [date]'s week, or null when none are set.
  Future<MacroTargets?> targetsFor({
    required String userId,
    required DateTime date,
  }) async {
    final MacroTargetRow? row =
        await (_db.select(_db.macroTargets)..where(
              ($MacroTargetsTable t) =>
                  t.userId.equals(userId) &
                  t.weekStartDate.equals(startOfWeek(date)),
            ))
            .getSingleOrNull();
    return row == null ? null : PlanMapper.targetsToDomain(row);
  }

  Future<MacroTargetRow?> targetRowFor({
    required String userId,
    required DateTime date,
  }) =>
      (_db.select(_db.macroTargets)..where(
            ($MacroTargetsTable t) =>
                t.userId.equals(userId) &
                t.weekStartDate.equals(startOfWeek(date)),
          ))
          .getSingleOrNull();

  /// Sets the targets for [date]'s week.
  ///
  /// Targets are per week so they can change week to week (spec §5.6); the
  /// week start is normalised to Monday so a mid-week edit updates the week
  /// you are in rather than creating a second overlapping one.
  /// The row id for a week's targets, derived rather than random.
  ///
  /// The table is unique on (user_id, week_start_date) and keyed on the id, so
  /// two phones each minting their own id for the same week produce two rows
  /// for one constrained pair — and the unique key refuses whichever reaches
  /// the server second, permanently, because retrying carries the same id it
  /// was refused for. Deriving the id from the pair the key is on means both
  /// phones arrive at the same row and the later write updates it.
  ///
  /// The same reasoning as [IngredientMatchStore.idFor], and the same shape:
  /// anything a household can decide independently on two devices needs an id
  /// that does not depend on which device decided it.
  static String idFor(String userId, DateTime weekStart) => const Uuid().v5(
    Namespace.url.value,
    'hearth:macro-targets:$userId:${_dateKey(startOfWeek(weekStart))}',
  );

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<String> setTargets({
    required String userId,
    required DateTime date,
    required MacroTargets targets,
    required String Function() idFactory,
    required DateTime updatedAt,
  }) async {
    final DateTime weekStart = startOfWeek(date);
    final MacroTargetRow? existing = await targetRowFor(
      userId: userId,
      date: weekStart,
    );
    // A row already here keeps its id, whatever it was: it may have been
    // written before this was derived, and may already be on the server under
    // that id. Only a new one gets the derived id.
    final String id = existing?.id ?? idFor(userId, weekStart);

    await _db
        .into(_db.macroTargets)
        .insertOnConflictUpdate(
          MacroTargetsCompanion.insert(
            id: id,
            userId: userId,
            weekStartDate: weekStart,
            kcal: targets.kcal,
            proteinG: targets.proteinG,
            carbG: targets.carbG,
            fatG: targets.fatG,
            fiberG: Value<double?>(targets.fiberG),
            sodiumMg: Value<double?>(targets.sodiumMg),
            cholesterolMg: Value<double?>(targets.cholesterolMg),
            updatedAt: updatedAt,
          ),
        );
    return id;
  }

  Stream<void> watchTargets() =>
      _db.select(_db.macroTargets).watch().map((_) {});
}
