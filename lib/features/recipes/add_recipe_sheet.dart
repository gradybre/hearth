import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';

/// The ways a recipe can come into the library (spec §5.2, §5.3, U05).
///
/// One labelled control rather than four buttons stacked up the corner of the
/// screen. Three of those four were icon-only, so what they did lived in a
/// tooltip — which is a hover, on a device with no pointer. The stack also
/// grew by one every time another way in was built.
///
/// Nothing here is hidden or disabled when the server is unreachable. Each
/// destination explains its own unavailability in its own words — "Importing
/// needs a connection to Hearth's server" — and a greyed-out row with no
/// reason is worse than a row that tells you why when you press it.
Future<void> showAddRecipeSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => const _AddRecipeSheet(),
);

class _AddRecipeSheet extends StatelessWidget {
  const _AddRecipeSheet();

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    // Material rather than a DecoratedBox: a ListTile paints its ink on the
    // nearest Material ancestor, and a coloured box in between hides it — the
    // framework says so out loud, which is how this was caught.
    return Material(
      color: colors.background,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HearthRadius.xl),
      ),
      child: SafeArea(
        // A list, not a column: four rows of prose at three times the text is
        // taller than a short phone, and a sheet that cannot scroll puts the
        // last way in below the bottom of the screen.
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
              child: Text('Add recipe', style: context.text.sectionHeader),
            ),
            for (final _Way way in _ways)
              ListTile(
                leading: Icon(way.icon, color: colors.textSecondary),
                title: Text(way.label, style: context.text.body),
                subtitle: Text(
                  way.blurb,
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(way.path);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// One way a recipe gets in.
class _Way {
  const _Way({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.path,
  });

  final String label;
  final String blurb;
  final IconData icon;
  final String path;
}

/// Typing first: a recipe out of your own head is still the common case.
const List<_Way> _ways = <_Way>[
  _Way(
    label: 'Write a recipe',
    blurb: 'A blank page, and your own words.',
    icon: Icons.edit_outlined,
    path: '/recipe/new',
  ),
  _Way(
    label: 'Import a recipe',
    blurb: 'From a picture, a screenshot, or a link.',
    icon: Icons.document_scanner_outlined,
    path: '/recipe/import',
  ),
  // Building a meal you ordered is a different act from writing a recipe, and
  // it produces one anyway — so it sits with the other ways in rather than
  // behind the editor (spec §5.2).
  _Way(
    label: 'Eat out',
    blurb: 'Build what you ordered from a restaurant menu.',
    icon: Icons.storefront,
    path: '/recipe/eat-out',
  ),
  _Way(
    label: 'Generate with AI',
    blurb: 'Describe a meal and have Hearth write it.',
    icon: Icons.auto_awesome,
    path: '/recipe/write',
  ),
];
