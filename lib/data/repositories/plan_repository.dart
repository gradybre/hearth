import 'package:uuid/uuid.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/recent_log.dart';
import '../../domain/planning/week.dart';
import '../../domain/planning/week_template.dart';
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
  static const String templatesTable = 'plan_templates';

  final HearthDatabase _db;
  final PlanStore _store;
  final PendingWriteStore _queue;
  final String _userId;
  final DateTime Function() _now;
  final String Function() _newId;

  /// The id of the row for one user's one day.
  ///
  /// Derived, not random. A day has no identity of its own — it *is* a user
  /// and a date, and the server enforces that with a unique key on the pair.
  /// Two devices that each invented a random id for the same Tuesday would
  /// produce two rows, and the second would be rejected forever: its meals
  /// could never sync, which is precisely the offline case this app promises
  /// to survive.
  static String dayIdFor({required String userId, required DateTime date}) {
    final DateTime key = dayKey(date);
    final String day =
        '${key.year.toString().padLeft(4, '0')}-'
        '${key.month.toString().padLeft(2, '0')}-'
        '${key.day.toString().padLeft(2, '0')}';
    return const Uuid().v5(
      Namespace.url.value,
      'hearth:meal-plan-day:$userId:$day',
    );
  }

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
    NutrientCoverage? liveCoverage,
    double? portion,
  }) => add(
    date: date,
    slot: slot,
    refType: recent.refType,
    refId: recent.refId,
    servings: portion ?? recent.servings,
    loggedCoverage: liveCoverage,
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
    NutrientCoverage? loggedCoverage,
    String? label,
  }) async {
    assert(
      loggedCoverage != null ||
          refType == PlanRefType.food ||
          loggedMacros == null,
      'A recipe must state its own coverage: its total is non-null whenever '
      'any one ingredient knows, so inferring from it claims a completeness '
      'nothing checked (spec §5.6).',
    );
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanDayRow day = await _store.ensureDay(
        userId: _userId,
        date: date,
        idFactory: () => dayIdFor(userId: _userId, date: date),
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
          // Falling back to what the numbers themselves imply is right only
          // for a single food, where a non-null value really does mean the
          // food stated it. A recipe's caller must pass its own coverage —
          // see `log`'s note on why the default was the bug (spec §5.6).
          coverage: loggedCoverage ?? NutrientCoverage.ofOne(loggedMacros),
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
    // Required. Its optional twin on `log` was the whole defect, and leaving
    // one here put it back one level up: the day screen's one-tap confirm
    // promptly fell through it and froze "complete" on a partial recipe.
    required NutrientCoverage liveCoverage,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanEntry? existing = await _store.entryById(entryId);
      if (existing == null) return null;

      // A correction keeps the moment it was eaten. `log` stamps both
      // `loggedAt` and the snapshot's `capturedAt` with the time it is
      // called, which is right for a meal being logged and wrong for one
      // being corrected: it would move a June meal to today, promote it above
      // today's meals in the recents list — which orders by exactly this —
      // and have the export say it was eaten in September. `restore` goes out
      // of its way to preserve this; correcting a portion has to as well.
      final MealPlanEntry logged = existing.log(
        liveMacros: liveMacros,
        at: existing.loggedAt ?? now,
        label: label,
        portion: portion,
        coverage: liveCoverage,
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

  /// Puts a logged entry back to planned (spec §5.6).
  ///
  /// The counterpart of [logEntry], and the other half of a tap: confirming a
  /// meal is one tap, so taking it back has to be one too.
  Future<MealPlanEntry?> unlogEntry(String entryId) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanEntry? existing = await _store.entryById(entryId);
      if (existing == null || !existing.isLogged) return null;

      final MealPlanEntry planned = existing.unlog();
      await _store.upsertEntry(planned, updatedAt: now);
      await _queueEntry(planned, now);
      return planned;
    });
  }

  /// Puts a removed entry back exactly as it was (spec §4).
  ///
  /// A restore is not a new meal, and that is the whole of it. The obvious
  /// route — hand the entry's numbers back through [add] — is wrong, because
  /// a logged entry's snapshot is **already multiplied by the portion**: it
  /// records what was eaten, not what one serving contains. [add] takes a
  /// per-serving figure and scales it, so two servings of a 100 kcal meal
  /// came back as 400, and half a serving came back as 25. At exactly one
  /// serving the two readings agree, which is why it survived being used.
  ///
  /// So this takes the entry itself and writes it back whole: the same id, the
  /// same portion, slot and day, the same frozen snapshot, and the same moment
  /// it was actually eaten. The sync mutation carries [_now] because that is
  /// when this device changed its mind — a different fact from when the meal
  /// happened, and the one thing here that is allowed to be new.
  ///
  /// Idempotent by construction: the same id is upserted, so a double tap or a
  /// replayed action puts back one meal rather than two.
  ///
  /// The queued upsert **supersedes** the queued delete rather than following
  /// it — [PendingWriteStore.enqueue] drops earlier pending writes for the
  /// same row — so the delete is never sent and the server never sees the meal
  /// leave. If the delete was already pushed, the upsert re-inserts it. Both
  /// routes converge; neither depends on per-entity ordering, which the queue
  /// does not promise.
  ///
  /// No day is ensured and none is re-queued. Removing an entry does not
  /// remove its day, and the entry's own `dayId` is a foreign key that was
  /// valid a moment ago — so asking for the date again would be asking the
  /// caller to restate something the entry already knows, and getting it
  /// wrong would write the meal to a day nobody checked.
  Future<MealPlanEntry> restore(MealPlanEntry entry) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      await _store.upsertEntry(entry, updatedAt: now);
      await _queueEntry(entry, now);
      return entry;
    });
  }

  /// Files an existing meal under a different day or slot (review N02).
  ///
  /// The same record, moved — not a copy, and emphatically not a delete and a
  /// re-log. Re-logging costs the meal from the food as it stands *now*, so
  /// correcting a date that way rewrites what was eaten (non-negotiable 3).
  /// This is the whole reason the operation exists.
  ///
  /// The destination day is ensured and queued before the entry, because the
  /// entry's `dayId` is a foreign key and the server has never heard of a day
  /// nobody has written to yet. The day it came *from* is left alone: an
  /// empty day is not a problem, and removing one would take the other meals
  /// on it with it.
  Future<MealPlanEntry> move(
    MealPlanEntry entry, {
    required DateTime date,
    required MealSlot slot,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      final MealPlanDayRow day = await _store.ensureDay(
        userId: _userId,
        date: date,
        idFactory: () => dayIdFor(userId: _userId, date: date),
        updatedAt: now,
      );
      await _queueDay(day, now);

      final MealPlanEntry moved = entry.filedUnder(
        dayId: day.id,
        slot: slot,
        loggedAt: _reDated(entry.loggedAt, date),
      );
      await _store.upsertEntry(moved, updatedAt: now);
      await _queueEntry(moved, now);
      return moved;
    });
  }

  /// The same food or recipe, at the same portion, planned for another day
  /// (review N02).
  ///
  /// A *planned* entry, deliberately. A copy is a meal nobody has eaten yet,
  /// and a snapshot freezes when a meal is logged and at no other time — so
  /// there is nothing to inherit and carrying one forward would give that
  /// column a second meaning. It follows that the copy is costed from the
  /// food as it stands when it is eventually logged, which is also the answer
  /// anyone would want after correcting that food's macros.
  Future<MealPlanEntry> copyAsPlanned(
    MealPlanEntry entry, {
    required DateTime date,
    required MealSlot slot,
  }) => add(
    date: date,
    slot: slot,
    refType: entry.refType,
    refId: entry.refId,
    servings: entry.servings,
  );

  /// [at], on [date], at the same time of day.
  ///
  /// Local throughout. Day attribution is local — `dayKey` says so — so
  /// reading the hour off a UTC instant and rebuilding it as a local one
  /// would shift the meal by the offset, which on this side of the Atlantic
  /// is enough to move an early breakfast onto the day before.
  static DateTime? _reDated(DateTime? at, DateTime date) {
    if (at == null) return null;
    final DateTime local = at.toLocal();
    return DateTime(
      date.year,
      date.month,
      date.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  Future<void> removeEntry(String entryId) async {
    final DateTime now = _now();
    await _db.transaction(() async {
      await _store.deleteEntry(entryId);
      await _queue.enqueue(
        entityTable: entriesTable,
        entityId: entryId,
        operation: WriteOperation.delete,
        payload: <String, Object?>{
          'id': entryId,
          // Stated, not left to the server: the tombstone records the deleting
          // writer's own clock, so an Undo from this same device is always
          // newer than the deletion it undoes (spec §7.1).
          'updated_at': now.toUtc().toIso8601String(),
        },
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

  // ── Week templates (spec §5.6) ────────────────────────────────────────────

  Future<List<WeekTemplate>> templates() async {
    final List<PlanTemplateRow> rows = await (_db.select(
      _db.planTemplates,
    )..where(($PlanTemplatesTable t) => t.userId.equals(_userId))).get();

    return <WeekTemplate>[
      for (final PlanTemplateRow row in rows)
        WeekTemplate(
          id: row.id,
          name: row.name,
          entries: WeekTemplate.decodeEntries(row.entries),
          updatedAt: row.updatedAt,
        ),
    ]..sort((WeekTemplate a, WeekTemplate b) => a.name.compareTo(b.name));
  }

  /// Saves the week containing [anchor] under [name].
  ///
  /// Returns null when there is nothing planned that week — saving an empty
  /// template is a thing you would only ever do by accident.
  Future<WeekTemplate?> saveWeekAsTemplate({
    required DateTime anchor,
    required String name,
  }) async {
    final DateTime monday = startOfWeek(anchor);
    final Map<DateTime, List<MealPlanEntry>> week = await entriesBetween(
      monday,
      addDays(monday, 6),
    );

    final List<TemplateEntry> entries = WeekTemplate.from(week);
    if (entries.isEmpty) return null;

    final DateTime now = _now();
    final WeekTemplate template = WeekTemplate(
      id: _newId(),
      name: name.trim(),
      entries: entries,
      updatedAt: now,
    );

    await _db.transaction(() async {
      await _db
          .into(_db.planTemplates)
          .insertOnConflictUpdate(
            PlanTemplateRow(
              id: template.id,
              userId: _userId,
              name: template.name,
              entries: template.encodeEntries(),
              updatedAt: now,
            ),
          );
      await _queue.enqueue(
        entityTable: templatesTable,
        entityId: template.id,
        operation: WriteOperation.upsert,
        payload: <String, Object?>{
          'id': template.id,
          'user_id': _userId,
          'name': template.name,
          'entries': <Map<String, Object?>>[
            for (final TemplateEntry entry in entries) entry.toJson(),
          ],
          // A row that was deleted and is being written again — an undo,
          // a restore, the same name re-added — has to come back rather than
          // stay a tombstone (spec §7.1).
          'is_deleted': false,
          'updated_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });

    return template;
  }

  /// Puts [template] onto the week containing [anchor], and says how many
  /// meals it added.
  ///
  /// **Additive.** It never clears a day first: silently deleting a week
  /// somebody had already planned is unrecoverable, and adding to a day is
  /// something they can see and undo. Entries arrive PLANNED, never logged —
  /// the same rule [copyDay] follows, and for the same reason (§4).
  Future<int> applyTemplate({
    required WeekTemplate template,
    required DateTime anchor,
  }) async {
    int added = 0;
    for (final ({DateTime date, TemplateEntry entry}) placed
        in template.onWeekOf(anchor)) {
      await add(
        date: placed.date,
        slot: placed.entry.slot,
        refType: placed.entry.refType,
        refId: placed.entry.refId,
        servings: placed.entry.servings,
      );
      added++;
    }
    return added;
  }

  Future<void> deleteTemplate(String id) {
    final DateTime now = _now();
    return _db.transaction(() async {
      await (_db.delete(
        _db.planTemplates,
      )..where(($PlanTemplatesTable t) => t.id.equals(id))).go();
      await _queue.enqueue(
        entityTable: templatesTable,
        entityId: id,
        operation: WriteOperation.delete,
        payload: <String, Object?>{
          'id': id,
          // Stated, not left to the server: the tombstone records the deleting
          // writer's own clock, so an Undo from this same device is always
          // newer than the deletion it undoes (spec §7.1).
          'updated_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });
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
