import 'package:flutter/material.dart';

import '../app/theme/hearth_colors.dart';
import '../app/theme/hearth_spacing.dart';
import '../app/theme/hearth_theme.dart';
import '../app/theme/hearth_typography.dart';

/// An honest empty state for a section that hasn't been built yet.
///
/// Says plainly what will live here and which build phase brings it, rather
/// than showing a fake screen that implies working functionality.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.description,
    required this.phase,
    super.key,
  });

  final String title;
  final String description;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(HearthSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  style: text.sectionHeader,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  description,
                  style: text.body.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HearthSpacing.lg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(HearthRadius.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HearthSpacing.md,
                      vertical: HearthSpacing.xs,
                    ),
                    child: Text(
                      phase,
                      style: text.metadata.copyWith(color: colors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
