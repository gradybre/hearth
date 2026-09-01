import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/macros.dart';
import '../../domain/planning/day_progress.dart';
import '../a11y/accessibility.dart';
import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import '../theme/hearth_typography.dart';

/// A day's four macros, each as a ring against its target (spec §5.6).
///
/// One widget for the day view and the week view, so the same four numbers
/// cannot come to read two different ways on two screens.
///
/// A ring rather than a bar because the question is *how full is this*, and a
/// proportion is what a ring draws. That decides what goes in the middle of
/// it: the amount eaten, which is the thing the arc is a picture of. A bar can
/// lead with what is left because it is only a length; a ring cannot, without
/// the number and the drawing disagreeing.
///
/// What is left has not been dropped — it moved below the ring, where §6.3
/// requires words anyway:
///
///  * **Under target** says nothing. A part-filled ring already says it, and
///    "142 left" under all four rings every day is noise rather than news.
///  * **On or over** says so with an icon and a word, because that is the
///    state worth interrupting for, and colour must never be carrying it.
class MacroRings extends StatelessWidget {
  const MacroRings({required this.progress, super.key});

  final DayProgress progress;

  static const Map<MacroKind, String> _labels = <MacroKind, String>{
    MacroKind.calories: 'kCal',
    MacroKind.protein: 'Protein',
    MacroKind.carbs: 'Carbs',
    MacroKind.fat: 'Fat',
  };

  /// What a target is counted in, when it is not the macro's own word.
  static String unitFor(MacroKind kind) =>
      kind == MacroKind.calories ? 'kcal' : 'g';

  @override
  Widget build(BuildContext context) {
    final int columns = A11y.macroColumns(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = HearthSpacing.md;
        final double itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final MacroProgress macro in progress.all)
              SizedBox(
                width: itemWidth,
                child: _MacroRing(macro: macro, maxWidth: itemWidth),
              ),
          ],
        );
      },
    );
  }
}

class _MacroRing extends StatelessWidget {
  const _MacroRing({required this.macro, required this.maxWidth});

  final MacroProgress macro;
  final double maxWidth;

  /// The ring's diameter at default text size.
  ///
  /// Sized around the numbers rather than chosen for looks: a 36pt readout
  /// with a line under it needs about 70pt of clear space inside the arc, and
  /// anything smaller clips one of them.
  static const double _baseDiameter = 104;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    final TargetState state = switch (macro.state) {
      MacroProgressState.under => TargetState.under,
      MacroProgressState.met => TargetState.met,
      MacroProgressState.over => TargetState.over,
    };
    final String eaten = macro.consumed.round().toString();
    // No unit inside the ring — the label above it already says which macro
    // this is, and the two words together would not fit without shrinking the
    // numbers, which is the one thing the dashboard never does. The spoken
    // label below keeps the unit.
    final String target = 'of ${macro.target.round()}';
    final String spokenTarget = '$target ${MacroRings.unitFor(macro.kind)}';

    // Grows with the type rather than staying put and clipping it. The columns
    // have already given way by the time the scale is large (see
    // A11y.macroColumns), so there is room for the ring to take.
    final double diameter = math.min(
      _baseDiameter * A11y.scaleOf(context),
      maxWidth,
    );

    final TargetIndicator? indicator = state == TargetState.under
        ? null
        : TargetIndicator.forState(
            state,
            amount: state == TargetState.over
                ? macro.remaining.abs().round().toString()
                : null,
          );

    return Semantics(
      label:
          '${MacroRings._labels[macro.kind]}: $eaten $spokenTarget'
          '${indicator == null ? '' : '. ${indicator.semanticLabel}'}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            MacroRings._labels[macro.kind]!,
            style: text.metadata.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: HearthSpacing.sm),
          SizedBox(
            width: diameter,
            height: diameter,
            child: CustomPaint(
              painter: _RingPainter(
                fill: macro.barFill,
                track: colors.progressTrack,
                // Colour reinforces the state; the icon and words below carry
                // it (§6.3).
                fillColor: macro.isOver ? colors.overAccent : colors.accent,
              ),
              child: Center(
                child: Padding(
                  // Keeps the numbers off the arc rather than shrinking them
                  // to fit inside it.
                  padding: EdgeInsets.all(diameter * 0.11),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        eaten,
                        style: text.macroReadout,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        target,
                        style: text.metadata.copyWith(color: colors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (indicator != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(indicator.icon, size: 14, color: colors.textMuted),
                const SizedBox(width: HearthSpacing.xxs),
                Flexible(
                  child: Text(
                    indicator.shortLabel,
                    style: text.metadata.copyWith(color: colors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The ring itself: a full track, and an arc over it from the top.
///
/// Deliberately not animated. The numbers move when a meal is logged, not
/// continuously, and an arc that sweeps into place is a moment spent watching
/// rather than reading — which is the wrong trade on the screen the app is
/// judged on (§6.3 also asks for motion to be earned).
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fill,
    required this.track,
    required this.fillColor,
  });

  /// 0..1, already clamped by [MacroProgress.barFill].
  final double fill;
  final Color track;
  final Color fillColor;

  /// Thick enough to read at arm's length on a worktop, thin enough to leave
  /// the numbers room.
  static const double _stroke = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Rect.fromLTWH(
      _stroke / 2,
      _stroke / 2,
      size.width - _stroke,
      size.height - _stroke,
    );

    canvas.drawArc(
      bounds,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );

    if (fill <= 0) return;
    canvas.drawArc(
      bounds,
      // From the top, clockwise — the direction a dial is read.
      -math.pi / 2,
      math.pi * 2 * fill,
      false,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fill != fill || old.fillColor != fillColor || old.track != track;
}
