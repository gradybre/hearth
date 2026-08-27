import 'package:meta/meta.dart';

import '../models/macros.dart';

/// The four meal slots a day is divided into (spec §5.6).
enum MealSlot { breakfast, lunch, dinner, snack }

/// What a plan entry points at.
enum PlanRefType { food, recipe }

/// Macros and portion frozen at the moment of logging.
///
/// **This is the mechanism behind "frozen log history" (spec §4).** Once
/// written it is never recomputed: editing or deleting the recipe or food it
/// came from cannot rewrite what you ate last Tuesday. Soft-deleting rather
/// than removing foods keeps the reference resolvable, but the numbers here are
/// the source of truth for history either way.
@immutable
class MacroSnapshot {
  const MacroSnapshot({
    required this.macros,
    required this.servings,
    required this.capturedAt,
    required this.label,
  });

  /// Macros for the portion actually eaten — already multiplied by [servings].
  final Macros macros;

  /// The portion logged, frozen alongside the macros so the history can show
  /// "1.5 servings" even if the recipe's yield later changes.
  final double servings;

  final DateTime capturedAt;

  /// What the food or recipe was called at log time, so a later rename doesn't
  /// make old history unreadable.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is MacroSnapshot &&
      other.macros == macros &&
      other.servings == servings &&
      other.capturedAt == capturedAt &&
      other.label == label;

  @override
  int get hashCode => Object.hash(macros, servings, capturedAt, label);

  @override
  String toString() => 'MacroSnapshot($label, ${servings}x, $macros)';
}

/// One food or recipe placed in a meal slot on a day (spec §4).
///
/// A single entry carries both states: [isPlanned] for "this is the plan" and
/// [isLogged] for "this is what happened". Confirming a planned item as eaten
/// is one tap (spec §5.6).
@immutable
class MealPlanEntry {
  const MealPlanEntry({
    required this.id,
    required this.dayId,
    required this.slot,
    required this.refType,
    required this.refId,
    required this.servings,
    this.isPlanned = true,
    this.isLogged = false,
    this.loggedAt,
    this.macroSnapshot,
  });

  final String id;
  final String dayId;
  final MealSlot slot;
  final PlanRefType refType;
  final String refId;

  /// The portion. Independent per person — no shared portion maths (spec §5.6).
  final double servings;

  final bool isPlanned;
  final bool isLogged;
  final DateTime? loggedAt;

  /// Set exactly once, when the entry is logged. Null while merely planned.
  final MacroSnapshot? macroSnapshot;

  /// Marks this entry eaten, freezing [liveMacros] at the given portion.
  ///
  /// [liveMacros] is the macros for a *single* serving as they stand right
  /// now; they are scaled by the portion and then frozen.
  MealPlanEntry log({
    required Macros liveMacros,
    required DateTime at,
    required String label,
    double? portion,
  }) {
    final double logged = portion ?? servings;
    return MealPlanEntry(
      id: id,
      dayId: dayId,
      slot: slot,
      refType: refType,
      refId: refId,
      servings: logged,
      isPlanned: isPlanned,
      isLogged: true,
      loggedAt: at,
      macroSnapshot: MacroSnapshot(
        macros: liveMacros.scaledBy(logged),
        servings: logged,
        capturedAt: at,
        label: label,
      ),
    );
  }

  /// The macros this entry contributes to a day.
  ///
  /// A logged entry always answers from its snapshot — never from the current
  /// state of the recipe or food. A merely-planned entry has to be costed
  /// live, which is why [plannedMacros] must be supplied for it.
  Macros contribution({Macros? plannedMacros}) {
    final MacroSnapshot? snapshot = macroSnapshot;
    if (isLogged && snapshot != null) return snapshot.macros;
    if (plannedMacros == null) return Macros.zero;
    return plannedMacros.scaledBy(servings);
  }

  MealPlanEntry copyWith({double? servings, bool? isPlanned, MealSlot? slot}) =>
      MealPlanEntry(
        id: id,
        dayId: dayId,
        slot: slot ?? this.slot,
        refType: refType,
        refId: refId,
        servings: servings ?? this.servings,
        isPlanned: isPlanned ?? this.isPlanned,
        isLogged: isLogged,
        loggedAt: loggedAt,
        // Deliberately carried through untouched: editing a plan entry must
        // never disturb a snapshot that has already been taken.
        macroSnapshot: macroSnapshot,
      );

  @override
  bool operator ==(Object other) => other is MealPlanEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
