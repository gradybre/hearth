import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/models/macros.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/week.dart';

/// One week, one row (spec §5.6).
///
/// Replaces seven tall rows with seven columns, which is the same week in a
/// glance and a tap rather than a scroll. Each date sits inside a ring showing
/// that day's calories against target, so the shape of the week is legible
/// before anything is tapped.
///
/// Monday first, which is Hearth's week and what [weekOf] builds.
///
/// Three things have to be told apart here, and none of them may lean on
/// colour (§6.3): which day is **selected** (an outline), which is **today**
/// (a bold letter — the same weight the day rows used), and which days have
/// anything in them (a dot).
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    required this.days,
    required this.selected,
    required this.eaten,
    required this.entryCounts,
    required this.targets,
    required this.onSelect,
    super.key,
  });

  final List<DateTime> days;
  final DateTime selected;
  final Map<DateTime, Macros> eaten;
  final Map<DateTime, int> entryCounts;
  final MacroTargets? targets;
  final ValueChanged<DateTime> onSelect;

  /// Initials, Monday first. Two of them repeat — the date beneath is what
  /// actually identifies a column, and the semantics label says the day in
  /// full.
  static const List<String> _initials = <String>[
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  static const List<String> _names = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: _DayColumn(
              day: days[i],
              initial: _initials[i],
              name: _names[i],
              eaten: eaten[days[i]] ?? Macros.zero,
              entryCount: entryCounts[days[i]] ?? 0,
              targets: targets,
              isSelected: days[i] == selected,
              onTap: () => onSelect(days[i]),
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.initial,
    required this.name,
    required this.eaten,
    required this.entryCount,
    required this.targets,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final String initial;
  final String name;
  final Macros eaten;
  final int entryCount;
  final MacroTargets? targets;
  final bool isSelected;
  final VoidCallback onTap;

  /// The ring around a date. Small — this is a navigator, not a readout.
  static const double _ring = 38;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool isToday = isSameDay(day, DateTime.now());
    final bool logged = !eaten.isZero;

    final MacroProgress? calories = targets == null
        ? null
        : DayProgress.from(consumed: eaten, targets: targets!).calories;

    return Semantics(
      button: true,
      selected: isSelected,
      onTap: onTap,
      label:
          '$name ${shortDate(day)}${isToday ? ', today' : ''}. '
          '${logged ? '${eaten.kcal.round()} calories logged' : 'nothing logged'}'
          '${entryCount > 0 ? ', $entryCount ${entryCount == 1 ? 'item' : 'items'}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: Container(
          // The whole column is the target, comfortably past the 44pt floor.
          constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
          padding: const EdgeInsets.symmetric(vertical: HearthSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HearthRadius.md),
            border: Border.all(
              color: isSelected ? colors.outlineStrong : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                initial,
                style: text.metadata.copyWith(
                  color: isToday ? colors.textPrimary : colors.textMuted,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: HearthSpacing.xs),
              SizedBox(
                width: _ring,
                height: _ring,
                child: CustomPaint(
                  painter: _DateRingPainter(
                    fill: calories?.barFill ?? 0,
                    track: colors.progressTrack,
                    // The same three tones the macro rings use, so a day reads
                    // the same in the strip as it does when opened. Colour is
                    // the only signal a 38pt ring has room for, which is why
                    // it is never the only one on the day itself.
                    fillColor: switch (calories?.tone) {
                      null || MacroTone.neutral => colors.accent,
                      MacroTone.good => colors.goodAccent,
                      MacroTone.over => colors.overAccent,
                    },
                  ),
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: text.metadata.copyWith(
                        color: colors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: HearthSpacing.xs),
              // A day with something in it, said with a mark rather than with
              // colour. An empty day gets the same space so the row does not
              // jump as days fill up.
              SizedBox(
                height: 6,
                child: entryCount > 0
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colors.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small ring behind a date.
///
/// The same idea as the macro rings and deliberately not the same widget: this
/// one is a hint at the shape of a day, thin enough to sit behind a numeral,
/// with no numbers of its own to make room for.
class _DateRingPainter extends CustomPainter {
  const _DateRingPainter({
    required this.fill,
    required this.track,
    required this.fillColor,
  });

  final double fill;
  final Color track;
  final Color fillColor;

  static const double _stroke = 2.5;

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
  bool shouldRepaint(covariant _DateRingPainter old) =>
      old.fill != fill || old.fillColor != fillColor || old.track != track;
}
