import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../local/hearth_database.dart';

/// Maps plan entries, snapshots, and targets between domain and rows.
///
/// The snapshot is stored as JSON rather than columns because it is a frozen
/// record, never queried or recomputed — spreading it across columns would
/// invite exactly the "just update this one field" edit that spec §4 forbids.
abstract final class PlanMapper {
  static String slotToSql(MealSlot slot) => slot.name;

  static MealSlot slotFromSql(String value) => MealSlot.values.firstWhere(
    (MealSlot slot) => slot.name == value,
    orElse: () => MealSlot.snack,
  );

  static String refTypeToSql(PlanRefType type) => type.name;

  static PlanRefType refTypeFromSql(String value) =>
      value == 'recipe' ? PlanRefType.recipe : PlanRefType.food;

  /// Keys this version writes. Anything else found on the way in is carried
  /// in `unreadFields` and written back untouched, so a local edit cannot
  /// delete a newer client's record of a frozen meal.
  static const Set<String> _snapshotKeys = <String>{
    'kcal',
    'protein_g',
    'carb_g',
    'fat_g',
    'fiber_g',
    'sodium_mg',
    'cholesterol_mg',
    'coverage',
    'servings',
    'captured_at',
    'label',
  };

  static Map<String, Object?> snapshotToJson(MacroSnapshot snapshot) =>
      <String, Object?>{
        // First, so a key this version does understand always wins over a
        // stale copy of itself.
        ...snapshot.unreadFields,
        'kcal': snapshot.macros.kcal,
        'protein_g': snapshot.macros.proteinG,
        'carb_g': snapshot.macros.carbG,
        'fat_g': snapshot.macros.fatG,
        // The minor three, written as null when unknown rather than left out
        // (spec §5.6). A snapshot is the whole of an entry's history — once
        // logged, an entry answers from this and never asks the food again —
        // so anything missing here is not merely undisplayed, it is gone, and
        // rule 3 forbids going back to put it in.
        'fiber_g': snapshot.macros.fiberG,
        'sodium_mg': snapshot.macros.sodiumMg,
        'cholesterol_mg': snapshot.macros.cholesterolMg,
        // How much of those numbers the minor three actually speak for
        // (spec §5.6). Written alongside them rather than derived later,
        // because once a meal is eaten its ingredients are gone and a partial
        // total can never be re-qualified.
        'coverage': snapshot.coverage.toJson(),
        'servings': snapshot.servings,
        'captured_at': snapshot.capturedAt.toIso8601String(),
        'label': snapshot.label,
      };

  /// Rebuilds a snapshot from stored JSON.
  ///
  /// Deliberately tolerant of missing fields: a snapshot is history, and
  /// history that fails to parse is worse than history with a zero in it.
  static MacroSnapshot? snapshotFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;

    return MacroSnapshot(
      macros: Macros(
        kcal: _double(decoded['kcal']),
        proteinG: _double(decoded['protein_g']),
        carbG: _double(decoded['carb_g']),
        fatG: _double(decoded['fat_g']),
        // No `_double`, which answers 0 for a missing key. An older snapshot
        // written before this carried them says nothing about fibre, and
        // nothing is not none — a zero here would put a claim into history
        // that nobody ever made.
        fiberG: _nullableDouble(decoded['fiber_g']),
        sodiumMg: _nullableDouble(decoded['sodium_mg']),
        cholesterolMg: _nullableDouble(decoded['cholesterol_mg']),
      ),
      // Absent, malformed, or written by a newer version than this reader
      // understands all read as "not recorded" — never as complete. A
      // snapshot frozen before coverage existed cannot earn it retroactively.
      coverage: NutrientCoverage.fromJson(decoded['coverage']),
      unreadFields: <String, Object?>{
        for (final MapEntry<String, Object?> field in decoded.entries)
          if (!_snapshotKeys.contains(field.key)) field.key: field.value,
      },
      servings: _double(decoded['servings']),
      capturedAt:
          DateTime.tryParse(decoded['captured_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      label: decoded['label']?.toString() ?? '',
    );
  }

  static MealPlanEntry entryToDomain(MealPlanEntryRow row) => MealPlanEntry(
    id: row.id,
    dayId: row.dayId,
    slot: slotFromSql(row.mealSlot),
    refType: refTypeFromSql(row.refType),
    refId: row.refId,
    servings: row.servings,
    isPlanned: row.isPlanned,
    isLogged: row.isLogged,
    loggedAt: row.loggedAt,
    macroSnapshot: snapshotFromJson(row.macroSnapshot),
  );

  static MealPlanEntriesCompanion entryToCompanion(
    MealPlanEntry entry,
    DateTime updatedAt,
  ) => MealPlanEntriesCompanion.insert(
    id: entry.id,
    dayId: entry.dayId,
    mealSlot: slotToSql(entry.slot),
    refType: refTypeToSql(entry.refType),
    refId: entry.refId,
    servings: entry.servings,
    isPlanned: Value<bool>(entry.isPlanned),
    isLogged: Value<bool>(entry.isLogged),
    loggedAt: Value<DateTime?>(entry.loggedAt),
    macroSnapshot: Value<String?>(
      entry.macroSnapshot == null
          ? null
          : jsonEncode(snapshotToJson(entry.macroSnapshot!)),
    ),
    updatedAt: updatedAt,
  );

  static Map<String, Object?> entryToJson(
    MealPlanEntry entry, {
    required DateTime updatedAt,
  }) => <String, Object?>{
    'id': entry.id,
    'meal_plan_day_id': entry.dayId,
    'meal_slot': slotToSql(entry.slot),
    'ref_type': refTypeToSql(entry.refType),
    'ref_id': entry.refId,
    'servings': entry.servings,
    'is_planned': entry.isPlanned,
    'is_logged': entry.isLogged,
    'logged_at': entry.loggedAt?.toIso8601String(),
    'macro_snapshot': entry.macroSnapshot == null
        ? null
        : snapshotToJson(entry.macroSnapshot!),
    // A row that was deleted and is being written again — Undo, or the
    // restore behind it — has to come back rather than stay a tombstone
    // (spec §7.1).
    'is_deleted': false,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  static MacroTargets targetsToDomain(MacroTargetRow row) => MacroTargets(
    kcal: row.kcal,
    proteinG: row.proteinG,
    carbG: row.carbG,
    fatG: row.fatG,
    // No `?? 0`: null is "use the Daily Value", and a zero would be a target
    // of nothing (spec §5.6).
    fiberG: row.fiberG,
    sodiumMg: row.sodiumMg,
    cholesterolMg: row.cholesterolMg,
  );

  static Map<String, Object?> targetsToJson({
    required String id,
    required String userId,
    required DateTime weekStart,
    required MacroTargets targets,
    required DateTime updatedAt,
  }) => <String, Object?>{
    'id': id,
    'user_id': userId,
    'week_start_date': _dateOnly(weekStart),
    'kcal': targets.kcal,
    'protein_g': targets.proteinG,
    'fiber_g': targets.fiberG,
    'sodium_mg': targets.sodiumMg,
    'cholesterol_mg': targets.cholesterolMg,
    'carb_g': targets.carbG,
    'fat_g': targets.fatG,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  static Map<String, Object?> dayToJson({
    required MealPlanDayRow day,
    required String userId,
  }) => <String, Object?>{
    'id': day.id,
    'user_id': userId,
    'day': _dateOnly(day.day),
    'notes': day.notes,
    'updated_at': day.updatedAt.toUtc().toIso8601String(),
  };

  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  /// Null for anything that is not a number, including a key that is not
  /// there. The four above fall back to zero because a snapshot without
  /// calories is a broken snapshot; the minor three do not, because a
  /// snapshot without fibre is an ordinary one (spec §5.6).
  static double? _nullableDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
