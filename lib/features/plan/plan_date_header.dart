import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/day_format.dart';

/// The planner's date and its existing actions, with room for enlarged text.
///
/// Keep this inside the screen's scroll view. The compact layout gives the
/// date its own line and spends no space repeating the selected Day view.
/// Callers own date changes, copying, and saved-week actions.
class PlanDateHeader extends StatelessWidget {
  const PlanDateHeader.day({
    required DateTime date,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required VoidCallback onCopy,
    this.today,
    super.key,
  }) : _firstDay = date,
       _lastDay = null,
       _onCopy = onCopy,
       _trailingAction = null;

  const PlanDateHeader.week({
    required DateTime firstDay,
    required DateTime lastDay,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required Widget trailingAction,
    this.today,
    super.key,
  }) : _firstDay = firstDay,
       _lastDay = lastDay,
       _onCopy = null,
       _trailingAction = trailingAction;

  final DateTime _firstDay;
  final DateTime? _lastDay;
  final VoidCallback? _onCopy;
  final Widget? _trailingAction;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  /// A calendar reference for relative headings and visible years.
  final DateTime? today;

  bool get _isWeek => _lastDay != null;

  static String _month(DateTime day) => monthName(day).substring(0, 3);

  static String _fullDate(DateTime day) =>
      '${weekdayName(day)}, ${monthName(day)} ${day.day}, ${day.year}';

  String _dateLabel(DateTime currentDay) {
    final DateTime from = _firstDay;
    final DateTime? to = _lastDay;
    if (to == null) {
      final String year = from.year == currentDay.year ? '' : ', ${from.year}';
      return '${shortWeekdayName(from)}, ${_month(from)} ${from.day}$year';
    }
    if (from.year != to.year) {
      return '${_month(from)} ${from.day}, ${from.year} – '
          '${_month(to)} ${to.day}, ${to.year}';
    }
    final String year = from.year == currentDay.year ? '' : ', ${from.year}';
    if (from.month == to.month) {
      return '${_month(from)} ${from.day}–${to.day}$year';
    }
    return '${_month(from)} ${from.day} – ${_month(to)} ${to.day}$year';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      final DateTime currentDay = today ?? DateTime.now();
      final String semantics = _isWeek
          ? '${_fullDate(_firstDay)} through ${_fullDate(_lastDay!)}'
          : _fullDate(_firstDay);
      final Widget date = Semantics(
        header: true,
        label: semantics,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!compact && !_isWeek)
              Text(
                relativeDay(_firstDay, today: currentDay) ??
                    weekdayName(_firstDay),
                style: context.text.recipeTitle,
              ),
            Text(
              _dateLabel(currentDay),
              key: const ValueKey<String>('plan-date-label'),
              style: compact
                  ? context.text.label
                  : _isWeek
                  ? context.text.sectionHeader.copyWith(
                      color: context.colors.textSecondary,
                    )
                  : context.text.metadata.copyWith(
                      color: context.colors.textMuted,
                    ),
            ),
          ],
        ),
      );
      final Widget actions = Wrap(
        key: const ValueKey<String>('plan-date-navigation'),
        spacing: HearthSpacing.xs,
        runSpacing: HearthSpacing.xs,
        children: <Widget>[
          _button(
            tooltip: _isWeek ? 'Previous week' : 'Previous day',
            icon: Icons.chevron_left,
            onPressed: onPrevious,
          ),
          _button(
            tooltip: _isWeek ? 'Go to this week' : 'Go to today',
            icon: Icons.today_outlined,
            onPressed: onToday,
          ),
          _button(
            tooltip: _isWeek ? 'Next week' : 'Next day',
            icon: Icons.chevron_right,
            onPressed: onNext,
          ),
          if (_onCopy case final VoidCallback copy)
            _button(
              tooltip: 'Copy this day to other days',
              icon: Icons.copy_all,
              onPressed: copy,
            ),
          if (_trailingAction case final Widget action)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: HearthTouch.androidTarget,
                minHeight: HearthTouch.androidTarget,
              ),
              child: action,
            ),
        ],
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            date,
            const SizedBox(height: HearthSpacing.xs),
            actions,
          ],
        );
      }
      // A long weekday must not be split inside its word just to keep the
      // actions beside it. Both groups keep their natural width and the
      // actions move below when the ordinary phone cannot fit both.
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: HearthSpacing.sm,
        runSpacing: HearthSpacing.xs,
        children: <Widget>[date, actions],
      );
    },
  );

  static Widget _button({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(
      minWidth: HearthTouch.androidTarget,
      minHeight: HearthTouch.androidTarget,
    ),
    icon: Icon(icon),
  );
}
