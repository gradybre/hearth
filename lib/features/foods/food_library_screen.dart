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
import '../../domain/text/text_normaliser.dart';

/// The household food library (spec §5.5).
///
/// Until barcode lookup arrives in Phase 2, everything here was entered by
/// hand. Search filters the already-loaded list rather than round-tripping the
/// database, because finding a food is on the daily logging path and every
/// extra tap or wait is paid three times a day.
class FoodLibraryScreen extends ConsumerStatefulWidget {
  const FoodLibraryScreen({super.key});

  @override
  ConsumerState<FoodLibraryScreen> createState() => _FoodLibraryScreenState();
}

class _FoodLibraryScreenState extends ConsumerState<FoodLibraryScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Food> _filter(List<Food> foods) {
    final String needle = normaliseKey(_search.text);
    if (needle.isEmpty) return foods;
    return foods
        .where(
          (Food food) =>
              normaliseKey(food.name).contains(needle) ||
              normaliseKey(food.brand ?? '').contains(needle),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AsyncValue<List<Food>> library = ref.watch(foodLibraryProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      // Scanning leads because it is the faster path for anything with a
      // packet, and typing a food in by hand is what §5.5 falls back to — not
      // the other way round. Both stay one tap.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'food-new',
            onPressed: () => context.push('/food/new'),
            backgroundColor: colors.surfaceElevated,
            foregroundColor: colors.textPrimary,
            tooltip: 'Add a food by hand',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: HearthSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'food-scan',
            onPressed: () => context.push('/food/scan'),
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text('Scan', style: context.text.label),
          ),
        ],
      ),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) => Center(
            child: Text('The food library could not be read.\n$error'),
          ),
          data: (List<Food> foods) {
            final List<Food> visible = _filter(foods);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                  child: Text('Foods', style: context.text.recipeTitle),
                ),
                Padding(
                  padding: EdgeInsets.all(gutter),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: context.text.body,
                    decoration: InputDecoration(
                      hintText: 'Search foods',
                      prefixIcon: Icon(Icons.search, color: colors.textMuted),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: foods.isEmpty
                      ? _EmptyFoods(gutter: gutter)
                      : visible.isEmpty
                      ? _NoMatches(query: _search.text, gutter: gutter)
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            0,
                            gutter,
                            gutter + 72,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              const SizedBox(height: HearthSpacing.sm),
                          itemBuilder: (BuildContext context, int index) =>
                              FoodCard(food: visible[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One food in the library list.
class FoodCard extends StatelessWidget {
  const FoodCard({required this.food, super.key});

  final Food food;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final ServingOption? serving = food.defaultServing;

    return Semantics(
      button: true,
      label: '${food.name}. ${_summary(food)}',
      onTap: () => context.push('/food/${food.id}'),
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => context.push('/food/${food.id}'),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        food.brand == null
                            ? food.name
                            : '${food.name}  ·  ${food.brand}',
                        style: text.ingredient,
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Text(
                        _summary(food),
                        style: text.metadata.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (serving != null)
                  Text(
                    '${serving.macros.kcal.round()} kcal',
                    style: text.ingredient.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summary(Food food) {
    final ServingOption? serving = food.defaultServing;
    if (serving == null) return 'No serving size yet';
    final String portion = QuantityFormat.formatAsAuthored(serving.amount);
    return 'per $portion  ·  '
        'P ${serving.macros.proteinG.round()}  '
        'C ${serving.macros.carbG.round()}  '
        'F ${serving.macros.fatG.round()}';
  }
}

class _EmptyFoods extends StatelessWidget {
  const _EmptyFoods({required this.gutter});

  final double gutter;

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
                'No foods yet',
                style: context.text.sectionHeader,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'Scan a packet, or add the things you eat often by hand.',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.gutter});

  final String query;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Nothing matches "$query"',
              style: context.text.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.sm),
            TextButton(
              onPressed: () => context.push('/food/new'),
              child: const Text('Add it as a new food'),
            ),
          ],
        ),
      ),
    );
  }
}
