import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/undo_snackbar.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/repositories/shopping_repository.dart';
import '../../domain/format/food_quantity_format.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/recipes/ingredient_consolidator.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/recipes/recipe_scaler.dart';
import '../../domain/units/quantity.dart';
import '../shopping/add_to_list_sheet.dart';
import 'collections_sheet.dart';
import 'cook_along_screen.dart';
import 'recipe_draft.dart';
import 'recipe_icon.dart';
import 'recipe_nutrition_receipt.dart';
import 'recipe_photo.dart';
import 'recipe_plan_sheet.dart';
import 'scale_control.dart';
import 'step_amounts.dart';
import 'timer_bar.dart';

/// Reading a recipe (spec §5.2).
///
/// In read mode the screen shows ingredients and directions and little else —
/// the reader is ruthlessly focused, because this is what you look at with
/// flour on your hands.
class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  /// Held here rather than in the body, because the Cook button is not in the
  /// body.
  ///
  /// It used to live in `_RecipeBodyState`, one level below the Scaffold's
  /// floatingActionButton — so scaling a recipe to 2x and tapping Cook handed
  /// cook-along the recipe as written. Brendan doubled a turkey bowl, saw
  /// 2 lb on the page, and was told to brown 1 lb. Scaling is a way of
  /// reading a recipe (§5.2), and cooking is reading it.
  double? _target;
  bool _actionBusy = false;

  @override
  Widget build(BuildContext context) {
    final String recipeId = widget.recipeId;
    final HearthColors colors = context.colors;
    final AsyncValue<Recipe?> recipe = ref.watch(recipeByIdProvider(recipeId));
    final Recipe? available = _availableFrom(recipe);
    final bool isFavorite =
        (ref.watch(favoriteRecipeIdsProvider).value ?? const <String>{})
            .contains(recipeId);
    final Map<String, Food> foods = <String, Food>{
      for (final Food food
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };

    // Large controls belong to the scrolling page on a short phone. Keeping
    // a three-row footer would leave almost no recipe to read at 3x text.
    final bool actionsInBody = MediaQuery.textScalerOf(context).scale(14) > 21;
    Widget actions(Recipe original) => _RecipeActions(
      busy: _actionBusy,
      eatenOut: original.isEatenOut,
      onCook: original.allSteps.isEmpty ? null : () => _cook(original),
      onPlan: () => _plan(original),
      onShop: () => _shop(original, foods),
      stacked: actionsInBody,
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: const SizedBox.shrink(),
        actions: <Widget>[
          if (available != null) ...<Widget>[
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? colors.accent : colors.textMuted,
              ),
              tooltip: isFavorite
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              onPressed: () {
                if (_currentRecipe == null) return;
                ref.read(collectionRepositoryProvider).toggleFavorite(recipeId);
              },
            ),
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Cookbooks',
              onPressed: () {
                if (_currentRecipe == null) return;
                showCollectionsSheet(context, recipeId: recipeId);
              },
            ),
            // "My usual bowl, but no rice" is a different meal, not an edit.
            // Opens the copy unsaved, so the rename and the change happen
            // before anything is written (spec §5.2).
            IconButton(
              icon: const Icon(Icons.content_copy_outlined),
              tooltip: 'Duplicate this recipe',
              onPressed: () {
                final Recipe? current = _currentRecipe;
                if (current == null) return;
                context.push(
                  '/recipe/new',
                  extra: RecipeDraft.fromRecipe(current).asCopy(),
                );
              },
            ),
            TextButton(
              onPressed: () {
                if (_currentRecipe != null) {
                  context.push('/recipe/$recipeId/edit');
                }
              },
              child: const Text('Edit'),
            ),
            const SizedBox(width: HearthSpacing.sm),
          ],
        ],
      ),
      body: recipe.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading recipe'),
        ),
        error: (Object error, StackTrace stack) => _RecipeUnavailable(
          failed: true,
          onRetry: () => ref.invalidate(recipeByIdProvider(recipeId)),
        ),
        data: (Recipe? loaded) => loaded == null || loaded.isDeleted
            ? const _RecipeUnavailable()
            : _RecipeBody(
                recipe: loaded,
                foods: foods,
                target: _target,
                onScaled: (double? value) => setState(() => _target = value),
                actions: actionsInBody ? actions(loaded) : null,
              ),
      ),
      // The recipe screen is pushed above the shell, so it does not get the
      // shell's timer bar. Without this, opening a recipe mid-cook is the one
      // place a running timer would drop out of sight.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!actionsInBody && available != null)
            ColoredBox(
              color: colors.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(HearthSpacing.sm),
                  child: actions(available),
                ),
              ),
            ),
          const CookTimerBar(),
        ],
      ),
    );
  }

  static Recipe? _availableFrom(AsyncValue<Recipe?> value) {
    if (value.isLoading || value.hasError) return null;
    final Recipe? loaded = value.value;
    return loaded == null || loaded.isDeleted ? null : loaded;
  }

  /// A callback can outlive the frame that supplied it. Recheck the current
  /// record before opening any action from a now-unavailable recipe.
  Recipe? get _currentRecipe => mounted
      ? _availableFrom(ref.read(recipeByIdProvider(widget.recipeId)))
      : null;

  /// The recipe as the reader has it, scaled or not.
  ///
  /// A recipe with no yield cannot be scaled to one, and `RecipeScaler` says
  /// so by throwing — so the guard here is the same one the body applies
  /// before offering the control at all.
  Recipe _scaled(Recipe recipe) {
    final double? target = _target;
    if (target == null ||
        !target.isFinite ||
        !recipe.servings.isFinite ||
        recipe.servings <= 0) {
      return recipe;
    }
    return RecipeScaler.toServings(recipe, target).recipe;
  }

  void _cook(Recipe original) {
    if (_actionBusy || original.isEatenOut || _currentRecipe == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        // A scaled value snapshot: changes on another device cannot change
        // the recipe halfway through cooking it.
        builder: (BuildContext context) =>
            CookAlongScreen(recipe: _scaled(original)),
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    _setActionBusy(true);
    try {
      await action();
    } finally {
      _setActionBusy(false);
    }
  }

  void _setActionBusy(bool value) {
    // The app's snackbar can remain visible after this route is popped.
    // Its reviewed Undo/Retry still works, but there is no page to rebuild.
    if (mounted) {
      setState(() => _actionBusy = value);
    } else {
      _actionBusy = value;
    }
  }

  Future<void> _plan(Recipe original) async {
    if (_actionBusy || _currentRecipe == null) return;
    final PlanRepository plans = ref.read(planRepositoryProvider);
    final _ActionFeedback feedback = _ActionFeedback(context);
    await _runAction(() async {
      final RecipePlanSelection? selection = await showRecipePlanSheet(
        context,
        recipe: original,
      );
      if (selection != null) {
        await _savePlan(plans, feedback, original, selection);
      }
    });
  }

  Future<void> _savePlan(
    PlanRepository plans,
    _ActionFeedback feedback,
    Recipe original,
    RecipePlanSelection selection,
  ) async {
    if (!feedback.requireCurrent()) return;
    try {
      if (!await feedback.requireAvailableRecipe(original.id)) return;
      final MealPlanEntry added = await plans.add(
        date: selection.date,
        slot: selection.slot,
        refType: PlanRefType.recipe,
        refId: original.id,
        servings: selection.servings,
        // No logged macros: planning is never a claim that this was eaten.
      );
      if (!feedback.isCurrent) return;
      feedback.refreshPlan();
      showUndoSnackBar(
        feedback.messenger,
        stackedAction: true,
        message:
            'Added to My plan · ${selection.slot.label} · '
            '${feedback.localizations.formatMediumDate(selection.date)}',
        onUndo: () => _undoPlan(plans, feedback, added.id),
      );
    } on Object {
      feedback.show(
        'Could not add to My plan. Your choices are kept for retry.',
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () =>
              _runAction(() => _savePlan(plans, feedback, original, selection)),
        ),
      );
    }
  }

  Future<void> _undoPlan(
    PlanRepository plans,
    _ActionFeedback feedback,
    String entryId,
  ) => _runAction(() async {
    if (!feedback.requireCurrent()) return;
    try {
      // Only the new entry's id. Another portion of this same recipe is a
      // separate decision and must survive this Undo.
      await plans.removeEntry(entryId);
      feedback.refreshPlan();
      feedback.show('Removed from My plan.');
    } on Object {
      feedback.show(
        'Could not undo that plan addition.',
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _undoPlan(plans, feedback, entryId),
        ),
      );
    }
  });

  Future<void> _shop(Recipe original, Map<String, Food> foods) async {
    if (_actionBusy || original.isEatenOut || _currentRecipe == null) return;
    final ShoppingRepository shopping = ref.read(shoppingRepositoryProvider);
    final _ActionFeedback feedback = _ActionFeedback(context);
    await _runAction(() async {
      final ListAddition? addition = await showAddToListSheet(
        context,
        recipes: <Recipe>[original],
        foods: foods.values.toList(growable: false),
        recipe: original,
        servings: _target ?? original.servings,
      );
      if (addition is RecipeAddition) {
        await _saveShopping(shopping, feedback, addition, foods);
      }
    });
  }

  Future<void> _saveShopping(
    ShoppingRepository shopping,
    _ActionFeedback feedback,
    RecipeAddition addition,
    Map<String, Food> foods,
  ) async {
    if (!feedback.requireCurrent()) return;
    final String? issue = recipeShoppingIssue(
      addition.recipe,
      servings: addition.servings,
    );
    if (issue != null) {
      feedback.show(issue);
      return;
    }
    try {
      if (!await feedback.requireAvailableRecipe(addition.recipe.id)) return;
      await shopping.addRecipe(
        recipe: addition.recipe,
        servings: addition.servings,
        foods: foods,
      );
      if (!feedback.isCurrent) return;
      feedback.container.invalidate(shoppingListProvider);
      feedback.show(
        'Ingredients added to our shopping list.',
        action: SnackBarAction(
          label: 'View list',
          onPressed: () {
            if (feedback.requireCurrent()) feedback.router.go('/shopping');
          },
        ),
      );
    } on Object {
      feedback.show(
        'Could not add ingredients. Your amount is kept for retry.',
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _runAction(
            () => _saveShopping(shopping, feedback, addition, foods),
          ),
        ),
      );
    }
  }
}

/// App-level feedback outlives the detail route while its Undo/Retry is visible.
/// No callback keeps using a disposed route's context or WidgetRef.
class _ActionFeedback {
  _ActionFeedback(BuildContext context)
    : messenger = ScaffoldMessenger.of(context),
      container = ProviderScope.containerOf(context, listen: false),
      router = GoRouter.of(context),
      localizations = MaterialLocalizations.of(context) {
    _userId = container.read(currentUserIdProvider);
    _householdId = container.read(currentHouseholdIdProvider);
  }

  final ScaffoldMessengerState messenger;
  final ProviderContainer container;
  final GoRouter router;
  final MaterialLocalizations localizations;
  late final String _userId;
  late final String _householdId;

  bool get isCurrent =>
      messenger.mounted &&
      container.read(currentUserIdProvider) == _userId &&
      container.read(currentHouseholdIdProvider) == _householdId;

  bool requireCurrent() {
    if (isCurrent) return true;
    // SnackBarAction dismisses its bar after invoking the callback. With
    // accessible navigation that dismissal is immediate, so wait until it
    // finishes before presenting the explanation for this expired action.
    Future<void>.microtask(
      () => _show(
        'Your account or household changed. Open the recipe and try again.',
      ),
    );
    return false;
  }

  /// Review sheets and their Retry can outlive a library update or this route.
  /// Check availability without replacing the recipe/yield the person reviewed.
  Future<bool> requireAvailableRecipe(String recipeId) async {
    if (!requireCurrent()) return false;
    final Recipe? current = await container.read(
      recipeByIdProvider(recipeId).future,
    );
    if (!requireCurrent()) return false;
    if (current != null && !current.isDeleted) return true;
    show('This recipe is no longer available. Nothing was added.');
    return false;
  }

  void refreshPlan() {
    if (!isCurrent) return;
    container.invalidate(dayEntriesProvider);
    container.invalidate(weekEntriesProvider);
  }

  void show(String message, {SnackBarAction? action}) {
    if (!isCurrent) return;
    _show(message, action: action);
  }

  void _show(String message, {SnackBarAction? action}) {
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: action == null
              ? Text(message)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(message),
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                ),
          // The action lives below the message to keep its full width.
          // Keep the same persistence as a native SnackBar.action.
          persist: action != null,
        ),
      );
  }
}

class _RecipeUnavailable extends StatelessWidget {
  const _RecipeUnavailable({this.failed = false, this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: CentredMessage(
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            failed ? 'Could not open this recipe' : 'Recipe unavailable',
            style: context.text.sectionHeader,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          failed
              ? 'Try loading it again.'
              : 'This recipe is no longer available in the library. '
                    'Your plan and saved logs have not changed.',
          style: context.text.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.lg),
        if (onRetry != null) ...<Widget>[
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          const SizedBox(height: HearthSpacing.sm),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Go back'),
        ),
      ],
    ),
  );
}

class _RecipeActions extends StatelessWidget {
  const _RecipeActions({
    required this.busy,
    required this.eatenOut,
    required this.onCook,
    required this.onPlan,
    required this.onShop,
    required this.stacked,
  });

  final bool busy;
  final bool eatenOut;
  final VoidCallback? onCook;
  final VoidCallback onPlan;
  final VoidCallback onShop;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = FilledButton.styleFrom(
      minimumSize: const Size(0, HearthTouch.minTarget),
    );
    final List<Widget> buttons = <Widget>[
      if (!eatenOut && onCook != null)
        FilledButton.icon(
          style: style,
          onPressed: busy ? null : onCook,
          icon: const Icon(Icons.soup_kitchen_outlined),
          label: const Text('Cook'),
        ),
      OutlinedButton.icon(
        style: style,
        onPressed: busy ? null : onPlan,
        icon: const Icon(Icons.event_outlined),
        label: const Text('Plan'),
      ),
      if (!eatenOut)
        OutlinedButton.icon(
          style: style,
          onPressed: busy ? null : onShop,
          icon: const Icon(Icons.shopping_basket_outlined),
          label: const Text('Shop'),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (stacked)
          for (int i = 0; i < buttons.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: HearthSpacing.sm),
            buttons[i],
          ]
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: HearthSpacing.sm,
            runSpacing: HearthSpacing.sm,
            children: buttons,
          ),
        if (busy) ...<Widget>[
          const SizedBox(height: HearthSpacing.xs),
          const LinearProgressIndicator(
            semanticsLabel: 'Saving your selection',
          ),
        ],
      ],
    );
  }
}

class _RecipeBody extends StatefulWidget {
  const _RecipeBody({
    required this.recipe,
    required this.foods,
    required this.target,
    required this.onScaled,
    this.actions,
  });

  final Recipe recipe;
  final Map<String, Food> foods;

  /// The yield the reader has scaled to, owned by the screen so the Cook
  /// button can see it too.
  final double? target;
  final ValueChanged<double?> onScaled;
  final Widget? actions;

  @override
  State<_RecipeBody> createState() => _RecipeBodyState();
}

class _RecipeBodyState extends State<_RecipeBody> {
  /// Whether the ingredients are shown summed rather than by section.
  ///
  /// The same kind of state as [_target], and for the same reason: scaling and
  /// combining are both ways of *reading* the recipe, not edits of it —
  /// nothing is written, and reopening shows it as written (spec §5.2).
  bool _combined = false;
  bool _wholeDish = false;

  double get _targetServings => widget.target ?? widget.recipe.servings;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    final Recipe original = widget.recipe;
    // A recipe with no yield cannot be scaled to a yield, and the scaler says
    // so by throwing. Offer the control only where it means something — which
    // a restaurant meal never is: you cannot make the burrito bowl bigger by
    // wanting to, and doubling one would silently double its macros against a
    // portion nobody served (spec §5.2).
    final bool scalable =
        original.servings.isFinite &&
        original.servings > 0 &&
        !original.isEatenOut;
    final ScaledRecipe? scaled = scalable
        ? RecipeScaler.toServings(original, _targetServings)
        : null;
    final Recipe recipe = scaled?.recipe ?? original;
    final RecipeMacros macros = MacroCalculator.forRecipe(
      recipe,
      foods: widget.foods,
    );

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter * 2),
        children: <Widget>[
          const SizedBox(height: HearthSpacing.sm),
          RecipePhoto(
            recipeId: original.id,
            width: double.infinity,
            height: 220,
          ),
          // Beside the title rather than above it. Here the sketch is a mark
          // on the page, not a hero image — the photo slot above already is
          // one — so unlike in the library the two do not compete and both
          // can show.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (RecipeIcon.canDraw(original.iconSvg)) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: HearthSpacing.xs),
                  child: RecipeIcon(svg: original.iconSvg, size: 36),
                ),
                const SizedBox(width: HearthSpacing.md),
              ],
              Expanded(child: Text(original.title, style: text.recipeTitle)),
            ],
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            _summary(recipe),
            style: text.metadata.copyWith(color: colors.textMuted),
          ),
          if (widget.actions != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            widget.actions!,
          ],
          if (original.notes != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            Text(
              original.notes!,
              style: text.body.copyWith(color: colors.textSecondary),
            ),
          ],
          if (recipe.allIngredients.isNotEmpty) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            RecipeNutritionSummary(
              recipe: recipe,
              macros: macros,
              wholeDish: _wholeDish,
              authoredRecipe: original,
              foods: widget.foods,
              onChanged: (bool value) => setState(() => _wholeDish = value),
            ),
          ],
          if (scalable) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            ScaleControl(
              originalServings: original.servings,
              targetServings: _targetServings,
              onChanged: widget.onScaled,
            ),
          ],
          const SizedBox(height: HearthSpacing.xl),
          // A grouped recipe reads the way a cookbook writes one: each group
          // carries its own ingredients *and* its own method, rather than a
          // grouped shopping list followed by an undifferentiated wall of
          // steps (spec §5.2).
          //
          // An ungrouped recipe is unchanged — ingredients, then Directions —
          // because a single default section is visually transparent and must
          // never make a simple recipe look organised.
          // Only where there is something to combine. A recipe with one
          // section would offer a choice between a list and the same list.
          if (recipe.isGrouped) ...<Widget>[
            _IngredientView(
              combined: _combined,
              onChanged: (bool value) => setState(() => _combined = value),
            ),
            const SizedBox(height: HearthSpacing.lg),
          ],
          if (recipe.isGrouped && _combined) ...<Widget>[
            Text('Ingredients', style: text.sectionHeader),
            const SizedBox(height: HearthSpacing.md),
            // Optional lines included, unlike the shopping list and the macro
            // total: a cook reading the list still has to see the chilli they
            // may or may not add.
            for (final ConsolidatedIngredient line
                in IngredientConsolidator.flatten(
                  recipe,
                  includeOptional: true,
                  foods: widget.foods,
                ))
              _CombinedRow(line: line, foods: widget.foods),
            const SizedBox(height: HearthSpacing.xl),
            // Method stays grouped either way. The sections are how the
            // cooking reads — and cook-along depends on a step knowing which
            // section's amounts it is talking about.
            for (final RecipeSection section in recipe.orderedSections)
              if (section.steps.isNotEmpty) ...<Widget>[
                Text(section.name, style: text.sectionHeader),
                const SizedBox(height: HearthSpacing.md),
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(
                    step: step,
                    section: section,
                    recipe: recipe,
                    foods: widget.foods,
                  ),
                const SizedBox(height: HearthSpacing.xl),
              ],
          ] else if (recipe.isGrouped)
            for (final RecipeSection section
                in recipe.orderedSections) ...<Widget>[
              Text(section.name, style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
              for (final RecipeIngredient ingredient in section.ingredients)
                _IngredientRow(ingredient: ingredient, foods: widget.foods),
              if (section.steps.isNotEmpty) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(
                    step: step,
                    section: section,
                    recipe: recipe,
                    foods: widget.foods,
                  ),
              ],
              const SizedBox(height: HearthSpacing.xl),
            ]
          else ...<Widget>[
            for (final RecipeIngredient ingredient in recipe.allIngredients)
              _IngredientRow(ingredient: ingredient, foods: widget.foods),
            if (recipe.allSteps.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.xl),
              Text('Directions', style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
              // Walked per section even here: an ungrouped recipe has exactly
              // one, and a step needs to know which one it belongs to before
              // it can say how much of anything it uses.
              for (final RecipeSection section in recipe.orderedSections)
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(
                    step: step,
                    section: section,
                    recipe: recipe,
                    foods: widget.foods,
                  ),
            ],
          ],
          if (scaled != null && scaled.hasWarnings) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            ScalingNotes(warnings: scaled.warnings),
          ],
        ],
      ),
    );
  }

  static String _summary(Recipe recipe) {
    final List<String> parts = <String>[
      recipe.servings.isFinite && recipe.servings > 0
          ? 'Serves ${_number(recipe.servings)}'
          : 'Yield not set',
      if (recipe.prepTime != null) '${recipe.prepTime!.inMinutes} min prep',
      if (recipe.cookTime != null) '${recipe.cookTime!.inMinutes} min cook',
      if (recipe.cuisine != null) recipe.cuisine!,
    ];
    return parts.join('  ·  ');
  }
}

String _number(double value) => QuantityFormat.count(value);

/// How the ingredients are being read: as the recipe groups them, or summed.
class _IngredientView extends StatelessWidget {
  const _IngredientView({required this.combined, required this.onChanged});

  final bool combined;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(value: false, label: Text('By section')),
        ButtonSegment<bool>(value: true, label: Text('Combined')),
      ],
      selected: <bool>{combined},
      showSelectedIcon: false,
      onSelectionChanged: (Set<bool> selected) => onChanged(selected.first),
    );
  }
}

/// One ingredient with every section's share of it added up.
///
/// Usually one amount. More than one when the same thing was written in units
/// that cannot be reconciled — 2 tbsp of butter in the sauce and 50 g in the
/// dough with no density known — and §5.7 is explicit that both are then shown
/// rather than guessed at.
class _CombinedRow extends StatelessWidget {
  const _CombinedRow({required this.line, this.foods});

  final ConsolidatedIngredient line;

  /// The household's food library, keyed by id — one snapshot from the
  /// screen, so each row's matched-food display preference (spec R1–R8) is
  /// resolved without a per-row lookup.
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final Food? food = line.foodId == null ? null : foods?[line.foodId];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              line.quantities
                  .map((Quantity q) => FoodQuantityFormat.format(q, food: food))
                  .join(' + '),
              style: text.ingredient,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: line.displayName, style: text.ingredient),
                  // The total understates what the recipe needs, and saying so
                  // is the difference between a number and a wrong number.
                  if (line.hasUnquantified)
                    TextSpan(
                      text: '  plus some to taste',
                      style: text.metadata.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, this.foods});

  final RecipeIngredient ingredient;

  /// The household's food library, keyed by id — see [_CombinedRow.foods].
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final Food? food = ingredient.foodId == null
        ? null
        : foods?[ingredient.foodId];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A fixed column so quantities line up down the list — what the
          // tabular figures in the type scale are for.
          SizedBox(
            width: 92,
            child: Text(
              ingredient.quantity == null
                  ? ''
                  : FoodQuantityFormat.format(
                      ingredient.quantity!,
                      food: food,
                      rawSources: [ingredient.rawText ?? ''],
                    ),
              style: text.ingredient,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: ingredient.name, style: text.ingredient),
                  if (ingredient.prepNote != null)
                    TextSpan(
                      text: ', ${ingredient.prepNote}',
                      style: text.ingredient.copyWith(color: colors.textMuted),
                    ),
                  if (ingredient.isOptional)
                    TextSpan(
                      text: '  optional',
                      style: text.metadata.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.section,
    required this.recipe,
    this.foods,
  });

  final RecipeStep step;
  final RecipeSection section;

  /// Carried so a step can still find an ingredient an import filed under a
  /// different heading — see [StepAmounts.recipe].
  final Recipe recipe;

  /// The household's food library, keyed by id — see [_CombinedRow.foods].
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '${step.stepNumber}.',
              style: text.ingredient.copyWith(color: colors.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.text,
                  style: text.body.copyWith(color: colors.textSecondary),
                ),
                StepAmounts(
                  step: step,
                  section: section,
                  recipe: recipe,
                  foods: foods,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
