import 'package:flutter/material.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';

/// Day and Week, kept to one labelled control when space is scarce.
class PlanViewControl extends StatelessWidget {
  const PlanViewControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final PlanView value;
  final ValueChanged<PlanView> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      return Align(
        alignment: Alignment.centerLeft,
        child: compact ? _compact(context) : _segments(context),
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
      child: DecoratedBox(
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
                Flexible(
                  child: Text(
                    value == PlanView.day ? 'Day view' : 'Week view',
                    style: context.text.label,
                  ),
                ),
                const SizedBox(width: HearthSpacing.sm),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _segments(BuildContext context) => SegmentedButton<PlanView>(
    key: const ValueKey<String>('plan-view-control'),
    segments: const <ButtonSegment<PlanView>>[
      ButtonSegment<PlanView>(
        value: PlanView.day,
        label: Text('Day'),
        icon: Icon(Icons.wb_sunny_outlined, size: 18),
      ),
      ButtonSegment<PlanView>(
        value: PlanView.week,
        label: Text('Week'),
        icon: Icon(Icons.view_week_outlined, size: 18),
      ),
    ],
    selected: <PlanView>{value},
    showSelectedIcon: false,
    onSelectionChanged: (Set<PlanView> selection) => onChanged(selection.first),
    style: ButtonStyle(
      textStyle: WidgetStatePropertyAll<TextStyle>(context.text.label),
    ),
  );
}
