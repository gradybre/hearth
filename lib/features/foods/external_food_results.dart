import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../domain/models/food.dart';
import 'food_draft.dart';
import 'food_search_controller.dart';

/// Foods found beyond the household's own library (spec §5.5).
///
/// Shown under the library's own results, never mixed into them: which foods
/// are yours and which are a stranger's is the difference between numbers you
/// have checked and numbers you have not, and §12 names getting that wrong as
/// the fastest way to lose trust in the whole app.
///
/// Nothing here is in the library yet. Choosing one opens the editor to be
/// read and saved (CLAUDE.md rule 4); [onSaved] then receives its id, which is
/// what lets a recipe ingredient use it as a match.
class ExternalFoodResults extends ConsumerWidget {
  const ExternalFoodResults({
    required this.query,
    required this.onSaved,
    super.key,
  });

  /// What this screen currently has typed.
  ///
  /// The search state is app-wide, so results are shown only when they answer
  /// the question being asked here. Without that, closing the ingredient
  /// picker and opening the food library would show the library someone
  /// else's answers — and reaching for lifecycle callbacks to clear it invites
  /// the disposed-ref crashes that pattern always produces.
  final String query;

  final ValueChanged<String>? onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FoodSearchState state = ref.watch(foodSearchProvider);
    final HearthColors colors = context.colors;

    final String asked = query.trim();
    final String? answering = switch (state) {
      FoodSearchIdle() => null,
      FoodSearchRunning(:final String query) => query,
      FoodSearchResults(:final String query) => query,
    };
    if (answering != asked) return const SizedBox.shrink();

    return switch (state) {
      FoodSearchIdle() => const SizedBox.shrink(),
      FoodSearchRunning() => Padding(
        padding: const EdgeInsets.symmetric(vertical: HearthSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: HearthSpacing.sm),
            Text(
              'Looking further afield…',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
      FoodSearchResults(
        :final List<NutritionMatch> matches,
        :final bool hasMore,
      ) =>
        matches.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: HearthSpacing.lg),
                child: Text(
                  'Nothing else found. Add it by hand and Hearth will keep it.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: HearthSpacing.lg,
                      bottom: HearthSpacing.sm,
                    ),
                    child: Text(
                      'Elsewhere',
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  for (final NutritionMatch match in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                      child: _ExternalFood(match: match, onSaved: onSaved),
                    ),
                  // The old hard cap made "is it really not there" and "there
                  // just wasn't room to show it" look identical. This is the
                  // difference between them.
                  if (hasMore)
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            ref.read(foodSearchProvider.notifier).loadMore(),
                        child: const Text('Show more'),
                      ),
                    ),
                ],
              ),
    };
  }
}

class _ExternalFood extends StatelessWidget {
  const _ExternalFood({required this.match, required this.onSaved});

  final NutritionMatch match;
  final ValueChanged<String>? onSaved;

  String get _sourceLabel => switch (match.source) {
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.usda => 'USDA',
    FoodSource.manual => 'Elsewhere',
    FoodSource.aiEstimate => 'AI estimate',
  };

  Future<void> _choose(BuildContext context) async {
    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.fromLookup(match.food),
    );
    if (saved != null) onSaved?.call(saved);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ServingOption? serving = match.food.defaultServing;
    final String macros = serving == null
        ? 'No serving size'
        : '${serving.label} · ${serving.macros.kcal.round()} kcal';

    return Semantics(
      button: true,
      label:
          '${match.food.name}'
          '${match.food.brand == null ? '' : ', ${match.food.brand}'}. '
          '$macros. From $_sourceLabel.'
          '${match.isLowConfidence ? ' Incomplete, needs checking.' : ''}',
      onTap: () => _choose(context),
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => _choose(context),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        match.food.brand == null
                            ? match.food.name
                            : '${match.food.name} · ${match.food.brand}',
                        style: context.text.ingredient,
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Row(
                        children: <Widget>[
                          Text(
                            macros,
                            style: context.text.metadata.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          if (match.isLowConfidence) ...<Widget>[
                            const SizedBox(width: HearthSpacing.sm),
                            // Never colour alone (§6.3): the doubt is an icon
                            // and a word, not a tint.
                            Icon(
                              Icons.warning_amber_outlined,
                              size: 14,
                              color: colors.error,
                            ),
                            const SizedBox(width: HearthSpacing.xxs),
                            Text(
                              'incomplete',
                              style: context.text.metadata.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HearthSpacing.sm),
                Text(
                  _sourceLabel,
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
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
