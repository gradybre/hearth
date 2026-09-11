import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/sort_button.dart';
import '../../data/local/collection_store.dart';
import '../../domain/recipes/recipe_query.dart';
import 'recipe_filters_sheet.dart';

/// Search box, four controls, and what is currently applied (spec §5.2).
///
/// The four are the whole rail: sort, the two toggles worth a tap on the way
/// past, and the way into everything else. It used to be sort, the toggles,
/// two times, protein, calories, **and one chip per collection, per cuisine
/// and per tag** — all in a horizontal scroll view, so it ran off the side of
/// a desktop window, was a scroll inside a scroll on a phone, and grew
/// longest for exactly the person with the most to sift through (review P6).
///
/// What is applied is a strip of named chips below, each removable on its
/// own. The rail before this could only say what was on by being scrolled
/// until the lit ones came past, and the one clear button was all-or-nothing
/// — so undoing one of three filters meant clearing all three and setting two
/// of them again.
class RecipeFilterBar extends ConsumerStatefulWidget {
  const RecipeFilterBar({required this.gutter, super.key});

  final double gutter;

  @override
  ConsumerState<RecipeFilterBar> createState() => _RecipeFilterBarState();
}

class _RecipeFilterBarState extends ConsumerState<RecipeFilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(recipeFilterProvider).text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final RecipeFilterController control = ref.read(
      recipeFilterProvider.notifier,
    );
    final List<CollectionSummary> collections =
        ref.watch(collectionsProvider).value ?? const <CollectionSummary>[];

    final int behindTheButton = _countBehindTheButton(filter);
    final List<_Applied> applied = _applied(filter, control, collections);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.gutter),
          child: TextField(
            controller: _controller,
            onChanged: control.search,
            textInputAction: TextInputAction.search,
            style: context.text.body,
            decoration: InputDecoration(
              hintText: 'Search recipes and ingredients',
              hintStyle: context.text.body.copyWith(color: colors.textMuted),
              prefixIcon: Icon(Icons.search, color: colors.textMuted),
              suffixIcon: filter.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _controller.clear();
                        control.search('');
                      },
                    ),
              filled: true,
              fillColor: colors.surfaceSunken,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: HearthSpacing.md),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.gutter),
          // A Wrap, not a horizontal scroll view. Four controls fit on one
          // line on any ordinary phone and wrap onto a second at large text,
          // which is what dynamic type asks for — and nothing here is ever
          // off the right-hand edge waiting to be found (spec §6.3).
          child: Wrap(
            key: const ValueKey<String>('recipe-filter-controls'),
            // Zero, because every child carries its own trailing gap: the
            // sort button's is inside `SortButton`, out of reach from here.
            runSpacing: HearthSpacing.sm,
            children: <Widget>[
              // Sort leads the row: it is always on and always relevant,
              // unlike the chips beside it, which are each off until chosen.
              SortButton<RecipeSort>(
                value: filter.sort,
                choices: <SortChoice<RecipeSort>>[
                  for (final RecipeSort sort in RecipeSort.values)
                    SortChoice<RecipeSort>(value: sort, label: sort.label),
                ],
                onChanged: control.setSort,
              ),
              RecipeFilterChip(
                label: 'Favourites',
                icon: Icons.favorite,
                selected: filter.favoritesOnly,
                onTap: control.toggleFavoritesOnly,
              ),
              // Narrows to meals eaten out; it never hides them. They live in
              // this library like anything else, and a tab that quietly
              // omitted a third of what you eat would be worse than useless
              // (spec §5.2).
              RecipeFilterChip(
                label: 'Eaten out',
                icon: Icons.storefront,
                selected: filter.eatenOutOnly,
                onTap: control.toggleEatenOutOnly,
              ),
              // The count is in the words, not in the fill: a lit chip and an
              // unlit one differ by colour, and colour alone is never the
              // meaning (spec §6.3). It counts only what is behind it — the
              // two toggles are right here, lit, and counting them twice
              // would make "Filters (2)" mean nothing you could act on.
              RecipeFilterChip(
                label: behindTheButton == 0
                    ? 'Filters'
                    : 'Filters ($behindTheButton)',
                icon: Icons.tune,
                activeIcon: Icons.tune,
                isToggle: false,
                selected: behindTheButton > 0,
                onTap: () => showRecipeFiltersSheet(context),
              ),
            ],
          ),
        ),
        if (applied.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.gutter,
              HearthSpacing.sm,
              widget.gutter,
              0,
            ),
            child: Wrap(
              // Each chip carries its own trailing gap, as above.
              runSpacing: HearthSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (final _Applied one in applied)
                  _AppliedChip(label: one.label, onRemove: one.remove),
                // "Clear filters", not "Clear all": `clearChips` keeps the
                // search text, so "all" emptied the strip and left the
                // library still narrowed by a word — with the strip, which
                // is the screen's answer to what is narrowing this list, then
                // saying nothing at all. The search keeps its own × in the
                // field; this button is about the chips beside it.
                TextButton.icon(
                  onPressed: control.clearChips,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear filters'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// How many of the filters the sheet holds are on.
  ///
  /// Deliberately not [RecipeFilter.activeCount]: that counts the favourites
  /// and eaten-out toggles too, and they are in the rail rather than behind
  /// the button.
  static int _countBehindTheButton(RecipeFilter filter) =>
      filter.tags.length +
      filter.cuisines.length +
      filter.collectionIds.length +
      (filter.maxTotalTime == null ? 0 : 1) +
      (filter.maxKcalPerServing == null ? 0 : 1) +
      (filter.minProteinPerServing == null ? 0 : 1);

  /// Everything narrowing the list right now, in the words the strip uses.
  ///
  /// The two toggles are in here as well as in the rail. The rail is where
  /// you switch things on; this strip answers "what is narrowing this list",
  /// and an answer that left two of them out — while the Clear all beside it
  /// cleared them — would be the wrong answer.
  ///
  /// The search box is not: it has its own × inside it, and a chip saying
  /// what is already legible in the field above is noise.
  static List<_Applied> _applied(
    RecipeFilter filter,
    RecipeFilterController control,
    List<CollectionSummary> collections,
  ) => <_Applied>[
    if (filter.favoritesOnly)
      _Applied('Only favourites', control.toggleFavoritesOnly),
    if (filter.eatenOutOnly)
      _Applied('Only eaten out', control.toggleEatenOutOnly),
    if (filter.maxTotalTime case final Duration limit)
      _Applied(
        RecipeTimeFilter.labelFor(limit),
        () => control.setMaxTotalTime(null),
      ),
    if (filter.minProteinPerServing case final double grams)
      _Applied(recipeProteinLabel(grams), () => control.setMinProtein(null)),
    if (filter.maxKcalPerServing case final double kcal)
      _Applied(recipeKcalLabel(kcal), () => control.setMaxKcal(null)),
    // Named by dimension, because a cookbook, a cuisine and a tag can wear
    // the same word and a strip of bare names would not say which of the
    // three a chip was about to remove.
    for (final String id in filter.collectionIds)
      _Applied(
        'Cookbook · ${_collectionName(collections, id)}',
        () => control.toggleCollection(id),
      ),
    for (final String cuisine in filter.cuisines)
      _Applied(
        'Cuisine · ${recipeFacetLabel(cuisine)}',
        () => control.toggleCuisine(cuisine),
      ),
    for (final String tag in filter.tags)
      _Applied('Tag · ${recipeFacetLabel(tag)}', () => control.toggleTag(tag)),
  ];

  /// A cookbook deleted while its filter was on still has to be removable,
  /// so an id with no cookbook behind it is named rather than dropped.
  static String _collectionName(
    List<CollectionSummary> collections,
    String id,
  ) {
    for (final CollectionSummary collection in collections) {
      if (collection.id == id) return collection.name;
    }
    return 'removed';
  }
}

/// One lit filter, and the way to put it out.
@immutable
class _Applied {
  const _Applied(this.label, this.remove);

  final String label;
  final VoidCallback remove;
}

/// A named filter with an × that removes only itself.
///
/// The whole chip is the target, not the × alone: a 16pt glyph is not a tap
/// target on a phone, and there is nothing else the chip could mean.
class _AppliedChip extends StatelessWidget {
  const _AppliedChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: HearthSpacing.sm),
      child: Semantics(
        button: true,
        label: 'Remove filter, $label',
        onTap: onRemove,
        excludeSemantics: true,
        child: Material(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outlineStrong),
              ),
              // A floor, never a fixed height — see RecipeFilterChip.
              constraints: const BoxConstraints(
                minHeight: HearthTouch.minTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.md,
                vertical: HearthSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      label,
                      style: context.text.label.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.xs),
                  Icon(Icons.close, size: 16, color: colors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
