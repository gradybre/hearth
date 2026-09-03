import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/models/macros.dart';

/// Calories, protein, carbs, and fat, side by side — the one nutrition
/// glance every screen showing a recipe's numbers uses (spec §5.2).
///
/// Deliberately just the four-column row and nothing else: the recipe
/// editor's review card, the detail screen's reading view, and the library
/// list's compact card each wrap this in whatever chrome fits their own
/// look, rather than sharing a card style that would fit none of them well.
class MacroStatsRow extends StatelessWidget {
  const MacroStatsRow({required this.macros, super.key});

  final Macros macros;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Row(
      children: <Widget>[
        for (final (String label, double value) in <(String, double)>[
          ('kcal', macros.kcal),
          ('protein', macros.proteinG),
          ('carbs', macros.carbG),
          ('fat', macros.fatG),
        ])
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value.round().toString(),
                  style: text.ingredient.copyWith(fontSize: 20),
                ),
                Text(
                  label,
                  style: text.metadata.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The same four numbers as one line of text — "420 kcal · 32g protein · 18g
/// carbs · 22g fat" — for a place with room for a summary line but not a
/// four-column block, like a card in a recipe list.
class MacroStatsLine extends StatelessWidget {
  const MacroStatsLine({
    required this.macros,
    this.isPartial = false,
    super.key,
  });

  final Macros macros;

  /// Whether something the recipe contains is missing from these numbers.
  ///
  /// Marked rather than hidden: a total that quietly undercounts is the worse
  /// failure, but so is a recipe whose nutrition vanishes entirely over one
  /// unresolved line. The word "partial" is what makes showing it honest, and
  /// it is a word rather than a colour (spec §6.3).
  final bool isPartial;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String line = <String>[
      '${macros.kcal.round()} kcal',
      '${macros.proteinG.round()}g protein',
      '${macros.carbG.round()}g carbs',
      '${macros.fatG.round()}g fat',
      if (isPartial) 'partial',
    ].join('  ·  ');

    return Text(
      line,
      style: context.text.metadata.copyWith(color: colors.textMuted),
    );
  }
}

/// The three minor nutrients as one quiet line, or nothing at all.
///
/// Nothing at all is the common case and the right one: a food nobody has
/// told Hearth about has no fibre to report, and an empty "Fibre —" would be
/// a row of dashes on most recipes (spec §5.6).
///
/// [partialFor] names, per nutrient, how much of the total was actually seen.
/// A partial total looks exactly like a whole one, which is how "12 g fibre"
/// off half a recipe becomes a number somebody trusts.
class MinorNutrientsLine extends StatelessWidget {
  const MinorNutrientsLine({required this.macros, this.partialFor, super.key});

  final Macros macros;

  /// Null where the caller has no notion of partial totals — a single food's
  /// serving is either known or not.
  final String? Function(MinorNutrient)? partialFor;

  @override
  Widget build(BuildContext context) {
    final List<MinorNutrient> known = <MinorNutrient>[
      for (final MinorNutrient n in MinorNutrient.values)
        if (macros.knows(n)) n,
    ];
    if (known.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    final List<String> caveats = <String>[
      for (final MinorNutrient n in known)
        if (partialFor?.call(n) case final String note) '${n.label}: $note',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          <String>[
            for (final MinorNutrient n in known)
              '${n.label} ${_number(macros.minor(n)!)} ${n.unit}',
          ].join('  ·  '),
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        if (caveats.isNotEmpty) ...<Widget>[
          const SizedBox(height: HearthSpacing.xxs),
          Text(
            caveats.join('  ·  '),
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  /// Whole numbers, except where rounding would erase the value entirely.
  ///
  /// The four macros round flat, which is fine at their magnitudes. Half a
  /// gram of fibre rounding to "0 g" would report the opposite of the truth,
  /// so anything under ten keeps a decimal.
  static String _number(double value) {
    if (value >= 10 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}
