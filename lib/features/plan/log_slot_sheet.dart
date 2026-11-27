import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/meal_plan.dart';
import 'log_sheet.dart';

/// Which meal a thing is being logged into (spec §5.6).
///
/// The day screen's primary action is "Log food", and the templates draw it
/// without saying where the food goes. Somewhere it has to: a log sheet is
/// opened for one slot and keeps it, so the slot is decided before the sheet
/// and not inside it.
///
/// **Asked rather than guessed.** Guessing from the clock is faster when it
/// is right and silently files breakfast under dinner when it is not — and
/// the sheet has no way to correct it, so the cost of a wrong guess is a
/// cancel and a second go. It is also meaningless on a day that is not
/// today, which this screen can be showing. One tap, always right, is the
/// better trade for a screen whose whole job is logging.
///
/// It does not replace the `+` on each meal: that one already knows where it
/// is going and stays the shorter path for somebody who has scrolled to the
/// meal they mean.
Future<void> showLogSlotSheet(BuildContext context, {required DateTime date}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _LogSlotSheet(date: date),
    );

class _LogSlotSheet extends StatelessWidget {
  const _LogSlotSheet({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    // Material rather than a painted box, so a row's ink lands on something.
    return Material(
      color: colors.background,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HearthRadius.xl),
      ),
      child: SafeArea(
        // A list, not a column: four rows at three times the text is taller
        // than a short phone, and a sheet that cannot scroll puts the last
        // meal below the bottom of the screen (spec §6.3).
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: HearthSpacing.md),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HearthSpacing.lg,
                HearthSpacing.xs,
                HearthSpacing.lg,
                HearthSpacing.md,
              ),
              child: Text('Log food to', style: context.text.sectionHeader),
            ),
            for (final MealSlot slot in MealSlot.values)
              ListTile(
                // Used at arm's length with messy hands, so the rows are
                // sized for a kitchen rather than to the 48pt floor
                // (spec §5.6).
                minTileHeight: HearthTouch.kitchenTarget,
                title: Text(slot.label, style: context.text.body),
                trailing: Icon(Icons.chevron_right, color: colors.textMuted),
                onTap: () {
                  Navigator.of(context).pop();
                  showLogSheet(context, date: date, slot: slot);
                },
              ),
          ],
        ),
      ),
    );
  }
}
