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
import 'collections_sheet.dart';
import 'recipe_library_screen.dart';

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
    );
  }
}

class _RecipeBody extends StatelessWidget {
  const _RecipeBody({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter * 2),
        children: <Widget>[
          Text(recipe.title, style: text.recipeTitle),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            _summary(recipe),
            style: text.metadata.copyWith(color: colors.textMuted),
          ),
          if (recipe.notes != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            Text(
              recipe.notes!,
              style: text.body.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: HearthSpacing.xl),
          for (final RecipeSection section
              in recipe.orderedSections) ...<Widget>[
            // A single default section is visually transparent: a simple
            // recipe never has to know sections exist (spec §5.2).
            if (!section.isDefault || recipe.sections.length > 1) ...<Widget>[
              Text(section.name, style: text.sectionHeader),
              const SizedBox(height: HearthSpacing.md),
            ],
            for (final RecipeIngredient ingredient in section.ingredients)
              _IngredientRow(ingredient: ingredient),
          ],
          if (recipe.allSteps.isNotEmpty) ...<Widget>[
            const SizedBox(height: HearthSpacing.xl),
            Text('Directions', style: text.sectionHeader),
            const SizedBox(height: HearthSpacing.md),
            for (final RecipeStep step in recipe.allSteps) _StepRow(step: step),
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
