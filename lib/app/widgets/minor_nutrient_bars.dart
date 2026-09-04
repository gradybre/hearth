import 'package:flutter/material.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../a11y/accessibility.dart';
import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import '../theme/hearth_typography.dart';

/// Fibre, sodium and cholesterol against their targets (spec §5.6).
///
/// Bars rather than rings, and deliberately quieter than the four above them.
/// Rings are for the macros, calories loudest of all; giving these the same
/// weight would say they matter as much, which is not what Brendan asked for
/// and not what the spec says.
///
/// **The three do not point the same way, and the bars say so.** Fibre fills
/// towards something worth reaching. Sodium and cholesterol fill a budget, and
/// filling one is the thing you were trying not to do. That is
/// [MinorNutrient.isFloor], and it is the whole reason this is not four more
/// identical rows.
///
/// Draws nothing when nothing logged knows any of them — which today is most
/// days, since only restaurant foods and newly-looked-up ones carry the
/// numbers. Three rows of dashes would be worse than an absence.
class MinorNutrientBars extends StatelessWidget {
  const MinorNutrientBars({required this.progress, super.key});

  final DayProgress progress;

  @override
  Widget build(BuildContext context) {
    final List<MinorProgress> known = progress.knownMinor;
    if (known.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final MinorProgress nutrient in known) ...<Widget>[
          _Bar(nutrient: nutrient),
          if (nutrient != known.last) const SizedBox(height: HearthSpacing.sm),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.nutrient});

  final MinorProgress nutrient;

  /// Thinner than a macro's. The difference in weight is the point.
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final MinorNutrient kind = nutrient.nutrient;

    final Color fill = switch (nutrient.tone) {
      MacroTone.neutral => colors.textMuted,
      MacroTone.good => colors.goodAccent,
      MacroTone.over => colors.overAccent,
    };

    // Never colour alone (§6.3). A filled bar and a warm colour say the same
    // thing twice to somebody who can see both and nothing at all to anybody
    // else, so the state is also a word.
    final TargetIndicator? indicator = switch (nutrient.tone) {
      MacroTone.neutral => null,
      // Only a floor is ever good — a ceiling is neutral until it is over —
      // so this is always "on target" and never the bare word "left".
      MacroTone.good => TargetIndicator.forState(TargetState.met),
      MacroTone.over => TargetIndicator.forState(
        TargetState.over,
        amount:
            '${nutrient.consumed.round() - nutrient.target.round()} '
            '${kind.unit}',
      ),
    };

    final String amounts =
        '${nutrient.consumed.round()} of ${nutrient.target.round()} '
        '${kind.unit}';

    return Semantics(
      // One sentence for the row, so a screen reader is not read a label, a
      // number and a bar as three separate things.
      label:
          '${kind.label}, $amounts.'
          '${indicator == null ? '' : ' ${indicator.semanticLabel}'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  kind.label,
                  style: text.metadata.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                amounts,
                style: text.metadata.copyWith(color: colors.textMuted),
              ),
              if (indicator case final TargetIndicator flag) ...<Widget>[
                const SizedBox(width: HearthSpacing.xs),
                Icon(flag.icon, size: 12, color: fill),
                const SizedBox(width: HearthSpacing.xxs),
                Text(
                  flag.shortLabel,
                  style: text.metadata.copyWith(color: fill),
                ),
              ],
            ],
          ),
          const SizedBox(height: HearthSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(_height),
            child: LinearProgressIndicator(
              value: nutrient.barFill,
              minHeight: _height,
              backgroundColor: colors.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(fill),
            ),
          ),
        ],
      ),
    );
  }
}
