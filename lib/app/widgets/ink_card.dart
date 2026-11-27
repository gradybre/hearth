import 'package:flutter/material.dart';

import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';

/// A card drawn on Hearth's one dark surface (spec §6.1, the November 2026
/// templates).
///
/// The day's summary is the loudest thing on the logging screen, and loudness
/// in a two-tone palette is a change of ground rather than another colour.
/// Against paper this inverts; against the near-black of dark mode it lifts.
/// Both are the same card.
///
/// **It swaps the theme for its subtree, and that is the whole mechanism.**
/// Everything inside — the macro rings, the minor-nutrient bars, a
/// `TextButton`, a `LinearProgressIndicator` — already resolves its colours
/// from the ambient [HearthColors]. Handing the subtree [HearthTheme.ink] is
/// therefore the only change any of them needs, and none of them grows an
/// `onInk` flag it would have to be passed correctly at every call site. The
/// same widgets go on being drawn on paper in the week view, unchanged.
///
/// Contrast inside is not taken on trust: `contrast_test.dart` puts the ink
/// palette through every pair it puts the light and dark palettes through,
/// and the §6.3 sweep measures the painted pixels on the real screen.
class InkCard extends StatelessWidget {
  const InkCard({required this.child, this.padding, super.key});

  final Widget child;

  /// Defaults to the same inset [_Card] uses on the day screen, so a card
  /// that changes ground does not also change size.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final HearthColors ink = HearthColors.ink();
    return Theme(
      data: HearthTheme.ink(),
      // A [Material], not a painted box: the readouts inside are `InkWell`s,
      // and an ink splash looks for the nearest Material to paint itself on.
      // Without one here it would find the Scaffold, behind the card, and
      // every tap on a total would ripple somewhere the card is not.
      child: Material(
        color: ink.background,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HearthRadius.lg),
            // A border even here. Against paper the ground does all the work,
            // but in dark mode the card is only 1.34:1 above the page and a
            // hairline is the difference between a card and a smudge.
            border: Border.all(color: ink.outline),
          ),
          padding: padding ?? const EdgeInsets.all(HearthSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}
