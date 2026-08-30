import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_query.dart';
import 'recipe_filter_bar.dart';
import 'recipe_photo.dart';

/// The household's recipe library (spec §5.2).
///
/// Reads from the local cache, so it works with no network. Recipes appear
/// here the moment they are saved, whether or not the sync has caught up.
class RecipeLibraryScreen extends ConsumerWidget {
  const RecipeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recipe>> library = ref.watch(recipeLibraryProvider);
    final AsyncValue<List<Recipe>> shown = ref.watch(filteredRecipesProvider);
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    // The search bar is hidden only while the library is genuinely empty:
    // once it has anything in it, a filter that matches nothing still needs
    // the controls on screen to be undone.
    final bool hasLibrary = (library.value ?? const <Recipe>[]).isNotEmpty;

    return Scaffold(
      backgroundColor: colors.background,
      // Import sits beside typing rather than replacing it: a recipe out of
      // your own head is still the common case, and importing is the one that
      // moves a library across (spec §5.3).
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'recipe-write',
            onPressed: () => context.push('/recipe/write'),
            backgroundColor: colors.surfaceElevated,
            foregroundColor: colors.textPrimary,
            tooltip: 'Have Hearth write one',
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: HearthSpacing.sm),
          FloatingActionButton.small(
            heroTag: 'recipe-import',
            onPressed: () => context.push('/recipe/import'),
            backgroundColor: colors.surfaceElevated,
            foregroundColor: colors.textPrimary,
            tooltip: 'Import from a picture or a link',
            child: const Icon(Icons.document_scanner_outlined),
          ),
          const SizedBox(height: HearthSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'recipe-new',
            onPressed: () => context.push('/recipe/new'),
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            icon: const Icon(Icons.add),
            label: Text('New recipe', style: context.text.label),
          ),
        ],
      ),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) =>
              _LibraryError(error: error, gutter: gutter),
          data: (List<Recipe> recipes) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Outside the empty/non-empty branch on purpose. The household
              // control used to live only in the populated case, which hid it
              // from exactly the person who needs it — someone with an empty
              // library, about to share a code.
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('Recipes', style: context.text.recipeTitle),
                    ),
                    // The household lives behind the library rather than in a
                    // settings pillar of its own: it is a thing you set up
                    // once and then forget (spec §5.1).
                    IconButton(
                      icon: const Icon(Icons.people_outline),
                      tooltip: 'Household',
                      onPressed: () => context.push('/household'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HearthSpacing.md),
              if (hasLibrary) ...<Widget>[
                RecipeFilterBar(gutter: gutter),
                const SizedBox(height: HearthSpacing.md),
              ],
              Expanded(
                child: recipes.isEmpty
                    ? _EmptyLibrary(gutter: gutter)
                    : (shown.value ?? const <Recipe>[]).isEmpty
                    ? _NoMatches(
                        gutter: gutter,
                        filter: filter,
                        onClear: () =>
                            ref.read(recipeFilterProvider.notifier).clearAll(),
                      )
                    : _RecipeList(
                        recipes: shown.value ?? const <Recipe>[],
                        gutter: gutter,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the library looks like when the filters exclude everything.
///
/// Distinct from the empty-library state, and it names the way out: a screen
/// that just says "nothing here" while three chips are quietly lit is how
/// people conclude their recipes are gone.
class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.gutter,
    required this.filter,
    required this.onClear,
  });

  final double gutter;
  final RecipeFilter filter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: EdgeInsets.all(gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'No recipes match',
                style: context.text.sectionHeader,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                filter.text.trim().isEmpty
                    ? 'Nothing in the library fits these filters.'
                    : 'Nothing matches "${filter.text.trim()}".',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              // A calorie or protein chip excludes any recipe whose
              // ingredients aren't all matched to foods — filtering on a
              // number that is missing half the dish would be worse than
              // showing nothing. Said out loud, because an empty screen
              // otherwise reads as a bug.
              if (filter.maxKcalPerServing != null ||
                  filter.minProteinPerServing != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  'Recipes whose ingredients are not all matched to foods have '
                  'no nutrition to filter on, so they are left out of the '
                  'calorie and protein filters.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: HearthSpacing.md),
              FilledButton(
                onPressed: onClear,
                child: const Text('Clear search and filters'),
              ),
            ],
          ),
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
    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter + 72),
    itemCount: recipes.length,
    separatorBuilder: (BuildContext context, int index) =>
        const SizedBox(height: HearthSpacing.md),
    itemBuilder: (BuildContext context, int index) => _DeletableRecipe(
      // Keyed by recipe, not by position. Without this the element at an index
      // is reused when the list shifts, so deleting a recipe handed its
      // swiped-open state straight to whatever moved up into its place.
      key: ValueKey<String>(recipes[index].id),
      recipe: recipes[index],
    ),
  );
}

class _DeletableRecipe extends ConsumerWidget {
  const _DeletableRecipe({required this.recipe, super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwipeToDelete(
    name: recipe.title,
    onDelete: () => ref.read(recipeRepositoryProvider).delete(recipe.id),
    onRestore: () => ref.read(recipeRepositoryProvider).restore(recipe.id),
    child: RecipeCard(recipe: recipe),
  );
}

/// One recipe in the library list.
class RecipeCard extends ConsumerWidget {
  const RecipeCard({required this.recipe, super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool isFavorite =
        (ref.watch(favoriteRecipeIdsProvider).value ?? const <String>{})
            .contains(recipe.id);

    return Semantics(
      button: true,
      label:
          '${recipe.title}. ${_summary(recipe)}'
          '${isFavorite ? '. Favourite' : ''}',
      onTap: () => context.push('/recipe/${recipe.id}'),
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
            padding: const EdgeInsets.fromLTRB(
              HearthSpacing.lg,
              HearthSpacing.lg,
              HearthSpacing.sm,
              HearthSpacing.lg,
            ),
            // The heart sits beside the whole text block rather than beside
            // the title alone: a 44pt tap target inside the title row would
            // set the row's height and open a gap above the summary line.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (hasRecipePhoto(ref, recipe.id)) ...<Widget>[
                  RecipePhoto(
                    recipeId: recipe.id,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(HearthRadius.md),
                  ),
                  const SizedBox(width: HearthSpacing.md),
                ],
                Expanded(
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
                            for (final String tag in recipe.tags)
                              _Tag(label: tag),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Favouriting from the list, not only from inside the recipe:
                // the heart is worth nothing if reaching it costs two
                // navigations.
                _FavoriteButton(recipeId: recipe.id, compact: true),
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

/// The heart. Shared by the library card and the recipe screen.
class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.recipeId, this.compact = false});

  final String recipeId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final bool isFavorite =
        (ref.watch(favoriteRecipeIdsProvider).value ?? const <String>{})
            .contains(recipeId);

    return IconButton(
      // The filled-vs-outline shape carries the state, not the colour alone
      // (spec §6.3), and the label says which action the tap performs.
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? colors.accent : colors.textMuted,
        size: compact ? 20 : 24,
      ),
      tooltip: isFavorite ? 'Remove from favourites' : 'Add to favourites',
      onPressed: () =>
          ref.read(collectionRepositoryProvider).toggleFavorite(recipeId),
    );
  }
}

/// The heart, for screens outside this file.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({required this.recipeId, super.key});

  final String recipeId;

  @override
  Widget build(BuildContext context) => _FavoriteButton(recipeId: recipeId);
}
