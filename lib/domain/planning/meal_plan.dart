import 'package:meta/meta.dart';

import '../models/macros.dart';
import 'nutrient_coverage.dart';

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
    this.coverage = const NutrientCoverage.notRecorded(),
    this.unreadFields = const <String, Object?>{},
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

  /// How much of [macros]' minor nutrients the numbers actually speak for
  /// (spec §5.6).
  ///
  /// Frozen with everything else, and for the same reason: once a meal is
  /// eaten its ingredients are no longer reachable, so a partial total can
  /// never be re-qualified from today's library. Editing the recipe tomorrow
  /// must not make yesterday's fibre look complete.
  ///
  /// Defaults to [MinorCoverage.notRecorded] so that every snapshot frozen
  /// before this existed says so, rather than claiming a completeness nothing
  /// ever checked.
  final NutrientCoverage coverage;

  /// Keys this version does not understand, carried so it cannot destroy them.
  ///
  /// A snapshot is frozen history, and a *newer* client may have written
  /// fields this one has never heard of. Sync and export pass the stored JSON
  /// across verbatim, but a local edit — changing a portion, dragging a meal
  /// to another slot — reads the row into this object and writes it back out.
  /// Without somewhere to put them, that round trip would silently delete
  /// another version's record of what was eaten, permanently and for both
  /// people (§4).
  ///
  /// Deliberately opaque: this version does not interpret them, it only
  /// promises not to lose them.
  final Map<String, Object?> unreadFields;

  @override
  bool operator ==(Object other) =>
      other is MacroSnapshot &&
      other.macros == macros &&
      other.servings == servings &&
      other.coverage == coverage &&
      other.capturedAt == capturedAt &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(macros, servings, coverage, capturedAt, label);

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
    required NutrientCoverage coverage,
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
        // Required, not defaulted. Defaulting to `ofOne(liveMacros)` looked
        // harmless and was the whole bug wearing a hat: a recipe's summed
        // total is non-null whenever *any* ingredient stated the nutrient, so
        // `ofOne` answered "complete" for precisely the partial recipe this
        // exists to qualify — and froze that claim into history, which is
        // worse than the absent key it replaced. Making it required means a
        // caller that has not thought about coverage cannot compile.
        //
        // Scaling a portion cannot change what was known: half a recipe whose
        // fibre was partial is still partial.
        coverage: coverage,
      ),
    );
  }

  /// Puts this entry back to merely planned.
  ///
  /// The snapshot goes with it. §4 freezes a snapshot so that *editing a
  /// recipe* can never rewrite a past day — it does not freeze the day
  /// against its owner, and someone saying "I did not eat that after all" is
  /// the owner correcting their own record. Leaving the numbers behind would
  /// keep a meal in the day's history that the day no longer claims happened.
  MealPlanEntry unlog() => MealPlanEntry(
    id: id,
    dayId: dayId,
    slot: slot,
    refType: refType,
    refId: refId,
    servings: servings,
    // Unlogging a thing that was never planned still leaves it on the day —
    // it is on the plate list either way, and losing the row entirely is
    // what the delete gesture is for.
    isPlanned: true,
    loggedAt: null,
    macroSnapshot: null,
  );

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
