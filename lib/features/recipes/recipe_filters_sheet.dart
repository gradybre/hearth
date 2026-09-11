import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/local/collection_store.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_query.dart';

/// Everything the library can be narrowed by, except the two toggles that
/// stay in the rail (spec §5.2, review P6).
///
/// The rail used to hold all of this at once — one chip per collection, per
/// cuisine and per tag, in a horizontal scroll view — so it ran off the side
/// of a 1280pt window, was a scroll inside a scroll on a phone, and grew
/// longest for the person with the most recipes to sift through. Nothing has
/// been taken away; it has been given a surface with room for it.
///
/// The chips toggle live, and the list behind the sheet narrows as they are
/// tapped: choosing a filter you cannot see the effect of is how you end up
/// closing a sheet twice to find out what it did.
Future<void> showRecipeFiltersSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _RecipeFiltersSheet(),
    );

/// The time filters on offer. Fixed rather than free-entry: picking a number
/// is a decision, and "under 30 minutes" is the one actually made on a
/// weeknight.
///
/// Public because the applied-filter strip has to name a lit one, and a
/// second copy of these two durations in the bar is how the sheet and the
/// strip would come to disagree about what "Under 1 hr" means.
enum RecipeTimeFilter {
  quick('Under 30 min', Duration(minutes: 30)),
  hour('Under 1 hr', Duration(hours: 1));

  const RecipeTimeFilter(this.label, this.limit);

  final String label;
  final Duration limit;

  /// What to call [limit] on the applied strip.
  static String labelFor(Duration limit) {
    for (final RecipeTimeFilter choice in values) {
      if (choice.limit == limit) return choice.label;
    }
    return 'Under ${limit.inMinutes} min';
  }
}

/// The protein floor the chip offers, in grams per serving.
const double kRecipeProteinFloor = 30;

/// The calorie ceiling the chip offers, per serving.
const double kRecipeKcalCeiling = 600;

String recipeProteinLabel(double grams) => 'Protein ${_trimZero(grams)} g+';

String recipeKcalLabel(double kcal) => 'Under ${_trimZero(kcal)} kcal';

String _trimZero(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';

/// Title-cases a folded tag or cuisine for display.
String recipeFacetLabel(String folded) =>
    folded.isEmpty ? folded : folded[0].toUpperCase() + folded.substring(1);

class _RecipeFiltersSheet extends ConsumerWidget {
  const _RecipeFiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final RecipeFilter filter = ref.watch(recipeFilterProvider);
    final RecipeFilterController control = ref.read(
      recipeFilterProvider.notifier,
    );
    final List<Recipe> library =
        ref.watch(recipeLibraryProvider).value ?? const <Recipe>[];
    final List<CollectionSummary> collections =
        ref.watch(collectionsProvider).value ?? const <CollectionSummary>[];
    final List<String> cuisines = RecipeSearch.cuisinesIn(library);
    final List<String> tags = RecipeSearch.tagsIn(library);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Text(
                  'Filter recipes',
                  style: context.text.sectionHeader,
                ),
              ),
              // Scrolls, because at three times the text almost everything
              // does and a sheet that cannot outgrow its space takes its
              // last group off the bottom of the screen (spec §6.3).
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.lg,
                  ),
                  children: <Widget>[
                    _Group(
                      heading: 'Time',
                      children: <Widget>[
                        for (final RecipeTimeFilter choice
                            in RecipeTimeFilter.values)
                          RecipeFilterChip(
                            label: choice.label,
                            icon: Icons.schedule,
                            selected: filter.maxTotalTime == choice.limit,
                            onTap: () => control.setMaxTotalTime(
                              filter.maxTotalTime == choice.limit
                                  ? null
                                  : choice.limit,
                            ),
                          ),
                      ],
                    ),
                    _Group(
                      heading: 'Nutrition',
                      children: <Widget>[
                        RecipeFilterChip(
                          label: recipeProteinLabel(kRecipeProteinFloor),
                          icon: Icons.egg_alt_outlined,
                          selected: filter.minProteinPerServing != null,
                          onTap: () => control.setMinProtein(
                            filter.minProteinPerServing == null
                                ? kRecipeProteinFloor
                                : null,
                          ),
                        ),
                        RecipeFilterChip(
                          label: recipeKcalLabel(kRecipeKcalCeiling),
                          icon: Icons.local_fire_department_outlined,
                          selected: filter.maxKcalPerServing != null,
                          onTap: () => control.setMaxKcal(
                            filter.maxKcalPerServing == null
                                ? kRecipeKcalCeiling
                                : null,
                          ),
                        ),
                      ],
                    ),
                    // The three that grow with the library. Each is left out
                    // entirely when the household has none rather than shown
                    // as an empty heading, which reads as a group that failed
                    // to load.
                    if (collections.isNotEmpty)
                      _Group(
                        heading: 'Cookbooks',
                        children: <Widget>[
                          for (final CollectionSummary collection
                              in collections)
                            RecipeFilterChip(
                              label: collection.name,
                              icon: Icons.menu_book_outlined,
                              selected: filter.collectionIds.contains(
                                collection.id,
                              ),
                              onTap: () =>
                                  control.toggleCollection(collection.id),
                            ),
                        ],
                      ),
                    if (cuisines.isNotEmpty)
                      _Group(
                        heading: 'Cuisines',
                        children: <Widget>[
                          for (final String cuisine in cuisines)
                            RecipeFilterChip(
                              label: recipeFacetLabel(cuisine),
                              icon: Icons.public,
                              selected: filter.cuisines.contains(cuisine),
                              onTap: () => control.toggleCuisine(cuisine),
                            ),
                        ],
                      ),
                    if (tags.isNotEmpty)
                      _Group(
                        heading: 'Tags',
                        children: <Widget>[
                          for (final String tag in tags)
                            RecipeFilterChip(
                              label: recipeFacetLabel(tag),
                              icon: Icons.label_outline,
                              selected: filter.tags.contains(tag),
                              onTap: () => control.toggleTag(tag),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One heading and the chips under it.
class _Group extends StatelessWidget {
  const _Group({required this.heading, required this.children});

  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          heading,
          style: context.text.label.copyWith(color: context.colors.textMuted),
        ),
        const SizedBox(height: HearthSpacing.sm),
        // A Wrap rather than a row of any kind: at three times the text one
        // chip is most of the width, and a fixed-height box around a growing
        // label is the same fault as ignoring the setting (spec §6.3).
        Wrap(runSpacing: HearthSpacing.sm, children: children),
      ],
    ),
  );
}

/// The filter chip the rail and the sheet share.
///
/// It lives here rather than in the bar so the import runs one way: the bar
/// opens this sheet, and both draw the same chip.
class RecipeFilterChip extends StatelessWidget {
  const RecipeFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.activeIcon,
    this.isToggle = true,
    super.key,
  });

  final String label;
  final IconData icon;

  /// Whether the chip is lit.
  final bool selected;

  /// What to draw when it is lit, for a chip that is not a toggle.
  ///
  /// A toggle swaps to a tick, so its state does not rest on the fill colour
  /// alone (spec §6.3). "Filters (3)" is not a toggle — a tick on it would
  /// say it was switched on — and carries its count in its own label instead.
  final IconData? activeIcon;

  /// Whether to announce a selected state to a screen reader.
  final bool isToggle;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: HearthSpacing.sm),
      child: Semantics(
        button: true,
        selected: isToggle ? selected : null,
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
              // A floor, never a fixed height: the chip grows with the text
              // and never shrinks below a target you can hit (spec §6.3).
              //
              // These chips were 38 points tall for as long as they lived in
              // a horizontal scroll view, and Flutter's tap-target auditor
              // skips anything touching a scrollable's edge — so nothing ever
              // said so. Taking the scroll view away is what made them
              // measurable.
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
                  Icon(
                    selected ? (activeIcon ?? Icons.check) : icon,
                    size: 16,
                    color: selected ? colors.onAccent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.xs),
                  // Flexible, not fixed: at large text the label is wider
                  // than a small phone, and a chip that cannot give is a chip
                  // that overflows.
                  Flexible(
                    child: Text(
                      label,
                      style: context.text.label.copyWith(
                        color: selected ? colors.onAccent : colors.textPrimary,
                      ),
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
