import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/reading_column.dart';
import 'day_screen.dart';
import 'plan_view_control.dart';
import 'week_screen.dart';
import 'week_view_preference.dart';

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
    final WeekViewPreferenceState? weekPreference = view == PlanView.week
        ? ref.watch(weekViewPreferenceProvider)
        : null;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;
    final bool compact =
        MediaQuery.sizeOf(context).width < 372 ||
        MediaQuery.textScalerOf(context).scale(16) > 20;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            ReadingColumn(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  compact ? HearthSpacing.sm : gutter,
                  gutter,
                  0,
                ),
                child: PlanViewControl(
                  value: view,
                  onChanged: (PlanView selection) =>
                      ref.read(planViewProvider.notifier).show(selection),
                  weekContent: weekPreference?.view,
                  onWeekContentChanged: weekPreference == null
                      ? null
                      : (WeekContentView selection) => ref
                            .read(weekViewPreferenceProvider.notifier)
                            .choose(selection),
                ),
              ),
            ),
            Expanded(
              child: view == PlanView.day
                  ? const DayScreen()
                  : WeekScreen(showViewControl: !compact),
            ),
          ],
        ),
      ),
    );
  }
}
