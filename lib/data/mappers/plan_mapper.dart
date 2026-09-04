import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
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

  static Map<String, Object?> snapshotToJson(MacroSnapshot snapshot) =>
      <String, Object?>{
        'kcal': snapshot.macros.kcal,
        'protein_g': snapshot.macros.proteinG,
        'carb_g': snapshot.macros.carbG,
        'fat_g': snapshot.macros.fatG,
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
      ),
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
    'updated_at': updatedAt.toIso8601String(),
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
    'updated_at': updatedAt.toIso8601String(),
  };

  static Map<String, Object?> dayToJson({
    required MealPlanDayRow day,
    required String userId,
  }) => <String, Object?>{
    'id': day.id,
    'user_id': userId,
    'day': _dateOnly(day.day),
    'notes': day.notes,
    'updated_at': day.updatedAt.toIso8601String(),
  };

  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
