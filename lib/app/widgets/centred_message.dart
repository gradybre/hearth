import 'package:flutter/material.dart';

import '../theme/hearth_spacing.dart';

/// A centred message on an otherwise empty screen (spec §5.8, §6.3).
///
/// Every empty state in the app is the same shape — a heading, a sentence
/// explaining the way out, sometimes a button — and every one of them was
/// written as a `Center` wrapping a `Column`. That clips: at accessibility
/// text sizes the words become taller than the screen, and a Column has
/// nowhere to put the overflow, so the bottom of the message is simply gone.
///
/// Scrollable, therefore, but only when it needs to be: the content stays
/// vertically centred while it fits, which is what makes an empty screen look
/// deliberate rather than top-aligned and forgotten. Dynamic type is honoured
/// by letting the layout give way, never by capping the text (§6.3).
class CentredMessage extends StatelessWidget {
  const CentredMessage({
    required this.children,
    this.gutter = HearthSpacing.lg,
    this.maxWidth = 380,
    super.key,
  });

  final List<Widget> children;
  final double gutter;

  /// A line of prose is unreadable when it runs the full width of a tablet.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final Widget content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      );

      // Unbounded height means this is already inside something that scrolls
      // — a sliver, or another scroll view. Adding a second scrollable there
      // is both wrong and, because the minimum height would be infinite, a
      // hard layout error. Just lay the content out.
      if (!constraints.hasBoundedHeight) {
        return Padding(
          padding: EdgeInsets.all(gutter),
          child: Center(child: content),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(gutter),
        child: ConstrainedBox(
          // Centres while it fits; scrolls once it does not.
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - gutter * 2).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Center(child: content),
        ),
      );
    },
  );
}
