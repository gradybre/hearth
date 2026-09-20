import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/shopping/walmart_link_reading.dart';
import '../../domain/shopping/walmart_product.dart';

/// Actions and messaging for reading a Walmart product link out of a
/// screenshot, and for reconciling what was read against whatever is
/// already in the link field (D-WALMART-001).
///
/// Stateless and side-effect free: every decision about whether to accept,
/// replace, or discard a reading is made by the caller through [onRead],
/// [onReplace], and [onKeep]. This widget only shows what was found and
/// offers the buttons to act on it.
final class WalmartLinkActions extends StatelessWidget {
  /// The link field's current text, as typed or previously accepted.
  final String value;

  /// The most recent attempt to read a Walmart link from screenshots.
  final WalmartLinkReading reading;

  /// Whether the "read from screenshot" action is currently available.
  final bool canRead;

  /// Starts a fresh read from screenshots.
  final VoidCallback onRead;

  /// Accepts the read candidate, replacing [value].
  final VoidCallback? onReplace;

  /// Discards the read candidate, keeping [value] as-is.
  final VoidCallback? onKeep;

  const WalmartLinkActions({
    required this.value,
    required this.reading,
    required this.canRead,
    required this.onRead,
    this.onReplace,
    this.onKeep,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    final List<Widget> children = <Widget>[];

    if (canRead) {
      children.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onRead,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HearthRadius.sm),
              ),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Read link from screenshot'),
          ),
        ),
      );
    }

    final Widget? resultChild = _buildResult(context, colors, text);
    if (resultChild != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: HearthSpacing.sm));
      }
      children.add(Semantics(liveRegion: true, child: resultChild));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget? _buildResult(
    BuildContext context,
    HearthColors colors,
    HearthTextStyles text,
  ) {
    switch (reading.status) {
      case WalmartLinkStatus.notFound:
        return null;

      case WalmartLinkStatus.ambiguous:
        return Text(
          'More than one Walmart product link was found. Crop to the one '
          'you want, or paste it instead.',
          style: text.metadata.copyWith(color: colors.textSecondary),
        );

      case WalmartLinkStatus.unreadable:
        return Text(
          'No complete Walmart product link could be read. Choose a '
          'screenshot with the full link, or paste it instead.',
          style: text.metadata.copyWith(color: colors.textSecondary),
        );

      case WalmartLinkStatus.found:
        final String? candidate = reading.url;
        if (candidate == null) return null;

        final String trimmedValue = value.trim();
        if (trimmedValue.isEmpty) {
          return _buildFallback(context, colors, text, candidate);
        }

        final String? candidateId = WalmartProduct.idFrom(candidate);
        final String? currentId = WalmartProduct.idFrom(trimmedValue);
        if (candidateId != null && candidateId == currentId) {
          return Text(
            'Read from your screenshot — check before saving.',
            style: text.metadata.copyWith(color: colors.textSecondary),
          );
        }

        return _buildConflict(context, colors, text, candidate);
    }
  }

  Widget _buildFallback(
    BuildContext context,
    HearthColors colors,
    HearthTextStyles text,
    String candidate,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SelectableText(candidate, style: text.body),
        const SizedBox(height: HearthSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onReplace,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Use this link'),
          ),
        ),
      ],
    );
  }

  Widget _buildConflict(
    BuildContext context,
    HearthColors colors,
    HearthTextStyles text,
    String candidate,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'A different Walmart link was read. Your current link is kept.',
          style: text.metadata.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: HearthSpacing.xs),
        SelectableText(candidate, style: text.body),
        const SizedBox(height: HearthSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onReplace,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Use this link'),
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onKeep,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HearthRadius.sm),
              ),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Keep current link'),
          ),
        ),
      ],
    );
  }
}
