import 'package:flutter/material.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import 'week_view_preference.dart';

enum _CompactWeekChoice { day, meals, nutrition }

/// Day and Week, kept to one labelled control when space is scarce.
class PlanViewControl extends StatelessWidget {
  const PlanViewControl({
    required this.value,
    required this.onChanged,
    this.weekContent,
    this.onWeekContentChanged,
    super.key,
  });

  final PlanView value;
  final ValueChanged<PlanView> onChanged;

  /// When supplied by Plan, one compact menu covers both levels of choice.
  /// Standalone Day/Week controls keep their original contract.
  final WeekContentView? weekContent;
  final ValueChanged<WeekContentView>? onWeekContentChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      return Align(
        alignment: Alignment.centerLeft,
        // Sized to the control, not to the row. It sits in the header's
        // title row now, and an `Align` with no factor takes the whole width
        // it is offered — which pushed the heading beside it onto a line of
        // its own and left the control looking left-aligned under it.
        widthFactor: 1,
        child: compact
            ? value == PlanView.week &&
                      weekContent != null &&
                      onWeekContentChanged != null
                  ? _compactWeek(context)
                  : _compact(context)
            : _segments(context),
      );
    },
  );

  Widget _compact(BuildContext context) => Semantics(
    button: true,
    value: value == PlanView.day ? 'Day' : 'Week',
    child: PopupMenuButton<PlanView>(
      key: const ValueKey<String>('plan-view-control'),
      tooltip: 'Change plan view',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(HearthRadius.md),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<PlanView>>[
        for (final PlanView view in PlanView.values)
          CheckedPopupMenuItem<PlanView>(
            key: ValueKey<String>('plan-view-${view.name}'),
            value: view,
            checked: value == view,
            child: Text(
              view == PlanView.day ? 'Day' : 'Week',
              style: context.text.label,
            ),
          ),
      ],
      child: _menuLabel(
        context,
        value == PlanView.day ? 'Day view' : 'Week view',
      ),
    ),
  );

  Widget _compactWeek(BuildContext context) {
    final bool meals = weekContent == WeekContentView.meals;
    return Semantics(
      key: const ValueKey<String>('week-content-control'),
      button: true,
      value: meals ? 'Week Meals' : 'Week Nutrition',
      child: PopupMenuButton<_CompactWeekChoice>(
        key: const ValueKey<String>('plan-view-control'),
        tooltip: 'Change plan view',
        initialValue: meals
            ? _CompactWeekChoice.meals
            : _CompactWeekChoice.nutrition,
        onSelected: (_CompactWeekChoice choice) {
          switch (choice) {
            case _CompactWeekChoice.day:
              onChanged(PlanView.day);
            case _CompactWeekChoice.meals:
              onWeekContentChanged!(WeekContentView.meals);
            case _CompactWeekChoice.nutrition:
              onWeekContentChanged!(WeekContentView.nutrition);
          }
        },
        position: PopupMenuPosition.under,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<_CompactWeekChoice>>[
              CheckedPopupMenuItem<_CompactWeekChoice>(
                key: const ValueKey<String>('plan-view-day'),
                value: _CompactWeekChoice.day,
                checked: false,
                child: Text('Day', style: context.text.label),
              ),
              CheckedPopupMenuItem<_CompactWeekChoice>(
                key: const ValueKey<String>('week-content-meals'),
                value: _CompactWeekChoice.meals,
                checked: meals,
                child: Text('Week Meals', style: context.text.label),
              ),
              CheckedPopupMenuItem<_CompactWeekChoice>(
                key: const ValueKey<String>('week-content-nutrition'),
                value: _CompactWeekChoice.nutrition,
                checked: !meals,
                child: Text('Week Nutrition', style: context.text.label),
              ),
            ],
        child: _menuLabel(context, meals ? 'Meals' : 'Nutrition'),
      ),
    );
  }

  Widget _menuLabel(BuildContext context, String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border.all(color: context.colors.outlineStrong),
      borderRadius: BorderRadius.circular(HearthRadius.md),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: HearthTouch.androidTarget,
        minHeight: HearthTouch.androidTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: Text(label, style: context.text.label)),
            const SizedBox(width: HearthSpacing.sm),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    ),
  );

  /// Two words, no icons — as the templates draw it.
  ///
  /// The icons were decorative: both segments are labelled, and a sun beside
  /// "Day" says nothing the word does not. They were also 44 points of the
  /// control's width, which is the difference between this sitting beside
  /// the day's heading and dropping onto a line of its own under it — on a
  /// 390pt phone "Wednesday" and the control with icons do not fit together.
  Widget _segments(BuildContext context) => SegmentedButton<PlanView>(
    key: const ValueKey<String>('plan-view-control'),
    segments: const <ButtonSegment<PlanView>>[
      ButtonSegment<PlanView>(value: PlanView.day, label: Text('Day')),
      ButtonSegment<PlanView>(value: PlanView.week, label: Text('Week')),
    ],
    selected: <PlanView>{value},
    showSelectedIcon: false,
    onSelectionChanged: (Set<PlanView> selection) => onChanged(selection.first),
    style: ButtonStyle(
      textStyle: WidgetStatePropertyAll<TextStyle>(context.text.label),
    ),
  );
}
