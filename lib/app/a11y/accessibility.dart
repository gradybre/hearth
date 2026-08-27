import 'package:flutter/material.dart';

/// Accessibility helpers backing the §6.3 baseline.
///
/// The baseline is not optional and not a late pass: dynamic type is honoured,
/// motion respects the OS setting, and meaning is never carried by colour
/// alone.
abstract final class A11y {
  /// True when the OS asks for reduced motion.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// An animation duration that collapses to zero when the user has asked for
  /// reduced motion. Use this instead of a bare [Duration] everywhere.
  static Duration motion(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;

  /// The layout-relevant text scale factor.
  static double scaleOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(100) / 100;

  /// Above this scale, multi-column numeric layouts must reflow to fewer
  /// columns rather than shrink or clip.
  ///
  /// This is how Hearth keeps dynamic type *honoured* while protecting the
  /// macro dashboard: the numbers keep growing, and the grid gives way around
  /// them. Capping the scale instead would fail exactly the person the feature
  /// exists for.
  static const double reflowThreshold = 1.4;

  /// A second threshold, past which even two columns won't fit and the macros
  /// stack into full-width rows.
  static const double stackThreshold = 2.0;

  /// Width at or above which four macros fit across at default text size.
  ///
  /// Below it, a 36pt readout in a quarter-width column wraps mid-number —
  /// "1,847" breaking across two lines — so a phone starts at two columns.
  static const double fourColumnWidth = 600;

  /// How many columns a four-macro row should use.
  ///
  /// Driven by available width *and* text scale: the phone starts narrower,
  /// and either axis can force a further reflow. The numbers never shrink and
  /// are never clipped — the grid gives way around them.
  static int macroColumns(BuildContext context, {double? availableWidth}) {
    final double width = availableWidth ?? MediaQuery.sizeOf(context).width;
    final double scale = scaleOf(context);

    int columns = width >= fourColumnWidth ? 4 : 2;
    if (scale >= reflowThreshold) columns = columns ~/ 2;
    if (scale >= stackThreshold) columns = 1;
    return columns.clamp(1, 4);
  }
}

/// Which side of a target a value sits on, expressed so it can be spoken and
/// drawn with an icon — never colour alone (spec §6.3).
enum TargetState { under, met, over }

/// The icon and words that carry an over/under state without relying on hue.
@immutable
class TargetIndicator {
  const TargetIndicator({
    required this.icon,
    required this.shortLabel,
    required this.semanticLabel,
  });

  factory TargetIndicator.forState(TargetState state, {String? amount}) =>
      switch (state) {
        TargetState.under => TargetIndicator(
          icon: Icons.arrow_downward,
          shortLabel: amount == null ? 'left' : '$amount left',
          semanticLabel: amount == null
              ? 'Under target.'
              : 'Under target, $amount left.',
        ),
        TargetState.met => const TargetIndicator(
          icon: Icons.check,
          shortLabel: 'on target',
          semanticLabel: 'On target.',
        ),
        TargetState.over => TargetIndicator(
          icon: Icons.arrow_upward,
          shortLabel: amount == null ? 'over' : '$amount over',
          semanticLabel: amount == null
              ? 'Over target.'
              : 'Over target by $amount.',
        ),
      };

  final IconData icon;
  final String shortLabel;
  final String semanticLabel;
}
