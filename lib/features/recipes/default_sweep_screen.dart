import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/default_sweep.dart';

/// Applying newly-marked defaults to recipes already saved (spec §5.3).
///
/// Marking a default changes what future matching does; it says nothing about
/// the recipes already in the library with lines nobody ever matched. Those
/// are the ones worth fixing — that the question keeps being asked is the
/// whole reason for marking a default — but recipe data is not rewritten in
/// the background. This shows what would change and waits (CLAUDE.md rule 4).
class DefaultSweepScreen extends ConsumerStatefulWidget {
  const DefaultSweepScreen({super.key});

  @override
  ConsumerState<DefaultSweepScreen> createState() => _DefaultSweepScreenState();
}

class _DefaultSweepScreenState extends ConsumerState<DefaultSweepScreen> {
  /// Lines the user has unticked. Held as the exceptions rather than the
  /// selection, so a proposal appearing on a rebuild arrives ticked — the
  /// list is a set of suggestions and the default answer to each is yes.
  final Set<String> _skipped = <String>{};
  bool _saving = false;

  Future<void> _apply(List<DefaultSweepChange> changes) async {
    final List<DefaultSweepChange> wanted = <DefaultSweepChange>[
      for (final DefaultSweepChange change in changes)
        if (!_skipped.contains(change.key)) change,
    ];
    if (wanted.isEmpty) return;

    setState(() => _saving = true);
    try {
      for (final Recipe recipe in DefaultSweep.apply(wanted)) {
        await ref.read(recipeRepositoryProvider).save(recipe);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wanted.length == 1
                ? 'One ingredient matched.'
                : '${wanted.length} ingredients matched.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    final List<Recipe> recipes =
        ref.watch(recipeLibraryProvider).value ?? const <Recipe>[];
    final List<Food> library =
        ref.watch(foodLibraryProvider).value ?? const <Food>[];
    final List<DefaultSweepChange> changes = DefaultSweep.proposals(
      recipes: recipes,
      library: library,
    );
    final int chosen = changes
        .where((DefaultSweepChange c) => !_skipped.contains(c.key))
        .length;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Apply defaults', style: context.text.sectionHeader),
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: HearthSpacing.sm),
            child: FilledButton(
              onPressed: _saving || chosen == 0 ? null : () => _apply(changes),
              child: Text(_saving ? 'Saving…' : 'Apply $chosen'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: changes.isEmpty
            ? _NothingToDo(
                gutter: gutter,
                hasDefaults: library.any((Food f) => f.isDefault),
              )
            : ListView(
                padding: EdgeInsets.all(gutter),
                children: <Widget>[
                  Text(
                    'These ingredients have no food attached, and one of your '
                    'defaults answers them. Untick anything you would rather '
                    'leave alone.',
                    style: context.text.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                  for (final Recipe recipe in _recipesIn(changes)) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
                      child: Text(
                        recipe.title,
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    for (final DefaultSweepChange change in changes)
                      if (change.recipe.id == recipe.id)
                        _ChangeRow(
                          change: change,
                          ticked: !_skipped.contains(change.key),
                          onToggle: _saving
                              ? null
                              : () => setState(() {
                                  if (!_skipped.remove(change.key)) {
                                    _skipped.add(change.key);
                                  }
                                }),
                        ),
                    const SizedBox(height: HearthSpacing.md),
                  ],
                ],
              ),
      ),
    );
  }

  /// The recipes touched, in the order their first change appears.
  static List<Recipe> _recipesIn(List<DefaultSweepChange> changes) {
    final Map<String, Recipe> seen = <String, Recipe>{};
    for (final DefaultSweepChange change in changes) {
      seen.putIfAbsent(change.recipe.id, () => change.recipe);
    }
    return seen.values.toList(growable: false);
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.change,
    required this.ticked,
    required this.onToggle,
  });

  final DefaultSweepChange change;
  final bool ticked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      button: true,
      checked: ticked,
      label:
          '${change.ingredient.name} matched to ${change.food.name}. '
          '${ticked ? 'Will be applied' : 'Skipped'}.',
      onTap: onToggle,
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            margin: const EdgeInsets.only(bottom: HearthSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                // Never colour alone (§6.3): the box itself says whether this
                // one is going to happen.
                Icon(
                  ticked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: ticked ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        change.ingredient.name,
                        style: context.text.ingredient,
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Text(
                        '→ ${change.food.name}',
                        style: context.text.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingToDo extends StatelessWidget {
  const _NothingToDo({required this.gutter, required this.hasDefaults});

  final double gutter;
  final bool hasDefaults;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(gutter * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            hasDefaults ? 'Nothing left to match.' : 'No defaults marked yet.',
            style: context.text.sectionHeader,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            hasDefaults
                ? 'Every ingredient your defaults answer already has a food '
                      'attached.'
                : 'Open a food you buy often and turn on "Use this by '
                      'default". Recipes calling for it will match it on '
                      'their own.',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
