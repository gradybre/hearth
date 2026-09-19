import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/local/preference_store.dart';
import '../../domain/foods/eatable_foods.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/portion_unit.dart';
import '../../domain/planning/recent_log.dart';
import '../../domain/planning/week.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../foods/external_food_results.dart';
import '../foods/food_search_controller.dart';
import 'day_picker_sheet.dart';
import 'entry_resolver.dart';
import 'logging_intent.dart';

/// Adds something to a slot, or confirms something already planned.
///
/// Logging speed is the success bar, so the default path is deliberately
/// short: pick a thing, tap Log. The portion stepper is right there for the
/// half-servings that come up in real life, but nothing has to be adjusted to
/// finish (spec §5.6).
Future<void> showLogSheet(
  BuildContext context, {
  required DateTime date,
  required MealSlot slot,
  ResolvedEntry? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) =>
      _LogSheet(date: date, slot: slot, existing: existing),
);

class _LogSheet extends ConsumerStatefulWidget {
  const _LogSheet({required this.date, required this.slot, this.existing});

  final DateTime date;
  final MealSlot slot;
  final ResolvedEntry? existing;

  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  final TextEditingController _search = TextEditingController();

  /// What the user is about to log: a recipe, a food, or the entry they opened.
  Recipe? _recipe;
  Food? _food;
  late double _servings = widget.existing?.entry.servings ?? 1;

  /// Which of the food's servings [_servings] counts (spec R12).
  ///
  /// Null is the ordinary state: a count of the food's first serving, which
  /// is what the stored column has always meant. It is only ever set from a
  /// package-derived amount, where the count and the row it counts are one
  /// answer — storing the count alone is what made a planned 30 oz reopen
  /// at twice its calories.
  late String? _servingOptionId = widget.existing?.entry.servingOptionId;

  /// Which unit the portion is being *entered* in (spec §5.6): one of the
  /// food's own servings, or a raw gram/ounce amount.
  ///
  /// Only that. `_servings`, and the `servings` column behind it, have always
  /// meant multiples of the food's default serving — `EntryResolver` rebuilds
  /// from `defaultServing` — so storing a count in any other unit
  /// reinterprets it everywhere later: projecting a planned meal, repeating a
  /// recent one. The first version of this did exactly that, and re-opening a
  /// meal logged as 1.7 x 100 g and pressing Update turned 170 kcal into 289
  /// without a keystroke.
  ///
  /// (Correcting a portion no longer re-costs from `defaultServing` — see
  /// `_frozenPerServing` — but the invariant still holds everywhere else, and
  /// a count stored in the wrong unit would still be wrong there.)
  ///
  /// So this changes the number under your thumb, never the number in the
  /// row. Half a pot is still half a pot to everything downstream, and 125 g
  /// of a food served in 170 g pots is stored as 0.735 of one.
  ///
  /// Null until something is chosen, which is what [_unitFrom] resolves.
  PortionUnit? _entryUnit;

  /// The unit the amount was last actually *entered* in.
  ///
  /// Not the same question as [_entryUnit], which is only what the field is
  /// being displayed in. Switching chips asks to read one portion another
  /// way; it does not restate the amount, so it must move neither the stored
  /// portion nor the macros underneath it. Only typing or stepping does.
  ///
  /// Null until something is entered, which is what [_basisFor] resolves.
  PortionUnit? _amountBasis;

  /// The unit this was last typed in, read back off the device.
  ///
  /// For a *new* portion that is the one this food was last logged in;
  /// for an existing entry it is the one that entry itself was typed in,
  /// which is a different question and deliberately never answered by the
  /// former — see `PreferenceStore.logUnitForEntry`.
  String? _rememberedUnitId;

  /// The food this sheet is about, once the library has it.
  ///
  /// An entry being corrected never went through the picker, so its food has
  /// to be recovered from the row — otherwise the screen where a portion is
  /// most often corrected is the one screen with no units on it.
  Food? _foodFor(Map<String, Food> foods) {
    if (_food != null) return _food;
    final MealPlanEntry? entry = widget.existing?.entry;
    if (entry == null || entry.refType != PlanRefType.food) return null;
    return foods[entry.refId];
  }

  /// The serving [_servings] counts.
  ///
  /// The named row where there is one, the food's first where there is not,
  /// and nothing at all when a named row has since been removed — falling
  /// back to the default there would re-cost the portion against a different
  /// row, which is the whole of the defect this reference exists to prevent.
  ServingOption? _standardFor(Map<String, Food> foods) {
    final Food? food = _foodFor(foods);
    if (food == null) return null;
    final String? id = _servingOptionId;
    if (id == null) return food.defaultServing;
    for (final ServingOption option in food.servingOptions) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// What actually gets written: the per-serving macros, the portion, and
  /// which serving that portion counts.
  ///
  /// The three travel together because they only mean anything together. A
  /// package-derived amount is six of the row the label was reviewed against
  /// — not six of whichever row the food lists first — so the count is
  /// converted into that row's own count and the id goes with it.
  ({Macros perServing, double portion, String? servingOptionId}) _basis({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) {
    // A meal already logged is corrected against what it was logged as, and
    // its reference is part of that record (spec §4).
    if (_frozenPerServing case final Macros frozen) {
      return (
        perServing: frozen,
        portion: _servings,
        servingOptionId: widget.existing?.entry.servingOptionId,
      );
    }
    final PackagePortion? package = _packagePortion(foods);
    if (package != null && package.servingCount > 0) {
      return (
        perServing: package.macros.scaledBy(1 / package.servingCount),
        portion: package.servingCount,
        servingOptionId: package.serving.id,
      );
    }
    return (
      perServing: _perServing(foods: foods, recipes: recipes),
      portion: _servings,
      servingOptionId: _servingOptionId,
    );
  }

  /// Which of [units] the portion is entered in: what was tapped, else what
  /// was remembered, else the serving the portion is actually counted in.
  ///
  /// [standard] before `units.first`, and the distinction is the whole of
  /// it: `portionUnitsFor` lists every same-kind row in the food's own
  /// order, so a reopened entry counted in the second of two rows reading
  /// '1 cup' showed the *first* chip beside the second row's calories. The
  /// arithmetic was right either way; the two lines named different rows,
  /// which is exactly the hazard a package relationship creates.
  PortionUnit? _unitFrom(List<PortionUnit> units, {ServingOption? standard}) =>
      _entryUnit ??
      PortionUnit.withId(units, _rememberedUnitId) ??
      PortionUnit.withId(
        units,
        standard == null ? null : PortionUnit.serving(standard).id,
      ) ??
      (units.isEmpty ? null : units.first);

  /// Reads back the unit stored under [key], if any is.
  Future<void> _recallUnit(String key) async {
    final String? id = await ref.read(preferenceStoreProvider).read(key);
    if (!mounted || id == null) return;
    setState(() => _rememberedUnitId = id);
  }

  /// Remembers how this entry's portion was typed.
  ///
  /// Nothing is written for the default serving — that is what a missing key
  /// already means — and a key that is no longer true is deleted rather than
  /// left to re-open a corrected portion in the unit it used to be in.
  Future<void> _recordEntryUnit(
    String entryId,
    PortionUnit? unit,
    Map<String, Food> foods,
  ) async {
    // A recipe, or a food with no serving at all: there was never a unit to
    // record and there is none to clear.
    if (unit == null) return;
    final PreferenceStore preferences = ref.read(preferenceStoreProvider);
    final String key = '${PreferenceStore.logUnitForEntry}$entryId';
    final ServingOption? standard = _standardFor(foods);
    // Never throws. By the time this runs the meal is already saved, and
    // failing here would leave the sheet open over a committed entry — one
    // more tap of "Log it" and the day has the meal twice. Which unit a
    // portion was typed in is the least important thing this save does, and
    // it should not be the only one that can undo the rest.
    try {
      if (!unit.isRaw && unit.serving?.id == standard?.id) {
        await preferences.delete(key);
        return;
      }
      await preferences.write(key, unit.id);
    } on Object {
      // The portion, the macros and the day are all already right. This
      // costs the next correction its unit and nothing else.
    }
  }

  bool _busy = false;

  bool get _isExisting => widget.existing != null;

  /// How far the day being logged to is from today, on the calendar.
  ///
  /// One reading of the clock, used for both the words and the colour. Two
  /// would be two sources of truth for one fact — and this change has just
  /// finished collapsing three copies of the weekday list into one.
  int get _daysFromToday => calendarDaysBetween(DateTime.now(), widget.date);

  /// The day this is going to, in the fewest words that identify it.
  ///
  /// "Today" and "Yesterday" rather than a date to work out; a weekday and a
  /// date for anything further off, because "Thursday" alone is two different
  /// Thursdays.
  String _when([int? delta]) => switch (delta ?? _daysFromToday) {
    0 => 'Today',
    -1 => 'Yesterday',
    1 => 'Tomorrow',
    _ => '${weekdayName(widget.date)} ${shortDate(widget.date)}',
  };

  @override
  void initState() {
    super.initState();
    // A correction opens in the unit it was typed in. The food it belongs to
    // may not have arrived yet, so this is read by entry id and matched to a
    // unit once the library resolves.
    final MealPlanEntry? entry = widget.existing?.entry;
    if (entry != null) {
      unawaited(_recallUnit('${PreferenceStore.logUnitForEntry}${entry.id}'));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The basis a logged meal was frozen on, per serving.
  ///
  /// The snapshot stores the total and the portion it was for, so one
  /// serving's worth is the one divided by the other. Null for a planned
  /// entry, which has no snapshot and should cost what the food costs today.
  Macros? get _frozenPerServing {
    final MealPlanEntry? entry = widget.existing?.entry;
    if (entry == null || !entry.isLogged) return null;
    final MacroSnapshot? snapshot = entry.macroSnapshot;
    if (snapshot == null) return null;
    // The row's own count as a fallback divisor. Nothing writes a snapshot
    // with a zero portion — the stepper refuses one — but dividing by it
    // would fall back to the live food, which is the bug this exists to fix.
    final double portion = snapshot.servings > 0
        ? snapshot.servings
        : entry.servings;
    if (portion <= 0) return null;
    return snapshot.macros.scaledBy(1 / portion);
  }

  /// The package-derived macros for the current portion, when this food can
  /// only answer the unit the amount was *entered* in through a reviewed
  /// package relationship (spec R9–R12). Null in every ordinary case.
  ///
  /// Keyed on [_amountBasis] rather than on whichever unit the field happens
  /// to be displayed in, and that distinction is the entire reason the field
  /// exists. Reopening a planned meal in the unit it was last typed in, or
  /// tapping a chip to read one portion another way, is not a new amount: it
  /// may move neither the stored portion nor the macros. Only typing or
  /// stepping sets a basis, so only typing or stepping can reach this.
  PackagePortion? _packagePortion(Map<String, Food> foods) {
    if (_recipe != null) return null;
    final PortionUnit? basis = _amountBasis;
    if (basis == null) return null;
    final Food? food = _foodFor(foods);
    if (food == null) return null;
    return packagePortionFor(
      food: food,
      basis: basis,
      servings: _servings,
      // Counted against the row this entry names, not the food's first.
      standard: _standardFor(foods),
    );
  }

  bool _usesApproximatePackage(
    Map<String, Food> foods,
    Map<String, Recipe> recipes,
  ) {
    final MealPlanEntry? entry = widget.existing?.entry;
    if (entry?.isLogged ?? false) {
      return entry?.macroSnapshot?.usesApproximatePackageNutrition ?? false;
    }
    final Recipe? recipe =
        _recipe ??
        (entry?.refType == PlanRefType.recipe ? recipes[entry?.refId] : null);
    if (recipe != null) {
      return MacroCalculator.forRecipe(
        recipe,
        foods: foods,
      ).usesApproximatePackageNutrition;
    }
    final PackagePortion? package = _packagePortion(foods);
    if (package != null) return package.isApproximate;
    final Food? food = _foodFor(foods);
    return _servingOptionId != null &&
        food?.activePackageServing?.id == _servingOptionId &&
        (food?.packageNutrition?.isApproximate ?? false);
  }

  Macros _perServing({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) {
    // A meal that has already been logged is corrected against what it was
    // logged as, never against what its food says today (spec §4, rule 3).
    //
    // `ResolvedEntry.perServing` is built from the food as it stands now —
    // right for a planned meal, which has not happened yet, and wrong for one
    // that has. Correcting the portion is the one screen that writes a new
    // snapshot over an old meal, so it is the one place an edit made months
    // later can reach back and change what was eaten.
    if (_frozenPerServing case final Macros frozen) return frozen;
    // A raw amount typed in a unit this food can only answer through a
    // reviewed package relationship (spec R9–R12). The macros come from the
    // *selected* nutrition row — 30 oz of a 10 oz package holding two 1 cup
    // servings is six of the row the relationship was reviewed against, not
    // six of whichever row happens to be first.
    //
    // Divided back out to a per-default-serving figure because that is what
    // the `servings` column has always counted, and everything downstream
    // rebuilds from it. The product of the two is what gets frozen, so the
    // total is the selected row's answer either way.
    final PackagePortion? package = _packagePortion(foods);
    if (package != null && _servings > 0) {
      return package.macros.scaledBy(1 / _servings);
    }
    if (widget.existing != null) return widget.existing!.perServing;
    if (_recipe != null) {
      return MacroCalculator.forRecipe(_recipe!, foods: foods).perServing;
    }
    final ServingOption? serving = _food?.defaultServing;
    return serving?.macros ?? Macros.zero;
  }

  /// How much of [_perServing]'s minor nutrients those numbers speak for.
  ///
  /// Computed beside them rather than inferred from them: a recipe's total is
  /// non-null whenever *any* ingredient stated the nutrient, so reading it
  /// back off the sum answers "complete" for a partial recipe (spec §5.6).
  NutrientCoverage _coverage({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) {
    // Frozen alongside the numbers, and for the same reason: how much of the
    // day those numbers spoke for is part of what was recorded.
    if (widget.existing?.entry.macroSnapshot case final MacroSnapshot snap
        when widget.existing!.entry.isLogged) {
      return snap.coverage;
    }
    // Read off the same row as the macros, never off `defaultServing`. Two
    // rows can both read '1 cup' and know different nutrients, and a
    // coverage claim frozen against the wrong one is permanent (spec §4,
    // §5.6) — which is the exact defect NutrientCoverage exists to prevent.
    final PackagePortion? package = _packagePortion(foods);
    if (package != null) return package.coverage;
    if (widget.existing != null) return widget.existing!.liveCoverage;
    if (_recipe != null) {
      return MacroCalculator.forRecipe(_recipe!, foods: foods).coverage;
    }
    final ServingOption? serving = _food?.defaultServing;
    return serving == null
        ? const NutrientCoverage.notRecorded()
        : NutrientCoverage.ofOne(serving.macros);
  }

  /// What this meal is called.
  ///
  /// For one already logged, the name it was logged under — not what its food
  /// is called today. `ResolvedEntry.label` reads the live food, so a
  /// correction would rename a June meal to whatever the food has since been
  /// renamed to, which is the thing `MacroSnapshot.label` exists to prevent:
  /// once the food is soft-deleted, that name is all the row has left.
  String get _label =>
      widget.existing?.entry.macroSnapshot?.label.isNotEmpty ?? false
      ? widget.existing!.entry.macroSnapshot!.label
      : widget.existing?.label ?? _recipe?.title ?? _food?.name ?? '';

  Future<void> _log({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
    PortionUnit? typedIn,
  }) async {
    setState(() => _busy = true);
    try {
      final ({Macros perServing, double portion, String? servingOptionId})
      basis = _basis(foods: foods, recipes: recipes);
      final NutrientCoverage coverage = _coverage(
        foods: foods,
        recipes: recipes,
      );
      // Null for a meal already logged: its numbers came from its own frozen
      // snapshot, so the qualifier frozen beside them is the one that still
      // describes them — whatever the food's package relationship says today.
      final bool? approximate = (widget.existing?.entry.isLogged ?? false)
          ? null
          : _usesApproximatePackage(foods, recipes);

      if (_isExisting) {
        await ref
            .read(planRepositoryProvider)
            .logEntry(
              widget.existing!.entry.id,
              liveMacros: basis.perServing,
              liveCoverage: coverage,
              usesApproximatePackage: approximate,
              servingOptionId: basis.servingOptionId,
              label: _label,
              portion: basis.portion,
            );
        await _recordEntryUnit(widget.existing!.entry.id, typedIn, foods);
      } else {
        final MealPlanEntry added = await ref
            .read(planRepositoryProvider)
            .add(
              date: widget.date,
              slot: widget.slot,
              refType: _recipe != null ? PlanRefType.recipe : PlanRefType.food,
              refId: _recipe?.id ?? _food!.id,
              servings: basis.portion,
              servingOptionId: basis.servingOptionId,
              loggedMacros: basis.perServing,
              loggedCoverage: coverage,
              usesApproximatePackage: approximate ?? false,
              label: _label,
            );
        await _recordEntryUnit(added.id, typedIn, foods);
      }
      ref.invalidate(dayEntriesProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _plan({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
    PortionUnit? typedIn,
  }) async {
    setState(() => _busy = true);
    try {
      // The same basis a log writes, minus the macros. A planned entry has
      // no snapshot to answer from later, so the row it counts is the only
      // thing standing between 30 oz and a reopened day that doubles it.
      final ({Macros perServing, double portion, String? servingOptionId})
      basis = _basis(foods: foods, recipes: recipes);
      final MealPlanEntry added = await ref
          .read(planRepositoryProvider)
          .add(
            date: widget.date,
            slot: widget.slot,
            refType: _recipe != null ? PlanRefType.recipe : PlanRefType.food,
            refId: _recipe?.id ?? _food!.id,
            servings: basis.portion,
            servingOptionId: basis.servingOptionId,
          );
      await _recordEntryUnit(added.id, typedIn, foods);
      ref.invalidate(dayEntriesProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Logs a recent thing again in one tap, at the portion it was last logged
  /// at (spec §5.6).
  ///
  /// Macros are recomputed from the current library rather than copied from
  /// the old snapshot: repeating a meal should record what that food is now.
  ///
  /// Costed against the serving that portion actually counted, never against
  /// whichever row the food happens to list first. A package-derived amount
  /// is six of the row its label was reviewed against, and reading that six
  /// against another row freezes double the meal it claims to repeat —
  /// history that §4 then forbids correcting.
  Future<void> _logAgain(
    RecentLog recent, {
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) async {
    final Food? food = recent.refType == PlanRefType.food
        ? foods[recent.refId]
        : null;
    final ServingOption? serving = food == null
        ? null
        : EntryResolver.servingForEntry(food, recent.servingOptionId);

    if (recent.refType == PlanRefType.food && serving == null) {
      // Nothing honest to repeat. The default row is a different serving
      // with different macros, and zero is not what was eaten either — so
      // the one-tap path asks rather than guessing, the same answer the
      // plan surface already gives an uncostable entry.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            food == null
                ? '${recent.label} is no longer in your foods.'
                : 'The serving ${recent.label} was logged in has been '
                      'removed. Choose a portion again.',
          ),
        ),
      );
      if (food != null) _choose(food);
      return;
    }

    setState(() => _busy = true);
    try {
      final Recipe? recipe = recent.refType == PlanRefType.recipe
          ? recipes[recent.refId]
          : null;
      final RecipeMacros? recipeMacros = recipe == null
          ? null
          : MacroCalculator.forRecipe(recipe, foods: foods);

      final Macros perServing = switch (recent.refType) {
        PlanRefType.recipe => recipeMacros?.perServing ?? Macros.zero,
        PlanRefType.food => serving!.macros,
      };
      // Beside the numbers, from the same source, for the same reason: a
      // recipe's coverage lives in its ingredients and cannot be read back
      // off its total (spec §5.6). For a food it is read off the very row
      // the macros came from — two rows can both read '1 cup' and know
      // different nutrients.
      final NutrientCoverage coverage = switch (recent.refType) {
        PlanRefType.recipe =>
          recipeMacros?.coverage ?? const NutrientCoverage.notRecorded(),
        PlanRefType.food => NutrientCoverage.ofOne(serving!.macros),
      };
      // Read off the food as it stands now rather than off the old
      // snapshot: the qualifier has to describe the relationship *this*
      // repeat is being costed through (spec R10, R12), and only when the
      // row being counted is the one that relationship is anchored to.
      final bool approximate = switch (recent.refType) {
        PlanRefType.recipe =>
          recipeMacros?.usesApproximatePackageNutrition ?? false,
        PlanRefType.food =>
          recent.servingOptionId != null &&
              food?.activePackageServing?.id == recent.servingOptionId &&
              (food?.packageNutrition?.isApproximate ?? false),
      };

      await ref
          .read(planRepositoryProvider)
          .logAgain(
            recent: recent,
            date: widget.date,
            slot: widget.slot,
            liveMacros: perServing,
            liveCoverage: coverage,
            usesApproximatePackage: approximate,
          );
      ref.invalidate(dayEntriesProvider);
      ref.invalidate(recentLogsProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Assigns this recipe or food across several days at once (spec §5.6's
  /// meal-prep assignment).
  ///
  /// "This batch is my dinner Mon/Tue/Wed" is one decision, so it is one
  /// action — not the same add repeated three times.
  Future<void> _assignAcrossDays() async {
    final List<DateTime>? days = await showDayPicker(
      context,
      title: 'Add to which days?',
      actionLabel: 'Add to days',
    );
    if (days == null || days.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .assignAcrossDays(
            dates: days,
            slot: widget.slot,
            refType: _recipe != null ? PlanRefType.recipe : PlanRefType.food,
            refId: _recipe?.id ?? _food!.id,
            servings: _servings,
          );
      ref.invalidate(dayEntriesProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Uses a food that was just saved from a wider search.
  ///
  /// Read back through the repository rather than picked out of
  /// [foodLibraryProvider]: the save has only just landed, and waiting for the
  /// library stream to re-emit would leave the sheet showing the picker for a
  /// frame after the user chose something.
  Future<void> _useSavedFood(String foodId) async {
    final Food? food = await ref.read(foodRepositoryProvider).byId(foodId);
    if (!mounted || food == null) return;
    _choose(food);
  }

  /// Moves the sheet on to this food, in the unit it was last logged in.
  void _choose(Food food) {
    setState(() {
      _food = food;
      _entryUnit = null;
      _amountBasis = null;
      _rememberedUnitId = null;
      // A different food's servings are not this one's.
      _servingOptionId = null;
    });
    unawaited(_recallUnit('${PreferenceStore.logUnitForFood}${food.id}'));
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .removeEntry(widget.existing!.entry.id);
      ref.invalidate(dayEntriesProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Map<String, Recipe> recipes = <String, Recipe>{
      for (final Recipe r
          in ref.watch(recipeLibraryProvider).value ?? const <Recipe>[])
        r.id: r,
    };
    final Map<String, Food> foods = <String, Food>{
      for (final Food f
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        f.id: f,
    };

    final bool hasChoice = _isExisting || _recipe != null || _food != null;
    final Macros perServing = _perServing(foods: foods, recipes: recipes);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: hasChoice ? 0.5 : 0.8,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext context, ScrollController controller) =>
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(HearthRadius.xl),
                ),
              ),
              child: hasChoice
                  ? _confirmView(controller, perServing, foods, recipes)
                  : _pickerView(controller, recipes, foods),
            ),
      ),
    );
  }

  /// The button the sheet exists to offer, shared by both arrangements above.
  ///
  /// [update] is whether this entry has *already been logged*, which is not
  /// the same as whether it exists: a planned meal exists and has not been
  /// logged, and that is precisely the entry whose button has to say "Log
  /// it". Collapsing the two is how the one button whose whole job is to log
  /// a planned meal stopped saying so.
  Widget _primaryAction({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
    required bool update,
    PortionUnit? typedIn,
  }) => FilledButton(
    onPressed: _busy
        ? null
        : () => _log(foods: foods, recipes: recipes, typedIn: typedIn),
    child: Text(
      _busy
          ? 'Saving…'
          : update
          ? 'Update'
          : 'Log it',
    ),
  );

  Widget _confirmView(
    ScrollController controller,
    Macros perServing,
    Map<String, Food> foods,
    Map<String, Recipe> recipes,
  ) {
    final HearthColors colors = context.colors;
    final Macros total = perServing.scaledBy(_servings);
    final bool alreadyLogged = widget.existing?.entry.isLogged ?? false;
    // Frozen for a meal already logged, live for one about to be (spec R12).
    final MacroSnapshot? frozenSnapshot = widget.existing?.entry.macroSnapshot;
    final bool approximatePackage = alreadyLogged
        ? frozenSnapshot?.usesApproximatePackageNutrition ?? false
        : _usesApproximatePackage(foods, recipes);

    // Which units this portion can be typed in, and which of them it is being
    // typed in. A raw gram or ounce amount is always available for a food
    // measured by mass or volume, so the row now earns its place even for a
    // food with a single stored serving.
    // One reading of the clock for both the words and the colour.
    final int daysFromToday = _daysFromToday;

    final Food? food = _foodFor(foods);
    final ServingOption? standard = _standardFor(foods);
    final List<PortionUnit> units = portionUnitsFor(food, standard: standard);
    final PortionUnit? unit = _unitFrom(units, standard: standard);
    // Rounded for the field only. The stored portion moves when somebody
    // types or steps, never because a chip was tapped: one pot is
    // 5.996473604060913 oz, and a field cannot show that, but a portion that
    // rounded itself every time the unit changed would drift.
    final double count = unit == null
        ? _servings
        : unit.forDisplay(
            unit.countOf(_servings, standard: standard?.amount, food: food),
          );

    // Scrollable, and through the sheet's own controller so that dragging
    // the content also grows the sheet (spec §6.3).
    //
    // The picker half has always had this; the half you reach *after*
    // choosing something never did, and it is the one every logged meal goes
    // through. At three times the text it overflowed by 200 pixels, taking
    // "Log it" off the bottom of the screen with it.
    return SafeArea(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.all(HearthSpacing.lg),
        children: <Widget>[
          Text(_label, style: context.text.sectionHeader),
          const SizedBox(height: HearthSpacing.xs),
          // Where this is going, before what it costs. The sheet named the
          // food and its macros and never said which day or meal it was
          // about — fine on today, and the whole question on a day you have
          // scrolled back to, because the header that knows the date is the
          // thing this sheet is covering (review F05).
          // The accent marks a day *behind* you and nothing else. Planning
          // tomorrow's dinner is what a planner is for, and flagging it the
          // same way as an accidental scroll back to last Tuesday would
          // spend the signal on the routine case and leave the one worth
          // noticing no louder. Never colour alone — the words say which day
          // it is regardless (spec §6.3).
          Text(
            '${widget.slot.label} · ${_when(daysFromToday)}',
            style: context.text.metadata.copyWith(
              color: daysFromToday < 0 ? colors.accent : colors.textMuted,
            ),
          ),
          const SizedBox(height: HearthSpacing.xs),
          Text(
            alreadyLogged
                ? 'Already logged. Adjust the portion or remove it.'
                : '${total.kcal.round()} kcal · '
                      'P ${total.proteinG.round()}  '
                      'C ${total.carbG.round()}  '
                      'F ${total.fatG.round()}',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
          // Said beside the number rather than folded into it: a package
          // printed as 'about 2 servings' gives an exact-looking total that
          // is not an exact measurement (spec R10, R12).
          if (approximatePackage) ...<Widget>[
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Uses approximate package servings',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ],
          const SizedBox(height: HearthSpacing.lg),
          // Which unit the portion is entered in, before how many of it.
          if (units.length > 1) ...<Widget>[
            _PortionUnitPicker(
              units: units,
              chosen: unit,
              onChanged: (PortionUnit picked) {
                // The field is rewritten underneath, so the focus has to go
                // — otherwise the stepper keeps what was typed, and the next
                // unfocus commits that stale number over the conversion.
                FocusScope.of(context).unfocus();
                setState(() {
                  // Pin the basis before the display unit moves. Reading the
                  // same portion in another unit is not a new amount, so it
                  // may change neither the stored portion nor the macros.
                  //
                  // Pinned to the food's own default serving rather than to
                  // whichever unit the field opened in. The stored portion
                  // has always been a count of that serving, and a
                  // remembered raw unit is only how it is shown — pinning
                  // the display unit would let a chip tap on a reopened
                  // planned meal re-cost it through the package
                  // relationship without a keystroke (spec R12, §4).
                  _amountBasis ??= standard == null
                      ? null
                      : PortionUnit.serving(standard);
                  _entryUnit = picked;
                });
                if (food != null) {
                  unawaited(
                    ref
                        .read(preferenceStoreProvider)
                        .write(
                          '${PreferenceStore.logUnitForFood}${food.id}',
                          picked.id,
                        ),
                  );
                }
              },
            ),
            const SizedBox(height: HearthSpacing.md),
          ] else if (standard case final ServingOption only)
            // One serving still needs saying. "1" on its own could be a
            // slice, a loaf or 100 g (§8.2 asks for a labelled amount).
            Padding(
              padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
              child: Text(
                'Serving: ${only.label}',
                style: context.text.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          _PortionStepper(
            servings: count,
            step: unit?.step ?? 0.25,
            basisId: unit?.id,
            format: unit == null ? writeAmount : unit.format,
            onChanged: (double value) => setState(() {
              // Typing or stepping *is* the basis — the one place the unit
              // behind the macros is allowed to change.
              _amountBasis = unit;
              _servings = unit == null
                  ? value
                  : unit.toDefaultServings(
                      value,
                      standard: standard?.amount,
                      food: food,
                    );
            }),
          ),
          // What an amount in grams actually comes to, before it is
          // committed. The stored number is a count of the default serving
          // whatever typed it, so this is the one line that says so.
          if (unit != null && unit.isRaw && standard != null)
            _ResolvedPortion(
              amount: '${unit.format(count)} ${unit.label}',
              servings: _servings,
              serving: standard,
            ),
          const SizedBox(height: HearthSpacing.lg),
          if (!_isExisting) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _assignAcrossDays,
                icon: const Icon(Icons.event_repeat_outlined, size: 18),
                label: const Text('Add to several days'),
              ),
            ),
            const SizedBox(height: HearthSpacing.sm),
          ],
          // Wrapped rather than a Row: three labels side by side stop
          // fitting long before the text is at its largest, and a button
          // pushed off the edge is one nobody can press.
          // Remove hard left, the actions hard right, and onto separate
          // lines rather than off the edge when they stop fitting.
          //
          // A plain Row overflows by 27 points on a 320-point phone at three
          // times the text. A plain Wrap fits, but packs Remove eight points
          // from the button beside it at every size — and Remove deletes a
          // logged meal and its frozen snapshot at once, with no undo on this
          // route, because the restore behind Undo is wired to the swipe.
          // `spaceBetween` keeps the width of the sheet between them while
          // they share a line, and `runSpacing` keeps them apart when they do
          // not.
          if (_isExisting)
            // Side by side while they fit, stacked when they do not — and
            // stacked with the primary *above* Remove, a full gap apart.
            //
            // A Wrap could not do this. `spaceBetween` only separates
            // children that share a run, so once they wrapped it fell back to
            // start-alignment and put the primary directly beneath Remove,
            // twelve points away and flush to the same edge — the adjacency
            // this arrangement exists to prevent, rotated ninety degrees.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowDirection: VerticalDirection.up,
              // The gap is required, not left over. `spaceBetween` only
              // spreads what is spare, so at three times the text on a small
              // phone the two buttons very nearly fill the line and it spread
              // them by five points. Demanding the gap as spacing means they
              // share a line only when it can be honoured, and stack — with
              // the same gap, and the primary above — when it cannot.
              spacing: HearthSpacing.xxxl,
              overflowSpacing: HearthSpacing.xxxl,
              children: <Widget>[
                TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Remove'),
                ),
                _primaryAction(
                  foods: foods,
                  recipes: recipes,
                  update: alreadyLogged,
                  typedIn: unit,
                ),
              ],
            )
          else
            // No destructive button here, so the only question is fitting.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: HearthSpacing.sm,
              overflowSpacing: HearthSpacing.sm,
              children: <Widget>[
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _plan(
                          foods: foods,
                          recipes: recipes,
                          typedIn: unit,
                        ),
                  child: const Text('Plan only'),
                ),
                _primaryAction(
                  foods: foods,
                  recipes: recipes,
                  update: alreadyLogged,
                  typedIn: unit,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pickerView(
    ScrollController controller,
    Map<String, Recipe> recipes,
    Map<String, Food> foods,
  ) {
    final HearthColors colors = context.colors;
    final String needle = _search.text.trim().toLowerCase();
    // Recents are hidden once the user starts searching: they have told us
    // what they are looking for, and a stale shortcut list would just be in
    // the way.
    final List<RecentLog> recents = needle.isEmpty
        ? (ref.watch(recentLogsProvider).value ?? const <RecentLog>[])
        : const <RecentLog>[];

    final List<Recipe> matchingRecipes = recipes.values
        .where(
          (Recipe r) =>
              needle.isEmpty || r.title.toLowerCase().contains(needle),
        )
        .toList(growable: false);
    // `eatableFoods` rather than `foods.values`: a modifier is a deduction,
    // and logging one on its own would make a day read lighter than the day
    // that happened. The unfiltered map stays in use above for *resolving* an
    // entry's macros, where a modifier is a legitimate ingredient of an
    // eaten-out recipe.
    final List<Food> matchingFoods = eatableFoods(foods.values)
        .where(
          (Food f) => needle.isEmpty || f.name.toLowerCase().contains(needle),
        )
        .toList(growable: false);
    final bool nothingLocally =
        matchingRecipes.isEmpty && matchingFoods.isEmpty;

    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Add to this meal', style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.md),
                TextField(
                  controller: _search,
                  // The library filters as you type; the wider search waits
                  // for a pause and lands underneath when it arrives — the
                  // same arrangement the Foods tab uses, so the daily path
                  // never waits on the network.
                  onChanged: (String value) {
                    ref.read(foodSearchProvider.notifier).search(value);
                    setState(() {});
                  },
                  style: context.text.body,
                  decoration: InputDecoration(
                    hintText: 'Search recipes and foods',
                    prefixIcon: Icon(Icons.search, color: colors.textMuted),
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                // The other way in, for the meal that is not in the library
                // yet because you are standing in the queue. Closes the sheet
                // first: the builder ends in the recipe editor, and a sheet
                // left open underneath would be waiting for a choice nobody
                // is going to make.
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: HearthTouch.minTarget,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // The day and the slot travel with it. Three screens
                        // later the editor has no other way to know them, and
                        // recovering them there would recover today's — so a
                        // dinner built for last Tuesday would become tonight's
                        // (spec §5.6, U04).
                        context.push(
                          '/recipe/eat-out',
                          extra: LoggingIntent(
                            date: widget.date,
                            slot: widget.slot,
                            eaten: true,
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                      ),
                      icon: const Icon(Icons.storefront, size: 18),
                      label: const Text('Ate out — build it from a menu'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // One scroll view for both: what the household has, then what the
            // wider sources turned up. Logging used to dead-end at the
            // library — anything not already saved had to be added from the
            // Foods tab and the meal picked up again afterwards, which is
            // three screens for one sandwich.
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                HearthSpacing.lg,
                0,
                HearthSpacing.lg,
                HearthSpacing.xl,
              ),
              children: <Widget>[
                if (recents.isNotEmpty) ...<Widget>[
                  const _GroupLabel(text: 'Recent'),
                  for (final RecentLog recent in recents)
                    _RecentRow(
                      recent: recent,
                      onTap: _busy
                          ? null
                          : () => _logAgain(
                              recent,
                              foods: foods,
                              recipes: recipes,
                            ),
                    ),
                ],
                if (matchingRecipes.isNotEmpty)
                  // "Yours", because the next heading down is "Elsewhere"
                  // and those rows write to the library when one is picked.
                  // The kind alone left the two readable as one list (review
                  // §7's picker scopes).
                  const _GroupLabel(text: 'Your recipes'),
                for (final Recipe recipe in matchingRecipes)
                  _PickRow(
                    title: recipe.title,
                    subtitle:
                        'serves ${recipe.servings == recipe.servings.roundToDouble() ? recipe.servings.round() : recipe.servings}',
                    onTap: () => setState(() => _recipe = recipe),
                  ),
                if (matchingFoods.isNotEmpty)
                  const _GroupLabel(text: 'Your foods'),
                for (final Food food in matchingFoods)
                  _PickRow(
                    title: food.name,
                    subtitle: food.defaultServing == null
                        ? 'no serving size'
                        : '${food.defaultServing!.macros.kcal.round()} kcal '
                              'per ${food.defaultServing!.label}',
                    onTap: () => _choose(food),
                  ),
                // Only ever about what the household already has: results
                // from further afield may well be listed directly underneath,
                // and "nothing matches" above a list of matches reads as a
                // broken screen.
                if (nothingLocally)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: HearthSpacing.xl,
                    ),
                    child: Text(
                      recipes.isEmpty && foods.isEmpty
                          ? 'Nothing saved yet. Search for a food and it can '
                                'be added straight from here.'
                          : 'None of your recipes or foods match.',
                      style: context.text.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Saved to the library first, then logged — the same review
                // every other route into the library goes through
                // (CLAUDE.md rule 4). Nothing reaches a day unchecked.
                ExternalFoodResults(
                  query: _search.text,
                  onSaved: _useSavedFood,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The portion stepper (spec §5.6).
///
/// Quarter steps because half and quarter servings are what actually come up.
/// The number between them is a field, not a label: a third of a batch is
/// three taps of a minus button and a tenth is not reachable at all, and
/// "how much did you eat" is a question with an answer, not a slider.
/// Which unit the portion is typed in (spec §5.6).
///
/// Chips rather than a dropdown: they are all visible at once, they reflow at
/// large text instead of opening a menu over the sheet, and the labels are
/// the food's own words — "170 g pot", "1 tbsp" — rather than a unit the app
/// decided on its behalf.
///
/// The raw units sit at the end of the same row rather than in a control of
/// their own: "how much of it" is one question, and asking it twice — once
/// for the unit, once for the number — is the arithmetic this was meant to
/// remove.
class _PortionUnitPicker extends StatelessWidget {
  const _PortionUnitPicker({
    required this.units,
    required this.chosen,
    required this.onChanged,
  });

  final List<PortionUnit> units;
  final PortionUnit? chosen;
  final ValueChanged<PortionUnit> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'Serving',
        style: context.text.metadata.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      const SizedBox(height: HearthSpacing.xs),
      Wrap(
        spacing: HearthSpacing.sm,
        runSpacing: HearthSpacing.sm,
        children: <Widget>[
          for (final PortionUnit unit in units)
            ChoiceChip(
              label: Text(unit.label),
              selected: unit == chosen,
              onSelected: (bool picked) {
                if (picked) onChanged(unit);
              },
            ),
        ],
      ),
    ],
  );
}

/// What an amount typed in grams comes to, in the food's own serving.
///
/// The number that reaches the row is a count of the default serving whatever
/// typed it, so this is the one line that shows it before it is committed —
/// "125 g = 0.74 × 170 g pot". Rounded to two places: it is here to be read,
/// and the stored value keeps every digit it has.
class _ResolvedPortion extends StatelessWidget {
  const _ResolvedPortion({
    required this.amount,
    required this.servings,
    required this.serving,
  });

  final String amount;
  final double servings;
  final ServingOption serving;

  @override
  Widget build(BuildContext context) {
    final String count = writeAmount((servings * 100).roundToDouble() / 100);
    return Padding(
      padding: const EdgeInsets.only(top: HearthSpacing.xs),
      child: Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          // Spoken as words rather than as an equation: "×" reads as a
          // multiplication sign, which is not how anybody says a portion.
          label: '$amount, which is $count of a ${serving.label}',
          excludeSemantics: true,
          child: Text(
            '$amount = $count × ${serving.label}',
            style: context.text.metadata.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PortionStepper extends StatefulWidget {
  const _PortionStepper({
    required this.servings,
    required this.onChanged,
    this.step = 0.25,
    this.basisId,
    this.format = writeAmount,
  });

  /// How much is being logged, counted in whatever unit [basisId] names.
  final double servings;
  final ValueChanged<double> onChanged;

  /// What the buttons move by. Quarters of a serving, but five grams of a
  /// gram: stepping a weight in quarter-grams is forty taps to cross a
  /// portion, which is not a stepper anybody would press twice.
  final double step;

  /// Which unit the number is in, so a change of unit rewrites the field even
  /// when the number happens to land on the same value.
  final String? basisId;

  /// How the number is written. A count of servings wants `writeAmount`'s
  /// fractions — a third of a batch reads "1/3" — and a weight does not:
  /// 125.5 g wrote itself "125 1/2" until this was a choice.
  final String Function(double) format;

  @override
  State<_PortionStepper> createState() => _PortionStepperState();
}

class _PortionStepperState extends State<_PortionStepper> {
  late final TextEditingController _field = TextEditingController(
    text: widget.format(widget.servings),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Typing over "1" and getting "12" is the classic annoyance, so the
      // whole value is selected on arrival and replaced by the first digit.
      if (_focus.hasFocus) {
        _field.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _field.text.length,
        );
      } else {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(_PortionStepper old) {
    super.didUpdateWidget(old);
    // The buttons change the value from outside, and that has to show. Not
    // while the field has focus, though: rewriting text under a cursor moves
    // it, and half-typed input is not a number to be corrected yet.
    if (!_focus.hasFocus &&
        (widget.servings != old.servings || widget.basisId != old.basisId)) {
      _field.text = widget.format(widget.servings);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Reads what was typed, or puts back what was there.
  ///
  /// A portion of zero is not a smaller portion, it is a deletion — and this
  /// is not the control that deletes things. Anything unreadable reverts
  /// rather than silently logging a number nobody chose.
  void _commit() {
    final double? typed = parseAmount(_field.text);
    // Not finite is not a portion either: "1e999" parses to infinity, and
    // infinity is neither caught by `<= 0` nor anything you can eat.
    if (typed == null || !typed.isFinite || typed <= 0) {
      _field.text = widget.format(widget.servings);
      return;
    }
    _field.text = widget.format(typed);
    if (typed != widget.servings) widget.onChanged(typed);
  }

  void _step(double by) {
    final double next = ((widget.servings + by) * 100).roundToDouble() / 100;
    if (next <= 0) return;
    _focus.unfocus();
    _field.text = widget.format(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Row(
      children: <Widget>[
        Text(
          'Portion',
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const Spacer(),
        IconButton(
          onPressed: widget.servings <= widget.step
              ? null
              : () => _step(-widget.step),
          tooltip: 'Smaller portion',
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 76,
          child: TextField(
            controller: _field,
            focusNode: _focus,
            textAlign: TextAlign.center,
            style: context.text.ingredient.copyWith(fontSize: 20),
            // The full keyboard, filtered — no numeric pad on iOS carries
            // both "." and "/", and a portion is written both ways. Same
            // reasoning as the serving-size field in the food editor.
            keyboardType: TextInputType.text,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(amountCharacters),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _focus.unfocus(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: HearthSpacing.sm,
              ),
              // An underline, so it reads as something you can type in
              // rather than a number that happens to sit between two
              // buttons.
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.outline),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _step(widget.step),
          tooltip: 'Larger portion',
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: HearthSpacing.sm,
      bottom: HearthSpacing.xs,
    ),
    child: Text(
      text,
      style: context.text.metadata.copyWith(color: context.colors.textMuted),
    ),
  );
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        button: true,
        label: '$title. $subtitle',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.text.ingredient),
                  const SizedBox(height: HearthSpacing.xxs),
                  Text(
                    subtitle,
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-tap repeat of something logged recently.
///
/// The whole point is that this is a single tap: no picker, no portion
/// dialog, no confirmation. The portion comes from last time, and it is
/// editable afterwards from the day view like any other entry.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.recent, required this.onTap});

  final RecentLog recent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String portion = recent.servings == recent.servings.roundToDouble()
        ? recent.servings.round().toString()
        : recent.servings.toString();
    final String detail = recent.servings == 1
        ? 'log again · 1 serving'
        : 'log again · $portion servings';

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        button: true,
        label: '${recent.label}. Log again, $detail.',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                children: <Widget>[
                  Icon(Icons.replay, size: 18, color: colors.accent),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(recent.label, style: context.text.ingredient),
                        const SizedBox(height: HearthSpacing.xxs),
                        Text(
                          detail,
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
