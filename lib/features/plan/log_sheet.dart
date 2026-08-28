import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/recent_log.dart';
import '../../domain/recipes/macro_calculator.dart';
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
  bool _busy = false;

  bool get _isExisting => widget.existing != null;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Macros _perServing({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) {
    if (widget.existing != null) return widget.existing!.perServing;
    if (_recipe != null) {
      return MacroCalculator.forRecipe(_recipe!, foods: foods).perServing;
    }
    final ServingOption? serving = _food?.defaultServing;
    return serving?.macros ?? Macros.zero;
  }

  String get _label =>
      widget.existing?.label ?? _recipe?.title ?? _food?.name ?? '';

  Future<void> _log({
    required Map<String, Food> foods,
    required Map<String, Recipe> recipes,
  }) async {
    setState(() => _busy = true);
    try {
      final Macros perServing = _perServing(foods: foods, recipes: recipes);

      if (_isExisting) {
        await ref
            .read(planRepositoryProvider)
            .logEntry(
              widget.existing!.entry.id,
              liveMacros: perServing,
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

      await ref
          .read(planRepositoryProvider)
          .logAgain(
            recent: recent,
            date: widget.date,
            slot: widget.slot,
            liveMacros: perServing,
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
                  ? _confirmView(perServing, foods, recipes)
                  : _pickerView(controller, recipes, foods),
            ),
      ),
    );
  }

  Widget _confirmView(
    Macros perServing,
    Map<String, Food> foods,
    Map<String, Recipe> recipes,
  ) {
    final HearthColors colors = context.colors;
    final Macros total = perServing.scaledBy(_servings);
    final bool alreadyLogged = widget.existing?.entry.isLogged ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            _PortionStepper(
              servings: _servings,
              onChanged: (double value) => setState(() => _servings = value),
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
            Row(
              children: <Widget>[
                if (_isExisting)
                  TextButton(
                    onPressed: _busy ? null : _remove,
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                if (!_isExisting)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _plan(foods: foods, recipes: recipes),
                    child: const Text('Plan only'),
                  ),
                const SizedBox(width: HearthSpacing.sm),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _log(foods: foods, recipes: recipes),
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : alreadyLogged
                        ? 'Update'
                        : 'Log it',
                  ),
                ),
              ],
            ),
          ],
        ),
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
    final List<Food> matchingFoods = foods.values
        .where(
          (Food f) => needle.isEmpty || f.name.toLowerCase().contains(needle),
        )
        .toList(growable: false);

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
                  onChanged: (_) => setState(() {}),
                  style: context.text.body,
                  decoration: InputDecoration(
                    hintText: 'Search recipes and foods',
                    prefixIcon: Icon(Icons.search, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: matchingRecipes.isEmpty && matchingFoods.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(HearthSpacing.xl),
                      child: Text(
                        recipes.isEmpty && foods.isEmpty
                            ? 'Add a recipe or a food first, then it can be '
                                  'logged here.'
                            : 'Nothing matches that search.',
                        style: context.text.body,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
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
                      if (matchingFoods.isNotEmpty)
                        const _GroupLabel(text: 'Foods'),
                      for (final Food food in matchingFoods)
                        _PickRow(
                          title: food.name,
                          subtitle: food.defaultServing == null
                              ? 'no serving size'
                              : '${food.defaultServing!.macros.kcal.round()} kcal '
                                    'per ${food.defaultServing!.label}',
                          onTap: () => setState(() => _food = food),
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
/// Quarter steps because half and quarter servings are what actually come up;
/// finer than that is false precision on a plate.
class _PortionStepper extends StatelessWidget {
  const _PortionStepper({required this.servings, required this.onChanged});

  final double servings;
  final ValueChanged<double> onChanged;

  static const double _step = 0.25;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String label = servings == servings.roundToDouble()
        ? servings.round().toString()
        : servings.toString();

    return Row(
      children: <Widget>[
        Text(
          'Portion',
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const Spacer(),
        IconButton(
          onPressed: servings <= _step
              ? null
              : () =>
                    onChanged(((servings - _step) * 100).roundToDouble() / 100),
          tooltip: 'Smaller portion',
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 64,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.text.ingredient.copyWith(fontSize: 20),
          ),
        ),
        IconButton(
          onPressed: () =>
              onChanged(((servings + _step) * 100).roundToDouble() / 100),
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
