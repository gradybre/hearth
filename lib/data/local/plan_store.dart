import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/target_schedule.dart';
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
  bool _observingLogConnection = false;
  bool _logConnectionClosed = false;

  bool get isLogStateConnectionClosed => _logConnectionClosed;

  /// Connection-local evidence for short-lived Log/Unlog receipts. These TEMP
  /// objects are not application history and never enter the persistent schema.
  /// Triggers observe content changes from repository, direct and sync writers;
  /// a timestamp cannot distinguish two edits in the same clock tick. A server
  /// confirmation changing only its timestamp or JSON encoding is not an edit.
  /// Revision rows remain after deletion so reinserting an id cannot revive an
  /// old receipt.
  ///
  /// Run before the action transaction. Idempotent SQL also handles two stores
  /// sharing a connection, and a new connection gets a new session token.
  Future<void> prepareLogStateTracking() async {
    if (!_observingLogConnection) {
      _observingLogConnection = true;
      // Drift closes this stream with its connection. Observe that terminal
      // event without needing to reopen/query a database that was disposed.
      _db.tableUpdates().listen(
        (_) {},
        onDone: () => _logConnectionClosed = true,
      );
    }
    await _db.customStatement('''
      CREATE TEMP TABLE IF NOT EXISTS hearth_log_state_session (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        token TEXT NOT NULL
      )
    ''');
    await _db.customStatement(
      'INSERT OR IGNORE INTO temp.hearth_log_state_session VALUES (1, ?)',
      <Object>[const Uuid().v4()],
    );
    await _db.customStatement('''
      CREATE TEMP TABLE IF NOT EXISTS hearth_log_state_revisions (
        entry_id TEXT PRIMARY KEY, revision INTEGER NOT NULL
      )
    ''');
    // fullkey retains array positions; container rows distinguish empty
    // arrays/objects, and null leaves distinguish missing from explicit null.
    // Traversal ids/order are deliberately absent: object order is not data.
    // Conflicting duplicate member paths are ambiguous, so changed raw text
    // with either tree containing them conservatively counts as an edit.
    String jsonTree(String row) =>
        '''
      SELECT fullkey,
        CASE WHEN type IN ('integer', 'real') THEN 'number' ELSE type END,
        atom FROM json_tree($row.macro_snapshot)
    ''';
    final String contentChanged = <String>[
      for (final String column in <String>[
        'id',
        'day_id',
        'meal_slot',
        'ref_type',
        'ref_id',
        'servings',
        'serving_option_id',
        'is_planned',
        'is_logged',
        'logged_at',
      ])
        'OLD.$column IS NOT NEW.$column',
      '''CASE
        WHEN OLD.macro_snapshot IS NEW.macro_snapshot THEN 0
        WHEN json_valid(OLD.macro_snapshot) = 1
          AND json_valid(NEW.macro_snapshot) = 1
        THEN EXISTS (SELECT fullkey FROM json_tree(OLD.macro_snapshot)
            GROUP BY fullkey HAVING COUNT(*) > 1)
          OR EXISTS (SELECT fullkey FROM json_tree(NEW.macro_snapshot)
            GROUP BY fullkey HAVING COUNT(*) > 1)
          OR EXISTS (${jsonTree('OLD')} EXCEPT ${jsonTree('NEW')})
          OR EXISTS (${jsonTree('NEW')} EXCEPT ${jsonTree('OLD')})
        ELSE 1
      END''',
    ].join(' OR ');
    for (final String event in <String>['INSERT', 'UPDATE', 'DELETE']) {
      final String row = event == 'DELETE' ? 'OLD' : 'NEW';
      await _db.customStatement('''
        CREATE TEMP TRIGGER IF NOT EXISTS hearth_log_state_${event.toLowerCase()}
        AFTER $event ON main.meal_plan_entries
        ${event == 'UPDATE' ? 'WHEN $contentChanged' : ''}
        BEGIN
          INSERT INTO hearth_log_state_revisions(entry_id, revision)
          VALUES ($row.id, 1)
          ON CONFLICT(entry_id) DO UPDATE SET revision = revision + 1;
          ${event == 'UPDATE' ? '''
          INSERT INTO hearth_log_state_revisions(entry_id, revision)
          SELECT OLD.id, 1 WHERE OLD.id != NEW.id
          ON CONFLICT(entry_id) DO UPDATE SET revision = revision + 1;
          ''' : ''}
        END
      ''');
    }
  }

  /// Read inside the same transaction as the guarded mutation.
  Future<StoredLogState?> logState(String id) async {
    final MealPlanEntryRow? row = await (_db.select(
      _db.mealPlanEntries,
    )..where(($MealPlanEntriesTable e) => e.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final MealPlanDayRow? day =
        await (_db.select(_db.mealPlanDays)
              ..where(($MealPlanDaysTable d) => d.id.equals(row.dayId)))
            .getSingleOrNull();
    if (day == null) return null;
    final QueryRow evidence = await _db
        .customSelect(
          '''
      SELECT token, COALESCE(revision, 0) AS revision
      FROM temp.hearth_log_state_session
      LEFT JOIN temp.hearth_log_state_revisions ON entry_id = ?
      WHERE singleton = 1
    ''',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .getSingle();
    return StoredLogState(
      row: row,
      userId: day.userId,
      connection: evidence.read<String>('token'),
      revision: evidence.read<int>('revision'),
    );
  }

  /// Restores the raw snapshot, including fields this client cannot interpret.
  /// [updatedAt] is the new sync write time; all original meal times remain.
  Future<void> restoreLogState(MealPlanEntryRow row, DateTime updatedAt) async {
    await _db
        .into(_db.mealPlanEntries)
        .insertOnConflictUpdate(
          row.copyWith(updatedAt: updatedAt).toCompanion(false),
        );
  }

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

  /// Moves an unlogged entry to a different food, returning how many rows
  /// changed — zero when it had been logged in the meantime (review N05).
  ///
  /// The `isLogged` test is part of the statement on purpose. A logged entry
  /// is a record of a meal that happened, and its reference and portion are
  /// not the caller's to rewrite (spec §4).
  Future<int> repointUnloggedEntry({
    required String entryId,
    required String refId,
    required double servings,
    required DateTime updatedAt,
  }) =>
      (_db.update(_db.mealPlanEntries)..where(
            ($MealPlanEntriesTable t) =>
                t.id.equals(entryId) & t.isLogged.equals(false),
          ))
          .write(
            MealPlanEntriesCompanion(
              refId: Value(refId),
              servings: Value(servings),
              updatedAt: Value(updatedAt),
            ),
          );

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
  }) async => (await targetResolutionFor(userId: userId, date: date)).targets;

  /// Reads both kinds of targets from one snapshot. Even a weekly exception
  /// retains the ongoing choice beneath it for the target editor.
  Future<ResolvedTargets> targetResolutionFor({
    required String userId,
    required DateTime date,
  }) => _db.transaction(() async {
    final DateTime monday = startOfWeek(date);
    final MacroTargetRow? exact = await targetRowFor(
      userId: userId,
      date: monday,
    );
    final OngoingMacroTargetRow? boundary =
        await (_db.select(_db.ongoingMacroTargets)
              ..where(
                ($OngoingMacroTargetsTable t) =>
                    t.userId.equals(userId) &
                    t.weekStartDate.isSmallerOrEqualValue(monday),
              )
              ..orderBy(<OrderClauseGenerator<$OngoingMacroTargetsTable>>[
                ($OngoingMacroTargetsTable t) =>
                    OrderingTerm.desc(t.weekStartDate),
              ])
              ..limit(1))
            .getSingleOrNull();
    return resolveTargetsForWeek(
      userId: userId,
      date: monday,
      exactWeeks: <ExactWeekTarget>[
        if (exact != null) PlanMapper.exactWeekTargetToDomain(exact),
      ],
      boundaries: <OngoingTargetBoundary>[
        if (boundary != null) PlanMapper.ongoingTargetToDomain(boundary),
      ],
    );
  });

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

  /// The ongoing boundary has its own identity even when an exact-week
  /// exception exists for the same person and Monday.
  static String ongoingIdFor(String userId, DateTime weekStart) =>
      const Uuid().v5(
        Namespace.url.value,
        'hearth:ongoing-macro-targets:$userId:'
        '${_dateKey(startOfWeek(weekStart))}',
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

  Future<OngoingMacroTargetRow?> ongoingTargetRowFor({
    required String userId,
    required DateTime date,
  }) =>
      (_db.select(_db.ongoingMacroTargets)..where(
            ($OngoingMacroTargetsTable t) =>
                t.userId.equals(userId) &
                t.weekStartDate.equals(startOfWeek(date)),
          ))
          .getSingleOrNull();

  Future<String> setOngoingTarget({
    required OngoingTargetBoundary boundary,
    required DateTime updatedAt,
  }) async {
    final OngoingMacroTargetRow? existing = await ongoingTargetRowFor(
      userId: boundary.userId,
      date: boundary.weekStart,
    );
    final String id =
        existing?.id ?? ongoingIdFor(boundary.userId, boundary.weekStart);
    await _db
        .into(_db.ongoingMacroTargets)
        .insertOnConflictUpdate(
          PlanMapper.ongoingTargetToCompanion(
            id: id,
            boundary: boundary,
            updatedAt: updatedAt,
          ),
        );
    return id;
  }

  /// A fresh revision when this person's saved target data changes.
  ///
  /// Watching both tables also catches remote updates with unchanged row
  /// counts and no plan-entry edits. Comparing the complete scoped result
  /// suppresses notifications caused only by another person's writes.
  Stream<int> watchTargetChanges({required String userId}) {
    int revision = 0;
    return _db
        .customSelect(
          'SELECT 0 AS target_kind, id, week_start_date, 0 AS is_stopped, '
          'kcal, protein_g, carb_g, fat_g, fiber_g, sodium_mg, cholesterol_mg, '
          'updated_at FROM macro_targets WHERE user_id = ? '
          'UNION ALL '
          'SELECT 1 AS target_kind, id, week_start_date, is_stopped, '
          'kcal, protein_g, carb_g, fat_g, fiber_g, sodium_mg, cholesterol_mg, '
          'updated_at FROM ongoing_macro_targets WHERE user_id = ? '
          'ORDER BY target_kind, week_start_date, id',
          variables: <Variable<String>>[
            Variable<String>(userId),
            Variable<String>(userId),
          ],
          readsFrom: <ResultSetImplementation>{
            _db.macroTargets,
            _db.ongoingMacroTargets,
          },
        )
        .watch()
        .map(
          (List<QueryRow> rows) => <Map<String, dynamic>>[
            for (final QueryRow row in rows) row.data,
          ],
        )
        .distinct(const DeepCollectionEquality().equals)
        .map((_) => ++revision);
  }

  Stream<void> watchTargets() =>
      _db.select(_db.macroTargets).watch().map((_) {});
}

/// Raw row and the storage evidence read with it in an action transaction.
class StoredLogState {
  const StoredLogState({
    required this.row,
    required this.userId,
    required this.connection,
    required this.revision,
  });

  final MealPlanEntryRow row;
  final String userId;
  final String connection;
  final int revision;
}
