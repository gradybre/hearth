import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/recipes/recipe_scaler.dart';

/// The scale control on a recipe (spec §5.2).
///
/// Target servings is the primary control — "I want 6" is the thought a cook
/// actually has — with multipliers offered beside it for the times the thought
/// is "double this". Both drive the same factor underneath.
class ScaleControl extends StatelessWidget {
  const ScaleControl({
    required this.originalServings,
    required this.targetServings,
    required this.onChanged,
    super.key,
  });

  final double originalServings;
  final double targetServings;
  final ValueChanged<double> onChanged;

  /// Multipliers worth one tap. Halving and doubling are the two a cook
  /// reaches for; anything else is faster through the stepper.
  static const List<double> multipliers = <double>[0.5, 2, 3];

  double get factor =>
      originalServings <= 0 ? 1 : targetServings / originalServings;

  bool get isScaled => (factor - 1).abs() > 1e-9;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isScaled ? colors.surfaceSunken : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(
          color: isScaled ? colors.outlineStrong : colors.outline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // The value lives in the stepper, so the label is just the
                // label — "Makes 8" beside a stepper reading 8 says it twice.
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: 'Makes ${_servings(targetServings)} servings',
                    excludeSemantics: true,
                    child: Text('Makes', style: context.text.label),
                  ),
                ),
                _Step(
                  icon: Icons.remove_circle_outline,
                  label: 'One fewer serving',
                  // Never below one: a recipe that makes nothing is not a
                  // scale, it is a mistake.
                  onPressed: targetServings > 1
                      ? () => onChanged(
                          (targetServings - 1).clamp(1, double.infinity),
                        )
                      : null,
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    _servings(targetServings),
                    textAlign: TextAlign.center,
                    style: context.text.ingredient.copyWith(fontSize: 20),
                  ),
                ),
                _Step(
                  icon: Icons.add_circle_outline,
                  label: 'One more serving',
                  onPressed: () => onChanged(targetServings + 1),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.sm),
            Row(
              children: <Widget>[
                for (final double multiplier in multipliers)
                  _Multiplier(
                    label: '${QuantityFormat.count(multiplier)}×',
                    selected: (factor - multiplier).abs() < 1e-9,
                    onTap: () => onChanged(originalServings * multiplier),
                  ),
                const Spacer(),
                if (isScaled)
                  TextButton(
                    onPressed: () => onChanged(originalServings),
                    child: const Text('Reset'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _servings(double value) => QuantityFormat.count(value);
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    tooltip: label,
    onPressed: onPressed,
    color: context.colors.accent,
  );
}

class _Multiplier extends StatelessWidget {
  const _Multiplier({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: HearthSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Scale by $label',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: HearthTouch.minTarget,
                minHeight: HearthTouch.minTarget,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: selected ? colors.accent : colors.outline,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.md),
              child: Text(
                label,
                style: context.text.label.copyWith(
                  color: selected ? colors.onAccent : colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What scaling deliberately did not do for you (spec §5.2).
///
/// Flagged, never auto-adjusted: salt, leavening, and cook times do not follow
/// a multiplier, and quietly tripling the baking powder would ruin the dish
/// more surely than saying nothing.
class ScalingNotes extends StatelessWidget {
  const ScalingNotes({required this.warnings, super.key});

  final List<ScalingWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final HearthColors colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: Text(
                    'Check these yourself',
                    style: context.text.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.sm),
            for (final ScalingWarning warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
                child: Text(
                  _describe(warning),
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _describe(ScalingWarning warning) => switch (warning.kind) {
    ScalingWarningKind.seasoning =>
      '${warning.subject} — season to taste rather than by the multiplier.',
    ScalingWarningKind.leavening =>
      '${warning.subject} — leavening does not scale in a straight line.',
    ScalingWarningKind.cookTime =>
      'Timings are unchanged — cook time follows pan size and volume, '
          'not the multiplier.',
  };
}
