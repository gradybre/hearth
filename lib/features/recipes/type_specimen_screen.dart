import 'package:flutter/material.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/parsing/direction_parser.dart';

/// A temporary screen showing the real type and colour tokens on realistic
/// content, so the design language can be judged in context rather than on a
/// spec sheet.
///
/// This is scaffolding for the theme decision, not the Recipes feature. It is
/// replaced by the real recipe library in Step 5.
class TypeSpecimenScreen extends StatelessWidget {
  const TypeSpecimenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(gutter),
        children: <Widget>[
          Text('Braised Short Ribs', style: text.recipeTitle),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'Serves 4  ·  30 min prep  ·  3 hr cook',
            style: text.metadata.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: HearthSpacing.xl),
          _MacroRow(),
          const SizedBox(height: HearthSpacing.xl),
          Text('Sauce', style: text.sectionHeader),
          const SizedBox(height: HearthSpacing.md),
          const _Ingredient(amount: '2 tbsp', name: 'olive oil'),
          const _Ingredient(amount: '1½ cups', name: 'dry red wine'),
          const _Ingredient(amount: '3 cloves', name: 'garlic', prep: 'minced'),
          const _Ingredient(amount: '400 g', name: 'crushed tomatoes'),
          const _Ingredient(
            amount: '¼ tsp',
            name: 'black pepper',
            optional: true,
          ),
          const SizedBox(height: HearthSpacing.xl),
          Text('Directions', style: text.sectionHeader),
          const SizedBox(height: HearthSpacing.md),
          const _Directions(
            'Season the ribs generously and sear them in a heavy pot until '
            'deeply browned on every side. Lower the heat and add the '
            'aromatics. Pour in 1.5 cups of dry red wine and scrape up the '
            'browned bits. Cover and cook for approx. 3 hr. Serve over '
            'polenta.',
          ),
        ],
      ),
    );
  }
}

/// The four tracked macros. Reflows to fewer columns as text scales up, so the
/// numbers keep growing instead of being capped (spec §6.3).
class _MacroRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    const List<(String, String, double, TargetState)> macros =
        <(String, String, double, TargetState)>[
          ('1,847', 'kcal', 0.84, TargetState.under),
          ('142', 'protein', 0.79, TargetState.under),
          ('186', 'carbs', 1.12, TargetState.over),
          ('61', 'fat', 0.87, TargetState.under),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = A11y.macroColumns(
              context,
              availableWidth: constraints.maxWidth,
            );
            // Each tile sizes to its own content height rather than to a
            // guessed aspect ratio, so a larger text scale makes the tiles
            // taller instead of clipping the number inside them.
            const double spacing = HearthSpacing.md;
            final double itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: <Widget>[
                for (final (
                      String value,
                      String label,
                      double fill,
                      TargetState s,
                    )
                    in macros)
                  SizedBox(
                    width: itemWidth,
                    child: _Macro(
                      value: value,
                      label: label,
                      fill: fill,
                      state: s,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({
    required this.value,
    required this.label,
    required this.fill,
    required this.state,
  });

  final String value;
  final String label;
  final double fill;
  final TargetState state;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final TargetIndicator indicator = TargetIndicator.forState(state);
    final Color barColor = state == TargetState.over
        ? colors.overAccent
        : colors.accent;

    return Semantics(
      label: '$label $value. ${indicator.semanticLabel}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value, style: text.macroReadout),
          const SizedBox(height: HearthSpacing.xxs),
          Row(
            children: <Widget>[
              // The state is carried by an icon and a word as well as colour —
              // never colour alone (spec §6.3).
              Icon(indicator.icon, size: 14, color: colors.textMuted),
              const SizedBox(width: HearthSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  style: text.metadata.copyWith(color: colors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(HearthRadius.sm),
            child: LinearProgressIndicator(
              value: fill.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ingredient extends StatelessWidget {
  const _Ingredient({
    required this.amount,
    required this.name,
    this.prep,
    this.optional = false,
  });

  final String amount;
  final String name;
  final String? prep;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Fixed column so quantities line up down the list — this is what
          // tabular figures are for.
          SizedBox(width: 92, child: Text(amount, style: text.ingredient)),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: name, style: text.ingredient),
                  if (prep != null)
                    TextSpan(
                      text: ', $prep',
                      style: text.ingredient.copyWith(color: colors.textMuted),
                    ),
                  if (optional)
                    TextSpan(
                      text: '  optional',
                      style: text.metadata.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Directions rendered as numbered steps.
///
/// Prose is run through [DirectionParser] rather than shown as a paragraph:
/// structured steps are what cook-along walks through one card at a time, and
/// a numbered list is far easier to hold your place in with messy hands
/// (spec §5.2).
class _Directions extends StatelessWidget {
  const _Directions(this.prose);

  final String prose;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final ParsedDirections parsed = DirectionParser.parse(prose);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ParsedStep step in parsed.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: HearthSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Text(
                    '${step.number}.',
                    style: text.ingredient.copyWith(color: colors.accent),
                  ),
                ),
                Expanded(
                  child: Text(
                    step.text,
                    style: text.body.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
