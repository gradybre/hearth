import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/step_ingredients.dart';

/// How much of each ingredient a step uses, shown beside the step.
///
/// The amount lives at the top of the recipe and the instruction lives at the
/// bottom, so cooking from one means scrolling between them with messy hands.
/// This puts the number where it is needed.
///
/// Written underneath the step rather than spliced into it: the step is what
/// the author wrote, and rewriting someone's sentence to inject a number is
/// how "brown the 2 lbs ground beef" happens. A separate line reads as the
/// reference it is, and stays right when the recipe is scaled — the
/// quantities come from the scaled ingredients, not from the text.
class StepAmounts extends StatelessWidget {
  const StepAmounts({required this.step, required this.section, super.key});

  final RecipeStep step;

  /// The step's own section — never the whole recipe. Two teaspoons in the
  /// sauce and two in the rub must read as two in each place.
  final RecipeSection section;

  @override
  Widget build(BuildContext context) {
    final List<RecipeIngredient> used = StepIngredients.forStep(step, section);
    if (used.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    final String line = used
        .map(
          (RecipeIngredient i) =>
              '${QuantityFormat.formatAsAuthored(i.quantity!)} ${i.name}',
        )
        .join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(top: HearthSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.straighten, size: 13, color: colors.textMuted),
          const SizedBox(width: HearthSpacing.xs),
          Expanded(
            child: Text(
              line,
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
