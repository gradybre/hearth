import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../foods/food_draft.dart';
import 'match_review_controller.dart';

/// Reviews what the nutrition sources made of a recipe's ingredients
/// (spec §5.3's match review screen).
///
/// The workhorse: each row says which food was chosen, where it came from,
/// which serving was used and what that works out to — because a match the
/// user cannot check is a macro they cannot trust. Nothing is written until
/// the whole list has been seen and applied (CLAUDE.md rule 4).
///
/// Returns the accepted matches, keyed by ingredient name.
Future<Map<String, String>?> showMatchReview(
  BuildContext context, {
  required List<ParsedIngredient> ingredients,
  List<AiEstimate> estimates = const <AiEstimate>[],
}) => Navigator.of(context).push<Map<String, String>>(
  MaterialPageRoute<Map<String, String>>(
    builder: (BuildContext context) =>
        _MatchReviewScreen(ingredients: ingredients, estimates: estimates),
  ),
);

class _MatchReviewScreen extends ConsumerStatefulWidget {
  const _MatchReviewScreen({
    required this.ingredients,
    this.estimates = const <AiEstimate>[],
  });

  final List<ParsedIngredient> ingredients;

  /// The model's own numbers, for lines the real chain cannot match
  /// (spec §5.4).
  final List<AiEstimate> estimates;

  @override
  ConsumerState<_MatchReviewScreen> createState() => _MatchReviewScreenState();
}

class _MatchReviewScreenState extends ConsumerState<_MatchReviewScreen> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(matchReviewProvider.notifier)
            .findMatches(widget.ingredients, estimates: widget.estimates);
      }
    });
  }

  /// Saves every accepted food into the library, then hands the matches back.
  ///
  /// The foods are saved here rather than earlier because until this moment
  /// they were only proposals. Each arrives through [FoodDraft.fromLookup], so
  /// it gets ids of this library's own and loses the source's spurious
  /// precision, exactly as a scanned food does.
  Future<void> _apply(MatchReviewReady ready) async {
    setState(() => _applying = true);
    try {
      final Map<String, String> matches = <String, String>{};
      for (final IngredientMatchRow row in ready.accepted) {
        final Food food = row.food != null
            ? FoodDraft.fromLookup(row.food!).toFood()
            : _foodFromEstimate(row);
        await ref.read(foodRepositoryProvider).save(food);
        matches[row.ingredient.name] = food.id;
      }
      if (mounted) Navigator.of(context).pop(matches);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// A food built from the model's own arithmetic, and labelled as such.
  ///
  /// [FoodSource.aiEstimate] is not decoration: it is what makes every later
  /// view of this food say "AI estimate", so a number nobody verified can
  /// never quietly pass for one that was (spec §5.4).
  ///
  /// The serving is the ingredient line itself, because that is what was
  /// estimated — "2 tbsp olive oil", not olive oil per 100 g.
  Food _foodFromEstimate(IngredientMatchRow row) {
    final AiEstimate estimate = row.estimate!;
    final Quantity amount =
        row.ingredient.quantity ?? Quantity.of(1, Units.item);

    return Food(
      id: const Uuid().v4(),
      name: row.ingredient.name,
      source: FoodSource.aiEstimate,
      servingOptions: <ServingOption>[
        ServingOption(
          id: const Uuid().v4(),
          label: QuantityFormat.formatAsAuthored(amount),
          amount: amount,
          macros: Macros(
            kcal: estimate.kcal,
            proteinG: estimate.proteinG,
            carbG: estimate.carbG,
            fatG: estimate.fatG,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final MatchReviewState state = ref.watch(matchReviewProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        // Short enough to sit beside "Use these" without truncating to
        // "Check the mat…".
        title: Text('Matches', style: context.text.sectionHeader),
        leading: TextButton(
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        actions: <Widget>[
          if (state is MatchReviewReady)
            Padding(
              padding: const EdgeInsets.only(right: HearthSpacing.sm),
              child: FilledButton(
                onPressed: _applying ? null : () => _apply(state),
                child: Text(_applying ? 'Saving…' : 'Use these'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          MatchReviewIdle() => const Center(child: CircularProgressIndicator()),
          MatchReviewSearching(:final int done, :final int total) => _Progress(
            done: done,
            total: total,
          ),
          MatchReviewReady(:final List<IngredientMatchRow> rows) =>
            rows.isEmpty
                ? Center(
                    child: Text(
                      'Nothing here needs a match.',
                      style: context.text.body,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.all(gutter),
                    children: <Widget>[
                      _Summary(state: state),
                      const SizedBox(height: HearthSpacing.lg),
                      for (int i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: HearthSpacing.sm,
                          ),
                          child: _MatchRow(
                            row: rows[i],
                            onChanged: (bool value) => ref
                                .read(matchReviewProvider.notifier)
                                .setAccepted(i, accepted: value),
                          ),
                        ),
                    ],
                  ),
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: HearthSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            'Looking up $done of $total',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final MatchReviewReady state;

  @override
  Widget build(BuildContext context) {
    final int found = state.foundCount;
    final int total = state.rows.length;
    final int unsure = state.rows
        .where((IngredientMatchRow r) => r.isAmbiguous)
        .length;

    final int ready = found - unsure;

    // Leads with what is actually ready to use, not with what was merely
    // found: "Found all 2" above two unticked toss-ups reads as a success the
    // screen immediately takes back.
    final String headline = switch ((found, ready)) {
      (0, _) => 'Nothing found.',
      (_, 0) => 'Nothing certain enough to tick.',
      _ when ready == total => 'All $total matched.',
      _ => '$ready of $total matched.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(headline, style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          unsure == 0
              ? 'Untick anything that looks wrong. Whatever is left unmatched '
                    'is fine — the recipe saves either way.'
              : '$unsure ${unsure == 1 ? 'is a toss-up' : 'are toss-ups'} and '
                    'left unticked. Tick one only if it is right.',
          style: context.text.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One ingredient, and what it was matched to.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.row, required this.onChanged});

  final IngredientMatchRow row;
  final ValueChanged<bool> onChanged;

  String get _sourceLabel => switch (row.food?.source) {
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.usda => 'USDA',
    FoodSource.manual => 'Your library',
    FoodSource.aiEstimate => 'AI estimate',
    null => '',
  };

  /// What the match actually works out to for this line.
  ///
  /// The number is the point: a plausible food name attached to the wrong
  /// serving is exactly the error this screen exists to catch.
  String _macrosLine(BuildContext context) {
    final Food? food = row.food;
    if (food == null) return '';

    final IngredientMacros computed = MacroCalculator.forIngredient(
      RecipeIngredient(
        id: 'preview',
        sectionId: 'preview',
        name: row.ingredient.name,
        sortOrder: 0,
        quantity: row.ingredient.quantity,
      ),
      food: food,
    );

    return switch (computed.status) {
      IngredientMacroStatus.resolved =>
        '${computed.macros.kcal.round()} kcal · '
            '${computed.macros.proteinG.round()} g protein',
      IngredientMacroStatus.noQuantity => 'No amount on the line',
      IngredientMacroStatus.unconvertible =>
        'Cannot convert ${row.ingredient.quantity == null ? '' : QuantityFormat.formatAsAuthored(row.ingredient.quantity!)} '
            'to this food\'s servings',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Food? food = row.food;

    if (food == null) {
      return row.estimate == null
          ? _NoMatchRow(ingredient: row.ingredient.name)
          : _EstimateRow(row: row, onChanged: onChanged);
    }

    final String macros = _macrosLine(context);
    final ServingOption? serving = food.defaultServing;

    return Semantics(
      checked: row.accepted,
      label:
          '${row.ingredient.name}, matched to ${food.name} from $_sourceLabel. '
          '$macros.'
          '${row.isAmbiguous ? ' Uncertain — several foods fit equally well.' : ''}',
      onTap: () => onChanged(!row.accepted),
      excludeSemantics: true,
      child: Material(
        color: row.accepted ? colors.surface : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => onChanged(!row.accepted),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: row.accepted ? colors.outlineStrong : colors.outline,
              ),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  row.accepted
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: row.accepted ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.ingredient.raw.trim().isEmpty
                            ? row.ingredient.name
                            : row.ingredient.raw.trim(),
                        style: context.text.ingredient,
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.arrow_right_alt,
                            size: 16,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: HearthSpacing.xxs),
                          Expanded(
                            child: Text(
                              food.brand == null
                                  ? food.name
                                  : '${food.name} · ${food.brand}',
                              style: context.text.metadata.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Text(
                        <String>[
                          _sourceLabel,
                          if (serving != null) 'per ${serving.label}',
                          if (macros.isNotEmpty) macros,
                        ].join(' · '),
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (row.isAmbiguous) ...<Widget>[
                        const SizedBox(height: HearthSpacing.xs),
                        Row(
                          children: <Widget>[
                            // Never colour alone (§6.3).
                            Icon(
                              Icons.help_outline,
                              size: 14,
                              color: colors.error,
                            ),
                            const SizedBox(width: HearthSpacing.xxs),
                            Expanded(
                              child: Text(
                                'Several fit equally well — check this one',
                                style: context.text.metadata.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

/// An ingredient nothing was found for.
///
/// Not an error and not a blocker: §5.3 is explicit that missing data never
/// stops a save. The recipe carries an incomplete flag instead, and the line
/// can be matched by hand whenever the user cares to.
class _NoMatchRow extends StatelessWidget {
  const _NoMatchRow({required this.ingredient});

  final String ingredient;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.remove, size: 20, color: colors.textMuted),
          const SizedBox(width: HearthSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(ingredient, style: context.text.ingredient),
                const SizedBox(height: HearthSpacing.xxs),
                Text(
                  'Nothing found. Match it yourself, or leave it.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A line only the model has a number for (spec §5.4).
///
/// Offered because a rough number that admits to being rough beats a silent
/// zero — but unticked, described as a guess, and saved with a source that
/// makes every later view of it say so. It is the weakest thing on this
/// screen and is dressed accordingly.
class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.row, required this.onChanged});

  final IngredientMatchRow row;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AiEstimate estimate = row.estimate!;

    return Semantics(
      checked: row.accepted,
      label:
          '${row.ingredient.name}. Nothing found in a real database. '
          'Hearth\'s own estimate is ${estimate.kcal.round()} calories. '
          'Not verified.',
      onTap: () => onChanged(!row.accepted),
      excludeSemantics: true,
      child: Material(
        color: row.accepted ? colors.surface : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => onChanged(!row.accepted),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: row.accepted ? colors.outlineStrong : colors.outline,
              ),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  row.accepted
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: row.accepted ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.ingredient.raw.trim().isEmpty
                            ? row.ingredient.name
                            : row.ingredient.raw.trim(),
                        style: context.text.ingredient,
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Text(
                        'Nothing found in a real database · '
                        'about ${estimate.kcal.round()} kcal',
                        style: context.text.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: HearthSpacing.xs),
                      Row(
                        children: <Widget>[
                          // Never colour alone (§6.3), and the words say what
                          // the badge will say later.
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 14,
                            color: colors.error,
                          ),
                          const SizedBox(width: HearthSpacing.xxs),
                          Expanded(
                            child: Text(
                              'Hearth\'s own guess — saved as an estimate, '
                              'never as fact',
                              style: context.text.metadata.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
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
