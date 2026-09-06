import 'package:uuid/uuid.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
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
  /// replayed action puts back one meal rather than two. Queued after the
  /// delete it undoes, so the ordering that reaches the server is the ordering
  /// the user performed.
  Future<MealPlanEntry> restore(
    MealPlanEntry entry, {
    required DateTime date,
  }) async {
    final DateTime now = _now();

    return _db.transaction(() async {
      // The date comes from the caller because a day's id is a uuid5 of it
      // and cannot be read back. `ensureDay` finds the existing row — removing
      // an entry does not remove its day — so this is a guard rather than a
      // creation in the ordinary case.
      final MealPlanDayRow day = await _store.ensureDay(
        userId: _userId,
        date: date,
        idFactory: () => entry.dayId,
        updatedAt: now,
      );
      await _queueDay(day, now);

      await _store.upsertEntry(entry, updatedAt: now);
      await _queueEntry(entry, now);
      return entry;
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
      monday.add(const Duration(days: 6)),
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
          'updated_at': now.toIso8601String(),
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
        payload: <String, Object?>{'id': id},
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
