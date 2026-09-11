import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../data/repositories/food_merge_repository.dart';
import '../../domain/foods/food_merge.dart';
import '../../domain/format/serving_format.dart';
import '../../domain/models/food.dart';

/// Foods that look like the same thing, and the way to make them one
/// (review N05).
///
/// The duplicate warning offers `Use existing` at the moment a second copy
/// would be made (#69). This is for the copies already there — and unlike
/// that one it writes, so every figure is counted and shown first
/// (CLAUDE.md rule 4).
class MergeScreen extends ConsumerWidget {
  const MergeScreen({super.key});

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
        title: Text('Duplicate foods', style: context.text.label),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: ref
              .watch(duplicateFoodsProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace s) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(gutter),
                    child: Text('The library could not be read.\n$e'),
                  ),
                ),
                data: (List<List<Food>> groups) => groups.isEmpty
                    ? _NoDuplicates(gutter: gutter)
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          HearthSpacing.lg,
                          gutter,
                          HearthSpacing.xxl,
                        ),
                        children: <Widget>[
                          for (final List<Food> group in groups) ...<Widget>[
                            _Group(group: group),
                            const SizedBox(height: HearthSpacing.lg),
                          ],
                        ],
                      ),
              ),
        ),
      ),
    );
  }
}

/// One set of foods that look like each other.
class _Group extends StatelessWidget {
  const _Group({required this.group});

  final List<Food> group;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(group.first.name, style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            for (final Food food in group)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.xxs),
                child: Text(
                  _describe(food),
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
            const SizedBox(height: HearthSpacing.sm),
            // Two at a time, deliberately. A group of four is three merges,
            // each one reviewed — a single button that collapsed all of them
            // would be asking for one yes to four different sets of moves.
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => showMergeReview(
                  context,
                  survivor: group.first,
                  retiring: group[1],
                ),
                child: const Text('Review a merge'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(Food food) {
    final String brand = food.brand == null || food.brand!.isEmpty
        ? ''
        : ' · ${food.brand}';
    if (food.defaultServing case final ServingOption serving) {
      return '${food.name}$brand — ${ServingFormat.describe(serving)}, '
          '${serving.macros.kcal.round()} kcal';
    }
    return '${food.name}$brand — no serving recorded';
  }
}

/// Reviews one merge, then does it (review N05, CLAUDE.md rule 4).
Future<void> showMergeReview(
  BuildContext context, {
  required Food survivor,
  required Food retiring,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext sheet) =>
      _MergeReview(survivor: survivor, retiring: retiring),
);

class _MergeReview extends ConsumerStatefulWidget {
  const _MergeReview({required this.survivor, required this.retiring});

  final Food survivor;
  final Food retiring;

  @override
  ConsumerState<_MergeReview> createState() => _MergeReviewState();
}

class _MergeReviewState extends ConsumerState<_MergeReview> {
  late Food _survivor = widget.survivor;
  late Food _retiring = widget.retiring;
  bool _busy = false;
  String? _refusal;

  Future<MergePlan> _plan() => ref
      .read(foodMergeRepositoryProvider)
      .plan(survivor: _survivor, retiring: _retiring);

  void _swap() => setState(() {
    final Food was = _survivor;
    _survivor = _retiring;
    _retiring = was;
    _refusal = null;
  });

  Future<void> _merge(MergePlan plan) async {
    setState(() {
      _busy = true;
      _refusal = null;
    });
    try {
      await ref.read(foodMergeRepositoryProvider).apply(plan);
      if (mounted) Navigator.of(context).pop();
    } on MergeRefused catch (refused) {
      if (mounted) {
        setState(
          () => _refusal = switch (refused.reason) {
            // Said rather than swallowed: the merge is refused precisely so
            // nothing races the other phone, and a button that did nothing
            // would read as a broken button.
            MergeRefusal.writesStillQueued =>
              'Hearth still has changes to send. Try again once syncing has '
                  'caught up.',
            MergeRefusal.plannedMealCannotConvert =>
              'A planned meal is measured in a way the kept food cannot '
                  'answer, so its amount would change. Nothing was merged.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Material(
      color: colors.background,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HearthRadius.xl),
      ),
      child: SafeArea(
        child: FutureBuilder<MergePlan>(
          future: _plan(),
          builder: (BuildContext context, AsyncSnapshot<MergePlan> snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Text(
                  'The merge could not be worked out.\n'
                  '${snap.error}',
                ),
              );
            }
            if (snap.data case final MergePlan plan) {
              return _Review(
                plan: plan,
                busy: _busy,
                refusal: _refusal,
                onSwap: _swap,
                onMerge: () => _merge(plan),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(HearthSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({
    required this.plan,
    required this.busy,
    required this.refusal,
    required this.onSwap,
    required this.onMerge,
  });

  final MergePlan plan;
  final bool busy;
  final String? refusal;
  final VoidCallback onSwap;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(HearthSpacing.lg),
      children: <Widget>[
        Text('Merge two foods', style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.md),
        _Side(label: 'Keep', food: plan.merged),
        _Side(label: 'Retire', food: plan.retiring),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy ? null : onSwap,
            child: const Text('Keep the other one instead'),
          ),
        ),
        const SizedBox(height: HearthSpacing.md),
        Text('What moves', style: context.text.label),
        const SizedBox(height: HearthSpacing.xs),
        for (final String line in <String>[
          if (plan.recipeLines > 0)
            '${plan.recipeLines} recipe ${plan.recipeLines == 1 ? 'line' : 'lines'}',
          if (plan.rememberedMatches > 0)
            '${plan.rememberedMatches} remembered ${plan.rememberedMatches == 1 ? 'match' : 'matches'}',
          if (plan.plannedMeals.isNotEmpty)
            '${plan.plannedMeals.length} planned ${plan.plannedMeals.length == 1 ? 'meal' : 'meals'}',
          if (plan.shoppingLines > 0)
            '${plan.shoppingLines} shopping ${plan.shoppingLines == 1 ? 'line' : 'lines'}',
          if (plan.moves == 0) 'nothing — no recipe or plan uses it',
        ])
          Text(
            line,
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        // Counted and named before the button rather than discovered after.
        // The repair queue would catch these eventually; that is a safety
        // net, not an answer.
        if (plan.stranded.isNotEmpty) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          Text('What stops counting', style: context.text.label),
          const SizedBox(height: HearthSpacing.xs),
          for (final StrandedLine line in plan.stranded)
            Text(
              '${line.ingredientName} in ${line.recipeTitle} — the kept food '
              'has no serving in ${line.unitLabel}',
              style: context.text.metadata.copyWith(color: colors.error),
            ),
        ],
        const SizedBox(height: HearthSpacing.md),
        Text('What does not move', style: context.text.label),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          plan.loggedMeals == 0
              ? 'No meal has been logged against it.'
              : '${plan.loggedMeals} logged ${plan.loggedMeals == 1 ? 'meal' : 'meals'} — '
                    'untouched, with the numbers and the name frozen at the '
                    'time they were eaten.',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (!plan.canProceed) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          Text(
            'This one cannot be merged: '
            '${plan.unconvertible.length} planned '
            '${plan.unconvertible.length == 1 ? 'meal is' : 'meals are'} '
            'measured in a way the kept food cannot answer, so the amount '
            'would change. Keeping the other one instead may work.',
            style: context.text.body.copyWith(color: colors.error),
          ),
        ],
        if (refusal case final String refusal) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          Text(refusal, style: context.text.body.copyWith(color: colors.error)),
        ],
        const SizedBox(height: HearthSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy || !plan.canProceed ? null : onMerge,
            child: Text(
              busy
                  ? 'Merging…'
                  : plan.moves == 0
                  ? 'Merge'
                  : 'Merge · ${plan.moves} ${plan.moves == 1 ? 'thing moves' : 'things move'}',
            ),
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.food});

  final String label;
  final Food food;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
          Text(
            food.brand == null || food.brand!.isEmpty
                ? food.name
                : '${food.name}  ·  ${food.brand}',
            style: context.text.body,
          ),
          Text(
            food.servingOptions.isEmpty
                ? 'no serving recorded'
                : '${food.servingOptions.length} '
                      '${food.servingOptions.length == 1 ? 'serving' : 'servings'}'
                      '${food.barcode == null ? '' : ' · barcode ${food.barcode}'}',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoDuplicates extends StatelessWidget {
  const _NoDuplicates({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return CentredMessage(
      gutter: gutter,
      children: <Widget>[
        Text(
          'No duplicates',
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'No two foods share a name or a barcode.',
          style: context.text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
