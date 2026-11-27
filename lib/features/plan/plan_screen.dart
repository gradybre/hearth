import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_theme.dart';
import 'day_screen.dart';
import 'week_screen.dart';

/// The Plan section: a day view and a week summary (spec §5.6).
///
/// The day is the default. Logging is what the app is judged on, and the week
/// is where you step back — so the step-back view is one tap away rather than
/// the thing standing between you and logging lunch.
///
/// This screen used to draw the Day / Week control itself, in a fixed band
/// above whichever view was showing. The templates put it beside the day's
/// title, so it moved into [PlanDateHeader] — which each view already builds
/// — and what is left here is the switch between the two.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: context.colors.background,
    body: SafeArea(
      child: ref.watch(planViewProvider) == PlanView.day
          ? const DayScreen()
          : const WeekScreen(),
    ),
  );
}
