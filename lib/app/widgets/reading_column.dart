import 'package:flutter/material.dart';

import '../theme/hearth_spacing.dart';

/// Content, bounded to a readable column and centred in what is left over
/// (review §6.2.7).
///
/// A window is as wide as somebody dragged it and a row of content is not. On
/// a 1280pt desktop the recipe list laid a short title at one end of a
/// thousand-point row and a heart at the other, which is not a row anybody
/// reads across — and the same is true of a food, a shopping line, or
/// anything else that is a list of things rather than a document.
///
/// Its own widget rather than a `ConstrainedBox` written out on each screen,
/// so the four section screens cannot drift to four different widths.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: HearthLayout.readingWidth),
      child: child,
    ),
  );
}
