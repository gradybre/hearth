import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
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
