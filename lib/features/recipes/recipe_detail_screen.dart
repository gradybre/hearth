import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_scaler.dart';
import 'collections_sheet.dart';
import 'cook_along_screen.dart';
import 'recipe_library_screen.dart';
import 'recipe_photo.dart';
import 'scale_control.dart';
import 'timer_bar.dart';

/// Reading a recipe (spec §5.2).
///
/// In read mode the screen shows ingredients and directions and little else —
/// the reader is ruthlessly focused, because this is what you look at with
/// flour on your hands.
class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final AsyncValue<Recipe?> recipe = ref.watch(recipeByIdProvider(recipeId));

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
            : _RecipeBody(recipe: loaded),
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
                  builder: (BuildContext context) =>
                      CookAlongScreen(recipe: recipe.value!),
                ),
              ),
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: Text('Cook', style: context.text.label),
            ),
    );
  }
}

class _RecipeBody extends StatefulWidget {
  const _RecipeBody({required this.recipe});

  final Recipe recipe;

  @override
  State<_RecipeBody> createState() => _RecipeBodyState();
}

class _RecipeBodyState extends State<_RecipeBody> {
  double? _target;

  /// Scaling is a way of *reading* the recipe, not an edit of it — nothing is
  /// written, and reopening the recipe shows it as written (spec §5.2).
  double get _targetServings => _target ?? widget.recipe.servings;

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
          if (scalable) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            ScaleControl(
              originalServings: original.servings,
              targetServings: _targetServings,
              onChanged: (double value) => setState(() => _target = value),
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
          if (recipe.isGrouped)
            for (final RecipeSection section
                in recipe.orderedSections) ...<Widget>[
              Text(section.name, style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
              for (final RecipeIngredient ingredient in section.ingredients)
                _IngredientRow(ingredient: ingredient),
              if (section.steps.isNotEmpty) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                for (final RecipeStep step in section.orderedSteps)
                  _StepRow(step: step),
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
              for (final RecipeStep step in recipe.allSteps)
                _StepRow(step: step),
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
  const _StepRow({required this.step});

  final RecipeStep step;

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
            child: Text(
              step.text,
              style: text.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
