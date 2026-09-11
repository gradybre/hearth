import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import 'food_draft.dart';
import 'read_label_sheet.dart';

/// The ways a food can come into the library (spec §5.5, review §6.2.6).
///
/// One labelled control rather than three buttons stacked up the corner of
/// the screen — four, once a build could read labels. Two of those said what
/// they did only in a tooltip, which is a hover on a device with no pointer,
/// and the stack grew by one every time another way in was built.
///
/// This is deliberately the same sheet as `add_recipe_sheet.dart` rather than
/// a second pattern for the same job: the review's §6.2.6 complaint is that
/// sibling screens invent their own conventions, and answering it with a
/// third convention would be answering it with the fault.
///
/// Every row ends in the editor or the scanner, never in a saved food —
/// nothing a camera or a database produced is written without being looked at
/// (CLAUDE.md rule 4).
///
/// [onSaved] receives the id of whatever was eventually saved, from any of the
/// three ways in. The Foods screen is scoped, and all three can write a food
/// into the half that is not showing — the manual editor's "From a restaurant"
/// switch does it without the scope being touched at all — so the caller has
/// to be told, or a food is saved out of sight.
Future<void> showAddFoodSheet(
  BuildContext context, {
  required ValueChanged<String> onSaved,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  // The screen's own context is handed to the sheet rather than the builder's:
  // every row closes the sheet before it navigates, and the builder's context
  // is dead the moment it does. Reading a label opens a second sheet from it,
  // which a defunct element cannot do.
  builder: (BuildContext _) => _AddFoodSheet(host: context, onSaved: onSaved),
);

class _AddFoodSheet extends ConsumerWidget {
  const _AddFoodSheet({required this.host, required this.onSaved});

  /// The screen underneath, which outlives this sheet.
  final BuildContext host;

  /// Told the id of the food that was saved, if one was.
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;

    // Material rather than a DecoratedBox, for the reason the recipe sheet
    // records: a ListTile paints its ink on the nearest Material ancestor,
    // and a coloured box in between hides it.
    return Material(
      color: colors.background,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HearthRadius.xl),
      ),
      child: SafeArea(
        // A list, not a column: three rows of prose at three times the text
        // is taller than a short phone, and a sheet that cannot scroll puts
        // the last way in below the bottom of the screen (spec §6.3).
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
              child: Text('Add food', style: context.text.sectionHeader),
            ),
            // Scanning leads because it is the faster path for anything with
            // a packet, and §5.5 puts manual entry behind it as the fallback
            // rather than in front of it.
            _Way(
              label: 'Scan a barcode',
              blurb: 'The fastest way in for anything with a packet.',
              icon: Icons.qr_code_scanner,
              onChosen: () => host.push<String>('/food/scan'),
              onSaved: onSaved,
            ),
            // Hidden rather than disabled when the build has no label reader:
            // the Claude key lives in an Edge Function, so an unconfigured
            // build has no way to read one at all, and offering a camera that
            // leads nowhere is worse than not offering one.
            if (canReadLabels(ref))
              _Way(
                label: 'Read a label',
                blurb: 'Photograph the panel on the back of the packet.',
                icon: Icons.document_scanner_outlined,
                onChosen: () => _readLabel(host),
                onSaved: onSaved,
              ),
            _Way(
              label: 'Enter it by hand',
              // For the things with no barcode to scan at all — the deli
              // counter, bulk bins, a wrapper already torn open. §5.5 ends
              // its lookup chain here, and §12 names food-data coverage as
              // the biggest threat to the success bar.
              blurb: 'The deli counter, the bulk bins, your own cooking.',
              icon: Icons.edit_outlined,
              onChosen: () => host.push<String>('/food/new'),
              onSaved: onSaved,
            ),
          ],
        ),
      ),
    );
  }

  /// Reads a label and opens the editor with it, for a food with no barcode.
  ///
  /// Straight to the editor, like every other route into the library: nothing
  /// a camera produced is saved without being looked at (CLAUDE.md rule 4).
  static Future<String?> _readLabel(BuildContext host) async {
    final LabelReading? reading = await showReadLabelSheet(host);
    if (reading == null || !host.mounted) return null;
    return host.push<String>(
      '/food/new',
      extra: FoodDraft.blank().withLabel(reading),
    );
  }
}

/// One way a food gets in.
class _Way extends StatelessWidget {
  const _Way({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.onChosen,
    required this.onSaved,
  });

  final String label;
  final String blurb;
  final IconData icon;

  /// Runs this way in, and answers with the id of the food it saved.
  final Future<String?> Function() onChosen;

  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return ListTile(
      leading: Icon(icon, color: colors.textSecondary),
      title: Text(label, style: context.text.body),
      subtitle: Text(
        blurb,
        style: context.text.metadata.copyWith(color: colors.textMuted),
      ),
      onTap: () async {
        // The sheet closes first in every case. Reading a label opens a sheet
        // of its own, and two stacked modals leave this one behind whatever
        // the second one pushes.
        Navigator.of(context).pop();
        final String? saved = await onChosen();
        if (saved != null) onSaved(saved);
      },
    );
  }
}
