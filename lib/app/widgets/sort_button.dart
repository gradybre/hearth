import 'package:flutter/material.dart';

import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';

/// One option a [SortButton] can offer.
class SortChoice<T> {
  const SortChoice({required this.value, required this.label});

  final T value;
  final String label;
}

/// The sort control both library screens use.
///
/// A menu rather than another chip in the row. Sort is single-choice and
/// always *on* — there is no "unsorted" — which is the opposite of how a
/// filter chip behaves, and giving the two the same appearance would suggest
/// you could turn sorting off by tapping the lit one.
///
/// It shows the current sort by name at all times, so the order the list is
/// in is never something you have to open a menu to find out.
class SortButton<T> extends StatelessWidget {
  const SortButton({
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<SortChoice<T>> choices;
  final ValueChanged<T> onChanged;

  String get _currentLabel => choices
      .firstWhere(
        (SortChoice<T> c) => c.value == value,
        orElse: () => choices.first,
      )
      .label;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(right: HearthSpacing.sm),
      // No Semantics wrapper: `excludeSemantics` around a control drops the
      // child's tap action, leaving a node that announces "button" and then
      // does nothing when activated — the exact trap
      // test/app/a11y/activatable_test.dart exists to catch. The tooltip is
      // the label instead, which PopupMenuButton already exposes to a screen
      // reader while keeping its own action intact.
      child: PopupMenuButton<T>(
        initialValue: value,
        tooltip: 'Sort by — currently $_currentLabel',
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        color: colors.surfaceElevated,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<T>>[
          for (final SortChoice<T> choice in choices)
            PopupMenuItem<T>(
              value: choice.value,
              child: Row(
                children: <Widget>[
                  // The chosen one carries a tick as well as the menu's own
                  // highlight — never colour alone (spec §6.3).
                  Icon(
                    choice.value == value ? Icons.check : null,
                    size: 16,
                    color: colors.accent,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Text(choice.label, style: context.text.label),
                ],
              ),
            ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            border: Border.all(color: colors.outline),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HearthSpacing.md,
            vertical: HearthSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.swap_vert, size: 16, color: colors.textSecondary),
              const SizedBox(width: HearthSpacing.xs),
              Text(
                _currentLabel,
                style: context.text.label.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
