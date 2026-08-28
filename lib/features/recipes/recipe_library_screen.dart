import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/models/recipe.dart';

/// The household's recipe library (spec §5.2).
///
/// Reads from the local cache, so it works with no network. Recipes appear
/// here the moment they are saved, whether or not the sync has caught up.
class RecipeLibraryScreen extends ConsumerWidget {
  const RecipeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recipe>> library = ref.watch(recipeLibraryProvider);
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recipe/new'),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        icon: const Icon(Icons.add),
        label: Text('New recipe', style: context.text.label),
      ),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) =>
              _LibraryError(error: error, gutter: gutter),
          data: (List<Recipe> recipes) => recipes.isEmpty
              ? _EmptyLibrary(gutter: gutter)
              : _RecipeList(recipes: recipes, gutter: gutter),
        ),
      ),
    );
  }
}

class _RecipeList extends StatelessWidget {
  const _RecipeList({required this.recipes, required this.gutter});

  final List<Recipe> recipes;
  final double gutter;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter + 72),
    itemCount: recipes.length + 1,
    separatorBuilder: (BuildContext context, int index) =>
        const SizedBox(height: HearthSpacing.md),
    itemBuilder: (BuildContext context, int index) {
      if (index == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
          child: Text('Recipes', style: context.text.recipeTitle),
        );
      }
      return RecipeCard(recipe: recipes[index - 1]);
    },
  );
}

/// One recipe in the library list.
class RecipeCard extends StatelessWidget {
  const RecipeCard({required this.recipe, super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Semantics(
      button: true,
      label: '${recipe.title}. ${_summary(recipe)}',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: InkWell(
          onTap: () => context.push('/recipe/${recipe.id}'),
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.lg),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(recipe.title, style: text.sectionHeader),
                const SizedBox(height: HearthSpacing.xs),
                Text(
                  _summary(recipe),
                  style: text.metadata.copyWith(color: colors.textMuted),
                ),
                if (recipe.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.md),
                  Wrap(
                    spacing: HearthSpacing.sm,
                    runSpacing: HearthSpacing.xs,
                    children: <Widget>[
                      for (final String tag in recipe.tags) _Tag(label: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summary(Recipe recipe) {
    final List<String> parts = <String>[
      'Serves ${_trimZero(recipe.servings)}',
      if (recipe.totalTime != null) _duration(recipe.totalTime!),
      if (recipe.cuisine != null) recipe.cuisine!,
    ];
    return parts.join('  ·  ');
  }

  static String _trimZero(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  static String _duration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.sm,
          vertical: HearthSpacing.xxs,
        ),
        child: Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// The first-run state. v1 ships no seed recipes, so this is what a new
/// household actually sees (spec §5.8).
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: EdgeInsets.all(gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Your library is empty',
                style: text.sectionHeader,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'Add a recipe by hand to get started. Importing from a photo '
                'or a link comes later.',
                style: text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error, required this.gutter});

  final Object error;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, color: colors.error),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'The recipe library could not be read.',
              style: context.text.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              '$error',
              style: context.text.metadata.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
