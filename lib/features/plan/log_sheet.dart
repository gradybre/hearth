import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/foods/eatable_foods.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/recent_log.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/units/quantity.dart';
import '../foods/external_food_results.dart';
import '../foods/food_search_controller.dart';
import 'day_picker_sheet.dart';
import 'entry_resolver.dart';

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

  /// Which of the food's servings the portion is *entered* in (spec §5.6).
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
  /// row. Half a pot is still half a pot to everything downstream.
  ServingOption? _serving;

  /// [_servings], in whatever serving is being entered in.
  double get _displayCount => _inServing(_servings, _serving);

  /// Converts a count of default servings into a count of [option].
  double _inServing(double servings, ServingOption? option) {
    final Quantity? unit = option?.amount;
    final Quantity? standard = _food?.defaultServing?.amount;
    if (unit == null ||
        standard == null ||
        unit.kind != standard.kind ||
        unit.canonicalAmount <= 0) {
      return servings;
    }
    final double converted =
        servings * standard.canonicalAmount / unit.canonicalAmount;
    return converted.isFinite && converted > 0 ? converted : servings;
  }

  /// And back again, which is what actually gets stored.
  double _inDefaultServings(double count, ServingOption? option) {
    final Quantity? unit = option?.amount;
    final Quantity? standard = _food?.defaultServing?.amount;
    if (unit == null ||
        standard == null ||
        unit.kind != standard.kind ||
        standard.canonicalAmount <= 0) {
      return count;
    }
    final double converted =
        count * unit.canonicalAmount / standard.canonicalAmount;
    return converted.isFinite && converted > 0 ? converted : count;
  }

  /// The servings this food can be entered in.
  ///
  /// Only those that can be expressed as a multiple of the default one — the
  /// same kind, so the two are directly comparable. A volume cannot be
  /// written as a multiple of a mass without a density the food does not
  /// carry, and §5.5's rule is that a figure nobody stated is not invented.
  /// An option that cannot be converted is not offered rather than offered
  /// and mis-stored.
  List<ServingOption> get _enterableServings {
    final ServingOption? standard = _food?.defaultServing;
    if (standard == null) return const <ServingOption>[];
    return <ServingOption>[
      for (final ServingOption option in _food!.servingOptions)
        if (option.amount.kind == standard.amount.kind &&
            option.amount.canonicalAmount > 0)
          option,
    ];
  }

  bool _busy = false;

  bool get _isExisting => widget.existing != null;

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
  }) async {
    setState(() => _busy = true);
    try {
      final Macros perServing = _perServing(foods: foods, recipes: recipes);
      final NutrientCoverage coverage = _coverage(
        foods: foods,
        recipes: recipes,
      );

      if (_isExisting) {
        await ref
            .read(planRepositoryProvider)
            .logEntry(
              widget.existing!.entry.id,
              liveMacros: perServing,
              liveCoverage: coverage,
              label: _label,
              portion: _servings,
            );
      } else {
        await ref
            .read(planRepositoryProvider)
            .add(
              date: widget.date,
              slot: widget.slot,
              refType: _recipe != null ? PlanRefType.recipe : PlanRefType.food,
              refId: _recipe?.id ?? _food!.id,
              servings: _servings,
              loggedMacros: perServing,
              loggedCoverage: coverage,
              label: _label,
            );
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
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .add(
            date: widget.date,
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

  /// Logs a recent thing again in one tap, at the portion it was last logged
  /// at (spec §5.6).
  ///
  /// Macros are recomputed from the current library rather than copied from
  /// the old snapshot: repeating a meal should record what that food is now.
  Future<void> _logAgain(
    RecentLog recent, {
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) async {
    setState(() => _busy = true);
    try {
      final Macros perServing = switch (recent.refType) {
        PlanRefType.recipe =>
          recipes[recent.refId] == null
              ? Macros.zero
              : MacroCalculator.forRecipe(
                  recipes[recent.refId]!,
                  foods: foods,
                ).perServing,
        PlanRefType.food =>
          foods[recent.refId]?.defaultServing?.macros ?? Macros.zero,
      };
      // Beside the numbers, from the same source, for the same reason: a
      // recipe's coverage lives in its ingredients and cannot be read back
      // off its total (spec §5.6).
      final NutrientCoverage coverage = switch (recent.refType) {
        PlanRefType.recipe =>
          recipes[recent.refId] == null
              ? const NutrientCoverage.notRecorded()
              : MacroCalculator.forRecipe(
                  recipes[recent.refId]!,
                  foods: foods,
                ).coverage,
        PlanRefType.food => switch (foods[recent.refId]?.defaultServing) {
          final ServingOption serving => NutrientCoverage.ofOne(serving.macros),
          null => const NutrientCoverage.notRecorded(),
        },
      };

      await ref
          .read(planRepositoryProvider)
          .logAgain(
            recent: recent,
            date: widget.date,
            slot: widget.slot,
            liveMacros: perServing,
            liveCoverage: coverage,
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
    setState(() {
      _food = food;
      _serving = food.defaultServing;
    });
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
  }) => FilledButton(
    onPressed: _busy ? null : () => _log(foods: foods, recipes: recipes),
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
          Text(
            alreadyLogged
                ? 'Already logged. Adjust the portion or remove it.'
                : '${total.kcal.round()} kcal · '
                      'P ${total.proteinG.round()}  '
                      'C ${total.carbG.round()}  '
                      'F ${total.fatG.round()}',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: HearthSpacing.lg),
          // Which serving the portion is entered in, before how many of it.
          if (_enterableServings.length > 1) ...<Widget>[
            _ServingPicker(
              options: _enterableServings,
              chosen: _serving ?? _food?.defaultServing,
              onChanged: (ServingOption option) => setState(() {
                // The field is rewritten underneath, so the focus has to go
                // — otherwise the stepper keeps what was typed, and the next
                // unfocus commits that stale number over the conversion.
                FocusScope.of(context).unfocus();
                _serving = option;
              }),
            ),
            const SizedBox(height: HearthSpacing.md),
          ] else if (_food?.defaultServing case final ServingOption only)
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
            servings: _displayCount,
            onChanged: (double value) =>
                setState(() => _servings = _inDefaultServings(value, _serving)),
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
                      : () => _plan(foods: foods, recipes: recipes),
                  child: const Text('Plan only'),
                ),
                _primaryAction(
                  foods: foods,
                  recipes: recipes,
                  update: alreadyLogged,
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
                        context.push('/recipe/eat-out');
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
                  const _GroupLabel(text: 'Recipes'),
                for (final Recipe recipe in matchingRecipes)
                  _PickRow(
                    title: recipe.title,
                    subtitle:
                        'serves ${recipe.servings == recipe.servings.roundToDouble() ? recipe.servings.round() : recipe.servings}',
                    onTap: () => setState(() => _recipe = recipe),
                  ),
                if (matchingFoods.isNotEmpty) const _GroupLabel(text: 'Foods'),
                for (final Food food in matchingFoods)
                  _PickRow(
                    title: food.name,
                    subtitle: food.defaultServing == null
                        ? 'no serving size'
                        : '${food.defaultServing!.macros.kcal.round()} kcal '
                              'per ${food.defaultServing!.label}',
                    onTap: () => setState(() {
                      _food = food;
                      _serving = food.defaultServing;
                    }),
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
/// Which of a food's servings the portion counts (spec §5.6).
///
/// Chips rather than a dropdown: they are all visible at once, they reflow at
/// large text instead of opening a menu over the sheet, and the labels are
/// the food's own words — "170 g pot", "1 tbsp" — rather than a unit the app
/// decided on its behalf.
class _ServingPicker extends StatelessWidget {
  const _ServingPicker({
    required this.options,
    required this.chosen,
    required this.onChanged,
  });

  final List<ServingOption> options;
  final ServingOption? chosen;
  final ValueChanged<ServingOption> onChanged;

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
          for (final ServingOption option in options)
            ChoiceChip(
              label: Text(option.label),
              selected: option.id == chosen?.id,
              onSelected: (bool picked) {
                if (picked) onChanged(option);
              },
            ),
        ],
      ),
    ],
  );
}

class _PortionStepper extends StatefulWidget {
  const _PortionStepper({required this.servings, required this.onChanged});

  final double servings;
  final ValueChanged<double> onChanged;

  static const double _step = 0.25;

  @override
  State<_PortionStepper> createState() => _PortionStepperState();
}

class _PortionStepperState extends State<_PortionStepper> {
  late final TextEditingController _field = TextEditingController(
    text: writeAmount(widget.servings),
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
    if (!_focus.hasFocus && widget.servings != old.servings) {
      _field.text = writeAmount(widget.servings);
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
      _field.text = writeAmount(widget.servings);
      return;
    }
    _field.text = writeAmount(typed);
    if (typed != widget.servings) widget.onChanged(typed);
  }

  void _step(double by) {
    final double next = ((widget.servings + by) * 100).roundToDouble() / 100;
    if (next <= 0) return;
    _focus.unfocus();
    _field.text = writeAmount(next);
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
          onPressed: widget.servings <= _PortionStepper._step
              ? null
              : () => _step(-_PortionStepper._step),
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
          onPressed: () => _step(_PortionStepper._step),
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
