import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/ingredient_consolidator.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/recipes/recipe_scaler.dart';
import 'collections_sheet.dart';
import 'cook_along_screen.dart';
import 'macro_stats_row.dart';
import 'recipe_library_screen.dart';
import 'recipe_photo.dart';
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

  @override
  Widget build(BuildContext context) {
    final String recipeId = widget.recipeId;
    final HearthColors colors = context.colors;
    final AsyncValue<Recipe?> recipe = ref.watch(recipeByIdProvider(recipeId));
    final Map<String, Food> foods = <String, Food>{
      for (final Food food
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: const SizedBox.shrink(),
        actions: <Widget>[
          FavoriteButton(recipeId: recipeId),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Cookbooks',
            onPressed: () => showCollectionsSheet(context, recipeId: recipeId),
          ),
          TextButton(
            onPressed: () => context.push('/recipe/$recipeId/edit'),
            child: const Text('Edit'),
          ),
          const SizedBox(width: HearthSpacing.sm),
        ],
      ),
      body: recipe.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text('Could not open that recipe.\n$error')),
        data: (Recipe? loaded) => loaded == null
            ? const Center(child: Text('That recipe no longer exists.'))
            : _RecipeBody(
                recipe: loaded,
                foods: foods,
                target: _target,
                onScaled: (double? value) => setState(() => _target = value),
              ),
      ),
      // The recipe screen is pushed above the shell, so it does not get the
      // shell's timer bar. Without this, opening a recipe mid-cook is the one
      // place a running timer would drop out of sight.
      bottomNavigationBar: const CookTimerBar(),
      floatingActionButton: recipe.value == null
          ? null
          : recipe.value!.allSteps.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  // The recipe is handed over by value: cook-along runs off a
                  // snapshot, so a partner's mid-cook edit cannot move the
                  // step under your hands (spec §5.2).
                  //
                  // And scaled, because what is on screen is what the cook
                  // means to make.
                  builder: (BuildContext context) =>
                      CookAlongScreen(recipe: _scaled(recipe.value!)),
                ),
              ),
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: Text('Cook', style: context.text.label),
            ),
    );
  }

  /// The recipe as the reader has it, scaled or not.
  ///
  /// A recipe with no yield cannot be scaled to one, and `RecipeScaler` says
  /// so by throwing — so the guard here is the same one the body applies
  /// before offering the control at all.
  Recipe _scaled(Recipe recipe) {
    final double? target = _target;
    if (target == null || recipe.servings <= 0) return recipe;
    return RecipeScaler.toServings(recipe, target).recipe;
  }
}

class _RecipeBody extends StatefulWidget {
  const _RecipeBody({
    required this.recipe,
    required this.foods,
    required this.target,
    required this.onScaled,
  });

  final Recipe recipe;
  final Map<String, Food> foods;

  /// The yield the reader has scaled to, owned by the screen so the Cook
  /// button can see it too.
  final double? target;
  final ValueChanged<double?> onScaled;

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
    // so by throwing. Offer the control only where it means something.
    final bool scalable = original.servings > 0;
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
          Text(original.title, style: text.recipeTitle),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            _summary(original),
            style: text.metadata.copyWith(color: colors.textMuted),
          ),
          if (original.notes != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            Text(
              original.notes!,
              style: text.body.copyWith(color: colors.textSecondary),
            ),
          ],
          if (recipe.allIngredients.isNotEmpty) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            Text('Nutrition per serving', style: text.sectionHeader),
            const SizedBox(height: HearthSpacing.sm),
            MacroStatsRow(macros: macros.perServing),
            // Quiet, below the four, and absent entirely when nothing here
            // knows them — which is most recipes (spec §5.6).
            if (macros.perServing.knowsAnyMinor) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              MinorNutrientsLine(
                macros: macros.perServing,
                partialFor: macros.partialNoteFor,
              ),
            ],
            // Missing data flags, never blocks (spec §5.3): shown alongside
            // the numbers rather than hiding them, so what is known is never
            // held back for want of what isn't — and naming the actual gap,
            // because "not matched" sent people to re-match ingredients that
            // were already matched and were never the problem.
            if (macros.incompleteReason case final String reason) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              Text(
                reason,
                style: text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
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
                ))
              _CombinedRow(line: line),
            const SizedBox(height: HearthSpacing.xl),
            // Method stays grouped either way. The sections are how the
            // cooking reads — and cook-along depends on a step knowing which
            // section's amounts it is talking about.
            for (final RecipeSection section in recipe.orderedSections)
              if (section.steps.isNotEmpty) ...<Widget>[
                Text(section.name, style: text.sectionHeader),
                const SizedBox(height: HearthSpacing.md),
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(step: step, section: section, recipe: recipe),
                const SizedBox(height: HearthSpacing.xl),
              ],
          ] else if (recipe.isGrouped)
            for (final RecipeSection section
                in recipe.orderedSections) ...<Widget>[
              Text(section.name, style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
              for (final RecipeIngredient ingredient in section.ingredients)
                _IngredientRow(ingredient: ingredient),
              if (section.steps.isNotEmpty) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(step: step, section: section, recipe: recipe),
              ],
              const SizedBox(height: HearthSpacing.xl),
            ]
          else ...<Widget>[
            for (final RecipeIngredient ingredient in recipe.allIngredients)
              _IngredientRow(ingredient: ingredient),
            if (recipe.allSteps.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.xl),
              Text('Directions', style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
              // Walked per section even here: an ungrouped recipe has exactly
              // one, and a step needs to know which one it belongs to before
              // it can say how much of anything it uses.
              for (final RecipeSection section in recipe.orderedSections)
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(step: step, section: section, recipe: recipe),
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
      'Serves ${recipe.servings == recipe.servings.roundToDouble() ? recipe.servings.round() : recipe.servings}',
      if (recipe.prepTime != null) '${recipe.prepTime!.inMinutes} min prep',
      if (recipe.cookTime != null) '${recipe.cookTime!.inMinutes} min cook',
      if (recipe.cuisine != null) recipe.cuisine!,
    ];
    return parts.join('  ·  ');
  }
}

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
  const _CombinedRow({required this.line});

  final ConsolidatedIngredient line;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              line.quantities.map(QuantityFormat.format).join(' + '),
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
  const _IngredientRow({required this.ingredient});

  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

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
                  : QuantityFormat.format(ingredient.quantity!),
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
  });

  final RecipeStep step;
  final RecipeSection section;

  /// Carried so a step can still find an ingredient an import filed under a
  /// different heading — see [StepAmounts.recipe].
  final Recipe recipe;

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
                StepAmounts(step: step, section: section, recipe: recipe),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
