import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import 'day_screen.dart';
import 'week_screen.dart';

/// The Plan section: a day view and a week summary (spec §5.6).
///
/// The day is the default. Logging is what the app is judged on, and the week
/// is where you step back — so the step-back view is one tap away rather than
/// the thing standing between you and logging lunch.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final PlanView view = ref.watch(planViewProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
              child: SegmentedButton<PlanView>(
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
                selected: <PlanView>{view},
                showSelectedIcon: false,
                onSelectionChanged: (Set<PlanView> selection) =>
                    ref.read(planViewProvider.notifier).show(selection.first),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll<TextStyle>(
                    context.text.label,
                  ),
                ),
              ),
            ),
            Expanded(
              child: view == PlanView.day
                  ? const DayScreen()
                  : const WeekScreen(),
            ),
          ],
        ),
      ),
    );
  }
}
