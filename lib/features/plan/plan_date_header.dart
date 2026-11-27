import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/day_format.dart';

/// The planner's title, its date stepper and its actions (spec §5.6, and the
/// November 2026 templates).
///
/// Two rows, not one. The title row carries the day in words and the Day /
/// Week control beside it; the row under it is the stepper — previous at the
/// left edge, next at the right, and the date centred between them. The
/// control used to be fixed chrome above the whole screen, owned by
/// [PlanScreen], which is why the templates' first row did not exist: the
/// title and the control were never in the same widget.
///
/// **The stepper balances rather than centring by arithmetic.** Two buttons
/// on the left, two on the right, so an `Expanded` between them puts the date
/// in the middle of the row and not in the middle of what is left over. The
/// templates draw only the two arrows; Hearth has "go to today" and, on the
/// day, a copy — neither is something the templates thought about, and
/// neither is given up to match a picture.
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
    this.viewControl,
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
    this.viewControl,
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

  /// The Day / Week control, drawn on the title row beside the heading.
  ///
  /// Passed in rather than built here: this widget knows about a date, not
  /// about which of the planner's two views is showing, and the week's
  /// control carries a second level of choice the day's does not.
  final Widget? viewControl;

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

      // The date itself, wherever it ends up: centred between the arrows on
      // an ordinary screen, on its own line above them when the words have
      // grown too big for a row.
      final Widget date = Semantics(
        // A node of its own. With `container: false` the annotation is
        // merged into whatever encloses it — and inside the stepper's Row
        // that is a layout box with no semantics of its own, so the label
        // was dropped and the date announced itself as "Wed, Sep 30" or not
        // at all. It only worked while this wrapped the header's whole
        // left-hand column.
        container: true,
        header: true,
        label: semantics,
        excludeSemantics: true,
        child: Text(
          _dateLabel(currentDay),
          key: const ValueKey<String>('plan-date-label'),
          textAlign: compact ? TextAlign.start : TextAlign.center,
          style: compact
              ? context.text.label
              : _isWeek
              ? context.text.sectionHeader.copyWith(
                  color: context.colors.textSecondary,
                )
              // Up from the muted metadata it used to be. Alone in the
              // middle of its own row it is no longer a caption under a
              // heading — it is the thing the row is about.
              : context.text.label,
        ),
      );

      // The day in words: "Today", "Yesterday", or the weekday. The week has
      // none — its date range is the only name it has, and it is on the
      // stepper.
      final Widget? title = compact || _isWeek
          ? null
          : Text(
              relativeDay(_firstDay, today: currentDay) ??
                  weekdayName(_firstDay),
              style: context.text.recipeTitle,
            );

      final Widget? titleRow = title == null && viewControl == null
          ? null
          : Wrap(
              // With a title, the pair sits at the two ends of the row as
              // the templates draw it. Without one — the week — there is
              // nothing to push against, so the control keeps the right-hand
              // side rather than sliding over to the left.
              alignment: title == null
                  ? WrapAlignment.end
                  : WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: HearthSpacing.sm,
              runSpacing: HearthSpacing.xs,
              children: <Widget>[?title, ?viewControl],
            );

      final Widget previous = _button(
        tooltip: _isWeek ? 'Previous week' : 'Previous day',
        icon: Icons.chevron_left,
        onPressed: onPrevious,
      );
      final Widget toToday = _button(
        tooltip: _isWeek ? 'Go to this week' : 'Go to today',
        icon: Icons.today_outlined,
        onPressed: onToday,
      );
      final Widget next = _button(
        tooltip: _isWeek ? 'Next week' : 'Next day',
        icon: Icons.chevron_right,
        onPressed: onNext,
      );
      final Widget? extra = _onCopy == null
          ? _trailingAction == null
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: HearthTouch.androidTarget,
                      minHeight: HearthTouch.androidTarget,
                    ),
                    child: _trailingAction,
                  )
          : _button(
              tooltip: 'Copy this day to other days',
              icon: Icons.copy_all,
              onPressed: _onCopy,
            );

      if (compact) {
        // No stepper here: at three times the text one arrow and the date
        // are already wider than a small phone, and a row that cannot hold
        // its middle puts the date off the side of the screen. The date
        // takes the full width and the controls follow it, which is what
        // this layout has always done (spec §6.3).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (titleRow case final Widget row) ...<Widget>[
              row,
              const SizedBox(height: HearthSpacing.xs),
            ],
            date,
            const SizedBox(height: HearthSpacing.xs),
            Wrap(
              key: const ValueKey<String>('plan-date-navigation'),
              spacing: HearthSpacing.xs,
              runSpacing: HearthSpacing.xs,
              children: <Widget>[previous, toToday, next, ?extra],
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ?titleRow,
          Row(
            key: const ValueKey<String>('plan-date-navigation'),
            children: <Widget>[
              previous,
              toToday,
              // Centred in the row, not in what is left of it: the two
              // buttons on each side are the same width, so the middle of
              // this Expanded is the middle of the header.
              Expanded(child: Center(child: date)),
              ?extra,
              next,
            ],
          ),
        ],
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
