import 'package:flutter/material.dart';

import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import '../widgets/centred_message.dart';
import '../widgets/reading_column.dart';

/// A tab that exists but has nothing behind it yet (spec §11).
///
/// The rooms are named and navigable before they are furnished, so the shape
/// of the app is walkable. What matters is that the screen says so plainly —
/// an empty list and an unwritten feature look identical, and only one of them
/// is worth waiting for.
///
/// It names what *will* be here rather than apologising. "Nothing here yet" on
/// its own reads as a fault; "Nothing here yet — workouts will be logged here"
/// reads as a room with the furniture still on order.
class UnbuiltScreen extends StatelessWidget {
  const UnbuiltScreen({required this.title, required this.coming, super.key});

  /// The tab's own name, so a screen reached from three different tabs does
  /// not say the same thing three times.
  final String title;

  /// One line naming what will live here, in the present tense of a promise
  /// rather than the future tense of a roadmap.
  final String coming;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ReadingColumn(
          child: CentredMessage(
            gutter: gutter,
            children: <Widget>[
              Text(
                title,
                style: context.text.sectionHeader,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                coming,
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'Not built yet.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
