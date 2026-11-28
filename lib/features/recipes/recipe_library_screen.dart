import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../app/widgets/recipe_art.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/default_sweep.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/recipes/recipe_artwork.dart';
import '../../domain/recipes/recipe_query.dart';
import 'add_recipe_sheet.dart';
import 'macro_stats_row.dart';
import 'recipe_detail_screen.dart';
import 'recipe_filter_bar.dart';
import 'recipe_icon.dart';
import 'recipe_photo.dart';

/// The household's recipe library (spec §5.2, and the November 2026
/// templates).
///
/// Reads from the local cache, so it works with no network. Recipes appear
/// here the moment they are saved, whether or not the sync has caught up.
///
/// **Two shapes.** On a phone, a half-screen window, or anything narrower
/// than [HearthLayout.detailPaneBreakpoint], this is a list and opening a
/// recipe pushes over it. Wider than that, the list keeps a column of its
/// own and the recipe opens in a pane beside it — which is what the desktop
/// template draws, and what the screenshot that prompted this redesign was
/// missing: a correct layout by the letter of §6.2 that still left the right
/// half of a 1280pt window as empty paper.
///
/// `/recipe/:id` stays a real route either way. The pane is a layout, not a
/// second way of navigating: a link, a plan entry and a search result all
/// still open a whole screen.
class RecipeLibraryScreen extends ConsumerWidget {
  const RecipeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: context.colors.background,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // The section's own width, not the window's: the sidebar has
          // already taken 208 points and a divider out of it, and asking
          // MediaQuery here would split a window that has no room for it.
          //
          // And the words as well as the window. Everywhere else a Hearth
          // layout gives way it gives way at [A11y.reflowThreshold] — this
          // file's own floating button did, until the heading took it — so
          // a 400pt column of three-times-sized titles beside a pane is not
          // the shape to hold on to on a desktop somebody has turned the
          // text up on. One column, and it gets the whole window.
          if (constraints.maxWidth < HearthLayout.detailPaneBreakpoint ||
              A11y.scaleOf(context) > A11y.reflowThreshold) {
            return const ReadingColumn(child: _LibraryList());
          }
          return Row(
            // Stretched, so the divider runs the height of the pane rather
            // than sizing itself to whichever column is shorter.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(
                width: HearthLayout.listColumnWidth,
                child: _LibraryList(inPane: true),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: context.colors.outline,
              ),
              const Expanded(child: _DetailPane()),
            ],
          );
        },
      ),
    ),
  );
}

/// The library itself: heading, filters, and the rows.
class _LibraryList extends ConsumerWidget {
  const _LibraryList({this.inPane = false});

  /// Whether a detail pane is beside this list.
  ///
  /// It changes two things: a row opens into the pane instead of pushing,
  /// and the row that is open says so.
  final bool inPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recipe>> library = ref.watch(recipeLibraryProvider);
    final AsyncValue<List<Recipe>> shown = ref.watch(filteredRecipesProvider);
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    // The column beside a pane is 400 points wide whatever the window is, so
    // it takes the compact gutter: the expanded one would spend a tenth of
    // the column on its own margins.
    final double gutter = !inPane && MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    // The search bar is hidden only while the library is genuinely empty:
    // once it has anything in it, a filter that matches nothing still needs
    // the controls on screen to be undone.
    final bool hasLibrary = (library.value ?? const <Recipe>[]).isNotEmpty;

    return library.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) =>
          _LibraryError(error: error, gutter: gutter),
      data: (List<Recipe> recipes) {
        // Computed here rather than in the header so the button knows
        // whether it would find anything before it is offered.
        final bool sweepable = DefaultSweep.proposals(
          recipes: recipes,
          library: ref.watch(foodLibraryProvider).value ?? const <Food>[],
        ).isNotEmpty;

        // Slivers rather than a Column with an Expanded list.
        //
        // The header and the filter bar were fixed chrome above the list,
        // and on a 320x568 phone at three times the text they are taller
        // than the screen on their own — so the list was handed a
        // negative height and the whole thing overflowed by ten points.
        // As slivers the chrome scrolls away with the content, which is
        // what a short screen needs and what a tall one never noticed.
        return CustomScrollView(
          slivers: <Widget>[
            // Outside the empty/non-empty branch on purpose. The household
            // control used to live only in the populated case, which hid it
            // from exactly the person who needs it — someone with an empty
            // library, about to share a code.
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                // A Wrap rather than a Row: at three times the text
                // the heading and the button together are wider than
                // a phone, and the button drops to its own line
                // instead of squeezing the words (spec §6.3).
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: HearthSpacing.md,
                  runSpacing: HearthSpacing.sm,
                  children: <Widget>[
                    Text('Recipes', style: context.text.recipeTitle),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Flexible, because the Wrap wraps this pair
                        // as a unit: on its own line at three times
                        // the text the button is still wider than a
                        // 320pt phone, and the label has to be allowed
                        // to take two lines rather than overflow.
                        const Flexible(child: _AddRecipeButton()),
                        _MaintenanceMenu(sweepable: sweepable),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: HearthSpacing.md)),
            if (hasLibrary) ...<Widget>[
              SliverToBoxAdapter(child: RecipeFilterBar(gutter: gutter)),
              const SliverToBoxAdapter(
                child: SizedBox(height: HearthSpacing.md),
              ),
            ],
            if (recipes.isEmpty)
              // Filling what is left, so a centred message stays centred
              // on a tall screen and grows past it when it must.
              //
              // `hasScrollBody: false` asks the child for an intrinsic
              // height, which a LayoutBuilder cannot answer — so the
              // message is told not to scroll, and answers. With a scroll
              // body instead, this sliver claims a whole viewport of
              // scroll extent regardless of the chrome above it, and the
              // empty states gain dead scroll they never had.
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyLibrary(gutter: gutter),
              )
            else if ((shown.value ?? const <Recipe>[]).isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NoMatches(
                  gutter: gutter,
                  filter: filter,
                  onClear: () =>
                      ref.read(recipeFilterProvider.notifier).clearAll(),
                ),
              )
            else
              _RecipeSliver(
                recipes: shown.value ?? const <Recipe>[],
                gutter: gutter,
                inPane: inPane,
              ),
          ],
        );
      },
    );
  }
}

/// The recipe beside the list, or the invitation to choose one.
class _DetailPane extends ConsumerWidget {
  const _DetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? selected = ref.watch(selectedRecipeIdProvider);
    if (selected == null) {
      // Nothing is opened for you. A window wide enough for two columns is
      // not a reason to open a recipe nobody asked for — and the first row
      // of a list sorted by "recent" is a different recipe every week.
      return CentredMessage(
        gutter: HearthSpacing.gutterExpanded,
        children: <Widget>[
          Text(
            'Choose a recipe',
            style: context.text.sectionHeader,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'Pick one from the list and it opens here.',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return RecipeDetailScreen(
      // Keyed by recipe, so choosing another one rebuilds the pane from
      // scratch. Without this the state inside it — the servings it has
      // been scaled to, above all — travels from one recipe to the next,
      // and a 12-serving stew opens as a doubled bowl of oats.
      key: ValueKey<String>('detail-pane-$selected'),
      recipeId: selected,
      embedded: true,
    );
  }
}

/// The way into the library, beside its heading (the November 2026
/// templates).
///
/// **It used to float.** A 56pt pill over the list is the shape this was for
/// two years, and it cost a documented defect: at three times the text it is
/// 274 points wide and 72 tall, parked over the right-hand end of every row
/// — which is exactly where the delete a swipe uncovers lands. The hit test
/// stopped at the pill, so pressing a visible, enabled Delete opened the Add
/// recipe sheet. The cure was a second shape — a docked bar, switched in
/// past the app's reflow threshold — plus a band of clearance under the last
/// row for the floating case.
///
/// In the heading there is no floating case, no second shape and no
/// clearance: the Scaffold lays the button out above the list like anything
/// else, and nothing is ever drawn over a row at any text size. What is
/// given up is that it scrolls away with the heading — the same bargain the
/// search field above it already makes.
///
/// It keeps the words "Add recipe" rather than the templates' "+ Add": U05's
/// rule is that every way in says what it is, and three of the four doors
/// this replaced were icon-only with their meaning in a tooltip — a hover,
/// on a device with no pointer.
class _AddRecipeButton extends StatelessWidget {
  const _AddRecipeButton();

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return OutlinedButton.icon(
      onPressed: () => showAddRecipeSheet(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.accent),
        // A floor, never a fixed height: the label grows with the text
        // setting and the control grows with it (spec §6.3).
        minimumSize: const Size(
          HearthTouch.androidTarget,
          HearthTouch.androidTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.md,
          vertical: HearthSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HearthRadius.md),
        ),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text('Add recipe', style: context.text.label),
    );
  }
}

/// What the library looks like when the filters exclude everything.
///
/// Distinct from the empty-library state, and it names the way out: a screen
/// that just says "nothing here" while three chips are quietly lit is how
/// people conclude their recipes are gone.
/// The library's maintenance, in a labelled menu (review §6.2.6, N04).
///
/// This corner used to hold two icon-only buttons whose meaning lived in a
/// tooltip — a hover, on a device with no pointer — and one of them was
/// called "Household" and opened Settings. The shell has carried Settings on
/// every screen since #58 and #61, so that one was a second door with worse
/// words, and it is gone rather than relabelled.
///
/// The same pattern Foods got in #64, deliberately: the review's complaint is
/// that sibling screens invent their own conventions.
class _MaintenanceMenu extends StatelessWidget {
  const _MaintenanceMenu({required this.sweepable});

  /// Whether any unmatched ingredient has a default waiting for it.
  final bool sweepable;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More',
    onSelected: (String path) => context.push(path),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: '/recipe/repair',
        child: Text('Nutrition repair', style: context.text.body),
      ),
      // Only when there is something to sweep. A row that can only ever say
      // "nothing to do" is a row that teaches people not to press it.
      if (sweepable)
        PopupMenuItem<String>(
          value: '/recipe/defaults',
          child: Text(
            'Apply defaults to unmatched ingredients',
            style: context.text.body,
          ),
        ),
    ],
  );
}

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
    return CentredMessage(
      // Inside a SliverFillRemaining that sizes itself from this, so it
      // must not claim to scroll: see the sliver below.
      scrollable: false,
      gutter: gutter,
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
            style: context.text.metadata.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: HearthSpacing.md),
        FilledButton(
          onPressed: onClear,
          child: const Text('Clear search and filters'),
        ),
      ],
    );
  }
}

/// The list, as a sliver so it shares one scroll view with the chrome above
/// it (see the comment on that scroll view).
class _RecipeSliver extends StatelessWidget {
  const _RecipeSliver({
    required this.recipes,
    required this.gutter,
    required this.inPane,
  });

  final List<Recipe> recipes;
  final double gutter;
  final bool inPane;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
    sliver: SliverList.separated(
      itemCount: recipes.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: HearthSpacing.md),
      itemBuilder: (BuildContext context, int index) => _DeletableRecipe(
        // Keyed by recipe, not by position. Without this the element at an
        // index is reused when the list shifts, so deleting a recipe handed
        // its swiped-open state straight to whatever moved up into its place.
        key: ValueKey<String>(recipes[index].id),
        recipe: recipes[index],
        inPane: inPane,
      ),
    ),
  );
}

class _DeletableRecipe extends ConsumerWidget {
  const _DeletableRecipe({
    required this.recipe,
    this.inPane = false,
    super.key,
  });

  final Recipe recipe;
  final bool inPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwipeToDelete(
    name: recipe.title,
    onDelete: () {
      // A recipe cannot stay open in the pane after it has gone from the
      // list beside it. Cleared before the delete, so the pane is not
      // reading a row that is on its way out.
      if (inPane && ref.read(selectedRecipeIdProvider) == recipe.id) {
        ref.read(selectedRecipeIdProvider.notifier).show(null);
      }
      return ref.read(recipeRepositoryProvider).delete(recipe.id);
    },
    onRestore: () async {
      await ref.read(recipeRepositoryProvider).restore(recipe.id);
      // And back into the pane. Everything Hearth deletes is soft-deleted
      // so that the undo is a real undo (§4), and one that returns the row
      // without the half-read page you were on is not quite one.
      //
      // "Is the pane empty" rather than a flag set by the delete: the
      // delete awaits a write to the database, which takes frames, and by
      // the time the snackbar reads `onRestore` this widget has been
      // rebuilt and any closure holding such a flag replaced. An empty
      // pane is the state the delete left behind, and it is still there to
      // read.
      if (inPane && ref.read(selectedRecipeIdProvider) == null) {
        ref.read(selectedRecipeIdProvider.notifier).show(recipe.id);
      }
    },
    child: RecipeCard(recipe: recipe, inPane: inPane),
  );
}

/// One recipe in the library list.
class RecipeCard extends ConsumerWidget {
  const RecipeCard({required this.recipe, this.inPane = false, super.key});

  final Recipe recipe;

  /// Whether this row opens into a pane beside the list rather than pushing
  /// a screen over it.
  final bool inPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool isFavorite =
        (ref.watch(favoriteRecipeIdsProvider).value ?? const <String>{})
            .contains(recipe.id);

    final Map<String, Food> foods = <String, Food>{
      for (final Food food
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };
    final RecipeMacros macros = MacroCalculator.forRecipe(recipe, foods: foods);
    final bool selected =
        inPane && ref.watch(selectedRecipeIdProvider) == recipe.id;
    final RecipeArt art = RecipeArt(
      artworkId: pickRecipeArtwork(
        title: recipe.title,
        tags: recipe.tags,
        cuisine: recipe.cuisine,
      ),
      size: 40,
    );
    void open() {
      if (inPane) {
        ref.read(selectedRecipeIdProvider.notifier).show(recipe.id);
      } else {
        context.push('/recipe/${recipe.id}');
      }
    }

    // Shown for any recipe with ingredients, complete or not. Hiding a
    // partial total was meant to avoid quoting a number that undercounts,
    // but it made a whole recipe's nutrition vanish over one unresolved
    // line, with nothing on screen to say why — so the total stays and is
    // marked as partial instead, which is the same "flag, never block" rule
    // the rest of the app follows (spec §5.3).
    final bool showMacros = recipe.allIngredients.isNotEmpty;

    return Semantics(
      button: true,
      label:
          '${recipe.title}. ${_summary(recipe)}'
          '${showMacros ? '. ${_macroLabel(macros.perServing)}'
                    '${macros.isIncomplete ? '. Partial — ${macros.incompleteReason}' : ''}' : ''}'
          '${isFavorite ? '. Favourite' : ''}',
      // Announced as well as drawn: the bar down its edge says which recipe
      // the pane is showing to somebody looking at the screen, and this
      // says it to somebody who is not (spec §6.3).
      selected: inPane ? selected : null,
      onTap: open,
      excludeSemantics: true,
      // The bar down the open row's leading edge, drawn as a ground the
      // card is inset from rather than as a border: a `Border` cannot have
      // one side thicker than the others and keep a radius, and a `Stack`
      // over the card would take the taps along that edge.
      //
      // A shape, not a shade. The tint and the accent outline below say the
      // same thing in colour, and colour alone is never the meaning
      // (spec §6.3) — this is what survives a greyscale print.
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.accent : null,
          borderRadius: BorderRadius.circular(HearthRadius.lg),
        ),
        padding: EdgeInsets.only(left: selected ? 4 : 0),
        child: Material(
          color: selected ? colors.surfaceSunken : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          child: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(HearthRadius.lg),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.lg),
                border: Border.all(
                  color: selected ? colors.accent : colors.outline,
                ),
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
                  ]
                  // A photograph of the actual dish beats a sketch of the idea
                  // of it, so the icon takes the slot only when there is no
                  // photo — never both, which would be two pictures of one
                  // recipe competing in a 64pt square.
                  else if (RecipeIcon.canDraw(recipe.iconSvg)) ...<Widget>[
                    RecipeIcon(svg: recipe.iconSvg, size: 40),
                    const SizedBox(width: HearthSpacing.md),
                  ]
                  // And the house's drawing of what kind of thing this is,
                  // last of the three, because it is the one that knows
                  // least about the recipe in front of it: a photograph is
                  // this dish, a sketch is this recipe's own doodle of
                  // itself, and this is a drawing of the category. It only
                  // ever fills a slot that would have been empty.
                  else if (art.hasArt) ...<Widget>[
                    art,
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
                          style: text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        if (showMacros) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          MacroStatsLine(
                            macros: macros.perServing,
                            isPartial: macros.isIncomplete,
                          ),
                        ],
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

  static String _macroLabel(Macros perServing) =>
      'Per serving: ${perServing.kcal.round()} calories, '
      '${perServing.proteinG.round()} grams protein, '
      '${perServing.carbG.round()} grams carbohydrates, '
      '${perServing.fatG.round()} grams fat';

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

    return CentredMessage(
      // Inside a SliverFillRemaining that sizes itself from this, so it
      // must not claim to scroll: see the sliver below.
      scrollable: false,
      gutter: gutter,
      children: <Widget>[
        Text(
          'Your library is empty',
          style: text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          // No colon anywhere in this sentence, deliberately: the cook
          // timer's test reads "any text containing a colon" as a timer
          // showing, so prose with one in it fails a test about timers.
          'Add recipe offers four ways in — write one, import one from a '
          'photo or a link, build what you ate out, or have Hearth write it.',
          style: text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
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
    return CentredMessage(
      gutter: gutter,
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
