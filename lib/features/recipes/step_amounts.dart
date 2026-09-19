import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/food_quantity_format.dart';
import '../../domain/models/food.dart';
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
///
/// [forCooking] switches between two presentations of the exact same matched,
/// scaled ingredients (never a second matching pass — see
/// [StepIngredients.forStep]):
///
/// * Default (`false`, used by recipe details and the All-steps view): the
///   original compact single line — a small ruler icon, muted 12pt metadata
///   type, dot-separated. Unchanged from before this panel existed.
/// * `true` (focused cook cards only): a full-width warm "For this step"
///   panel below the direction text, per the Hearth cooking-ingredients plan
///   (loop/cook-ingredients-v1/PLAN-v2.md, D7 in APPROVAL.md). Each matched
///   ingredient gets its own quantity-first line, wrapping naturally rather
///   than truncating.
class StepAmounts extends StatelessWidget {
  const StepAmounts({
    required this.step,
    required this.section,
    this.recipe,
    this.forCooking = false,
    this.foods,
    super.key,
  });

  final RecipeStep step;

  /// The step's own section, which is where its amounts come from first. Two
  /// teaspoons in the sauce and two in the rub must read as two in each place.
  final RecipeSection section;

  /// The rest of the recipe, so a step can still find an ingredient an import
  /// filed under a different heading — but only where that name appears in
  /// one section and cannot be ambiguous.
  final Recipe? recipe;

  /// Use the focused-cook "For this step" panel instead of the default
  /// compact metadata line. Defaults to `false`, which is the presentation
  /// recipe details and the All-steps view keep using.
  final bool forCooking;

  /// The household's food library, keyed by id, for the matched-food mass
  /// display preference and pack size (spec R1–R8) — one snapshot passed
  /// down from the screen rather than fetched per row. Null is read the same
  /// as "no match", which formats with the conservative default.
  final Map<String, Food>? foods;

  /// The focused-card ingredient row size.
  ///
  /// D7 (loop/cook-ingredients-v1/APPROVAL.md): 22 is the initial candidate,
  /// not a locked token. Astra and an independent visual reviewer compare it
  /// against the 26pt instruction, the 18pt panel heading and 18pt action
  /// labels on actual Flutter captures, and may move it within 20–24 after
  /// reviewing hierarchy, spacing, wrapping and small-screen readability.
  /// Kept as one named constant so that adjustment is a one-line change.
  /// Accessibility text scaling is not capped by this value — it is an
  /// ordinary `fontSize` on a `Text` widget under the ambient `MediaQuery`.
  static const double _cookingIngredientFontSize = 22;

  @override
  Widget build(BuildContext context) {
    final List<RecipeIngredient> used = StepIngredients.forStep(
      step,
      section,
      elsewhere: recipe?.sections ?? const <RecipeSection>[],
    );
    if (used.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;

    if (forCooking) return _buildPanel(context, colors, used);
    return _buildCompact(context, colors, used);
  }

  /// The original compact line: recipe details and the All-steps view.
  Widget _buildCompact(
    BuildContext context,
    HearthColors colors,
    List<RecipeIngredient> used,
  ) {
    // `format`, not `formatAsAuthored`. The latter exists for surfaces showing
    // somebody their own typing back — an editor's parse preview — and its own
    // doc says reading surfaces honour the reader's units instead. This is the
    // reading surface: a step saying "16 oz" beside a list saying "1 lb" makes
    // a cook stop and work out whether those are the same number.
    final String line = used
        .map(
          (RecipeIngredient i) =>
              '${FoodQuantityFormat.format(i.quantity!, food: foods?[i.foodId], rawSources: [i.rawText ?? ''])} '
              '${i.name}',
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

  /// The focused-card "For this step" panel.
  ///
  /// The 24pt gap above the panel lives in this outer [Padding] rather than
  /// in the caller, so it only ever appears alongside the panel itself: an
  /// empty match returns [SizedBox.shrink] above and never reaches here, so
  /// there is no reserved gap for zero matched ingredients (R3).
  ///
  /// Deliberately outside any `excludeSemantics` ancestor in
  /// `cook_along_screen.dart`'s focused card, so each ingredient line is its
  /// own reachable piece of content rather than being folded into the
  /// instruction's single "tap to go on" announcement (R5).
  Widget _buildPanel(
    BuildContext context,
    HearthColors colors,
    List<RecipeIngredient> used,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: HearthSpacing.xl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(HearthSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          border: Border.all(color: colors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'For this step',
              style: context.text.label.copyWith(
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: HearthSpacing.sm),
            for (int i = 0; i < used.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: HearthSpacing.sm),
              Text(
                // Quantity first, amount and name kept together on one line
                // rather than a rigid amount column — a fixed-width column
                // is the thing that breaks on a small phone.
                '${FoodQuantityFormat.format(used[i].quantity!, food: foods?[used[i].foodId], rawSources: [used[i].rawText ?? ''])} '
                '${used[i].name}',
                style: context.text.ingredient.copyWith(
                  fontSize: _cookingIngredientFontSize,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
