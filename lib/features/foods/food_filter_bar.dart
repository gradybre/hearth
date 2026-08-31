import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/sort_button.dart';
import '../../domain/foods/food_query.dart';
import '../../domain/models/food.dart';

/// Sort and filter chips over the food library.
///
/// The recipe library's bar owns its own search box; this one deliberately
/// does not. The Foods screen's search field drives the *outward* Open Food
/// Facts and USDA search as well as this filter, so it stays where it is and
/// this sits underneath it.
class FoodFilterBar extends ConsumerWidget {
  const FoodFilterBar({required this.gutter, super.key});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FoodFilter filter = ref.watch(foodFilterProvider);
    final FoodFilterController control = ref.read(foodFilterProvider.notifier);
    final List<Food> library =
        ref.watch(foodLibraryProvider).value ?? const <Food>[];

    // Only the sources and tags the library actually contains: a chip that
    // can only ever return nothing is noise in a row already this long.
    final List<FoodSource> sources = FoodSearch.sourcesIn(library);
    final List<String> storeTags = FoodSearch.storeTagsIn(library);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Row(
            children: <Widget>[
              SortButton<FoodSort>(
                value: filter.sort,
                choices: <SortChoice<FoodSort>>[
                  for (final FoodSort sort in FoodSort.values)
                    SortChoice<FoodSort>(value: sort, label: sort.label),
                ],
                onChanged: control.setSort,
              ),
              _Chip(
                label: 'Needs attention',
                icon: Icons.error_outline,
                selected: filter.needsAttention,
                onTap: control.toggleNeedsAttention,
              ),
              _Chip(
                label: 'Has barcode',
                icon: Icons.qr_code_scanner,
                selected: filter.hasBarcode,
                onTap: control.toggleHasBarcode,
              ),
              for (final FoodSource source in sources)
                _Chip(
                  label: _sourceLabel(source),
                  icon: Icons.inventory_2_outlined,
                  selected: filter.sources.contains(source),
                  onTap: () => control.toggleSource(source),
                ),
              for (final String tag in storeTags)
                _Chip(
                  label: tag,
                  icon: Icons.storefront_outlined,
                  selected: filter.storeTags.contains(tag),
                  onTap: () => control.toggleStoreTag(tag),
                ),
            ],
          ),
        ),
        if (filter.activeCount > 0)
          Padding(
            padding: EdgeInsets.only(left: gutter, top: HearthSpacing.xs),
            child: TextButton.icon(
              onPressed: control.clearChips,
              icon: const Icon(Icons.close, size: 16),
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

  /// What a source is called on a chip.
  ///
  /// "Yours" rather than "Manual": from the library's side the distinction
  /// that matters is whether this household typed the numbers or a stranger
  /// did, which is the same reason the scan screen says "Your library".
  static String _sourceLabel(FoodSource source) => switch (source) {
    FoodSource.manual => 'Yours',
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.usda => 'USDA',
    FoodSource.aiEstimate => 'AI estimate',
  };
}

/// The same chip the recipe filter bar uses, kept private to each bar rather
/// than shared: they are one small widget apart, and a shared one would have
/// to grow options for both.
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
