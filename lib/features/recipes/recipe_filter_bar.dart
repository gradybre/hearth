import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/sort_button.dart';
import '../../data/local/collection_store.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_query.dart';

/// Search box and combinable filter chips over the library (spec §5.2).
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
    final List<Recipe> library =
        ref.watch(recipeLibraryProvider).value ?? const <Recipe>[];
    final List<CollectionSummary> collections =
        ref.watch(collectionsProvider).value ?? const <CollectionSummary>[];

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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: widget.gutter),
          child: Row(
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
              _Chip(
                label: 'Favourites',
                icon: Icons.favorite,
                selected: filter.favoritesOnly,
                onTap: control.toggleFavoritesOnly,
              ),
              // Narrows to meals eaten out; it never hides them. They live in
              // this library like anything else, and a tab that quietly
              // omitted a third of what you eat would be worse than useless
              // (spec §5.2).
              _Chip(
                label: 'Eaten out',
                icon: Icons.storefront,
                selected: filter.eatenOutOnly,
                onTap: control.toggleEatenOutOnly,
              ),
              for (final _TimeChoice choice in _TimeChoice.values)
                _Chip(
                  label: choice.label,
                  icon: Icons.schedule,
                  selected: filter.maxTotalTime == choice.limit,
                  onTap: () => control.setMaxTotalTime(
                    filter.maxTotalTime == choice.limit ? null : choice.limit,
                  ),
                ),
              _Chip(
                label: 'Protein 30 g+',
                icon: Icons.egg_alt_outlined,
                selected: filter.minProteinPerServing != null,
                onTap: () => control.setMinProtein(
                  filter.minProteinPerServing == null ? 30 : null,
                ),
              ),
              _Chip(
                label: 'Under 600 kcal',
                icon: Icons.local_fire_department_outlined,
                selected: filter.maxKcalPerServing != null,
                onTap: () => control.setMaxKcal(
                  filter.maxKcalPerServing == null ? 600 : null,
                ),
              ),
              for (final CollectionSummary collection in collections)
                _Chip(
                  label: collection.name,
                  icon: Icons.menu_book_outlined,
                  selected: filter.collectionIds.contains(collection.id),
                  onTap: () => control.toggleCollection(collection.id),
                ),
              for (final String cuisine in RecipeSearch.cuisinesIn(library))
                _Chip(
                  label: _titleCase(cuisine),
                  icon: Icons.public,
                  selected: filter.cuisines.contains(cuisine),
                  onTap: () => control.toggleCuisine(cuisine),
                ),
              for (final String tag in RecipeSearch.tagsIn(library))
                _Chip(
                  label: _titleCase(tag),
                  icon: Icons.label_outline,
                  selected: filter.tags.contains(tag),
                  onTap: () => control.toggleTag(tag),
                ),
            ],
          ),
        ),
        if (filter.activeCount > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.gutter,
              HearthSpacing.sm,
              widget.gutter,
              0,
            ),
            child: TextButton.icon(
              onPressed: control.clearChips,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text(
                filter.activeCount == 1
                    ? 'Clear 1 filter'
                    : 'Clear ${filter.activeCount} filters',
              ),
            ),
          ),
      ],
    );
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// The time chips on offer. Fixed rather than free-entry: picking a number is
/// a decision, and "under 30 minutes" is the one actually made on a weeknight.
enum _TimeChoice {
  quick('Under 30 min', Duration(minutes: 30)),
  hour('Under 1 hr', Duration(hours: 1));

  const _TimeChoice(this.label, this.limit);

  final String label;
  final Duration limit;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: HearthSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: selected ? colors.accent : colors.outline,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.md,
                vertical: HearthSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // A lit chip swaps to a filled check, so the state does not
                  // rest on the fill colour alone (spec §6.3).
                  Icon(
                    selected ? Icons.check : icon,
                    size: 16,
                    color: selected ? colors.onAccent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.xs),
                  Text(
                    label,
                    style: context.text.label.copyWith(
                      color: selected ? colors.onAccent : colors.textPrimary,
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
