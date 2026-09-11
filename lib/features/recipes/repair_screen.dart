import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/repair_queue.dart';

/// Everything in the library that is not finished, in one place (review N04).
///
/// The three gap kinds have always been on a recipe's own macros, and the
/// editor has always been able to fix one. What there was no way to do was
/// *ask the library* — finding the four recipes with unmatched lines meant
/// opening every recipe in turn, which is why nobody did it and why a
/// half-matched import could sit there for months quietly costing a day its
/// numbers.
///
/// Sorted worst first, and each row goes straight to the place that fixes it.
class RepairScreen extends ConsumerWidget {
  const RepairScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Nutrition repair', style: context.text.label),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: ref
              .watch(repairQueueProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace s) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(gutter),
                    child: Text('The library could not be read.\n$e'),
                  ),
                ),
                data: (RepairQueue queue) => queue.isEmpty
                    ? _NothingToFix(gutter: gutter)
                    : _Queue(queue: queue, gutter: gutter),
              ),
        ),
      ),
    );
  }
}

class _Queue extends StatelessWidget {
  const _Queue({required this.queue, required this.gutter});

  final RepairQueue queue;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        HearthSpacing.lg,
        gutter,
        HearthSpacing.xxl,
      ),
      children: <Widget>[
        // One line for the whole screen, not one per section. Three section
        // blurbs put 260 points of prose above the first row at twice the
        // text on a small phone — the §6.2.4 fault, reproduced on the screen
        // built to answer §6.2.4's siblings.
        Text(
          queue.outstanding == 0
              ? 'Nothing is wrong. The list below is what nobody has said.'
              : queue.outstanding == 1
              ? '1 thing to fix'
              : '${queue.outstanding} things to fix',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (queue.recipes.isNotEmpty) ...<Widget>[
          const SizedBox(height: HearthSpacing.lg),
          _Section(
            // No blurb: each row says what is wrong with it, which is the
            // thing a sentence here would have had to summarise.
            title: 'Recipes with gaps',
            children: <Widget>[
              for (final RecipeRepair repair in queue.recipes)
                _RecipeRow(repair: repair),
            ],
          ),
        ],
        if (queue.unloggable.isNotEmpty) ...<Widget>[
          const SizedBox(height: HearthSpacing.lg),
          _Section(
            title: 'Foods that cannot be logged',
            children: <Widget>[
              for (final FoodRepair food in queue.unloggable)
                _FoodRow(
                  name: food.food.name,
                  brand: food.food.brand,
                  detail: food.food.servingOptions.isEmpty
                      ? 'no serving'
                      : 'every serving is zero',
                  id: food.food.id,
                ),
            ],
          ),
        ],
        if (queue.silent.isNotEmpty) ...<Widget>[
          const SizedBox(height: HearthSpacing.lg),
          _Section(
            title: 'Foods that never said fibre, sodium or cholesterol',
            // The one blurb that survives, because it changes what the
            // section *means*: §5.6 has the three as optional and nullable,
            // so a food that never stated them is being honest. Without this
            // line the heading reads as an accusation.
            blurb: 'Optional, so this is a list rather than a fault.',
            children: <Widget>[
              for (final FoodRepair food in queue.silent)
                _FoodRow(
                  name: food.food.name,
                  brand: food.food.brand,
                  detail: 'no fibre, sodium or cholesterol',
                  id: food.food.id,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A titled group, with the reason it is worth your time above it.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.blurb});

  final String title;

  /// Only where the heading alone would mean the wrong thing.
  final String? blurb;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // A heading for a screen reader too, so the three groups can be
        // jumped between rather than read through (spec §6.3).
        Semantics(
          header: true,
          container: true,
          child: Text(title, style: context.text.sectionHeader),
        ),
        if (blurb case final String blurb) ...<Widget>[
          const SizedBox(height: HearthSpacing.xxs),
          Text(
            blurb,
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
        const SizedBox(height: HearthSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(HearthRadius.lg),
            border: Border.all(color: colors.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(HearthRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: colors.outline),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.repair});

  final RecipeRepair repair;

  /// What is wrong, by kind, in the order a fix would take them.
  ///
  /// Each kind separately rather than "4 problems": they want different
  /// fixes, and a count that hides which is a count you have to open the
  /// recipe to understand — the state this screen exists to end.
  String get _detail => <String>[
    if (repair.unmatched.isNotEmpty)
      '${repair.unmatched.length} not matched to a food',
    if (repair.unconvertible.isNotEmpty)
      '${repair.unconvertible.length} in a unit its food cannot answer',
    if (repair.withoutQuantity.isNotEmpty)
      '${repair.withoutQuantity.length} with no amount',
  ].join(' · ');

  /// The first two lines by name, so a row says which ingredients rather than
  /// only how many.
  String get _named {
    final List<RecipeIngredient> all = repair.all;
    final List<String> names = <String>[
      for (final RecipeIngredient line in all.take(2)) line.name,
    ];
    if (all.length > 2) names.add('and ${all.length - 2} more');
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) => _Row(
    title: repair.recipe.title,
    detail: _detail,
    footnote: _named,
    icon: Icons.link_off,
    // The editor rather than the recipe page: the page shows the gap, the
    // editor is where an ingredient is matched.
    onTap: () => context.push('/recipe/${repair.recipe.id}/edit'),
  );
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.name,
    required this.brand,
    required this.detail,
    required this.id,
  });

  final String name;
  final String? brand;
  final String detail;
  final String id;

  @override
  Widget build(BuildContext context) => _Row(
    title: brand == null || brand!.isEmpty ? name : '$name · $brand',
    detail: detail,
    footnote: null,
    icon: Icons.error_outline,
    onTap: () => context.push('/food/$id'),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.detail,
    required this.footnote,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String detail;
  final String? footnote;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      button: true,
      label: <String?>[title, detail, footnote].nonNulls.join('. '),
      onTap: onTap,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // Android's floor rather than the shared 44: this is a bare
            // InkWell, so nothing pads it the way a ListTile pads itself.
            constraints: const BoxConstraints(
              minHeight: HearthTouch.androidTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 20, color: colors.textMuted),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: context.text.body),
                        const SizedBox(height: HearthSpacing.xxs),
                        Text(
                          detail,
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (footnote case final String footnote) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            footnote,
                            style: context.text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Icon(Icons.chevron_right, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingToFix extends StatelessWidget {
  const _NothingToFix({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return CentredMessage(
      gutter: gutter,
      children: <Widget>[
        Text(
          'Nothing to repair',
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'Every recipe counts all of its ingredients, and every food can be '
          'logged.',
          style: context.text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
