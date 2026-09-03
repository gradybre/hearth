import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../a11y/accessibility.dart';
import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import 'undo_snackbar.dart';

/// Swipe a row aside to uncover the way to delete it.
///
/// Two deliberate actions, not one: the swipe uncovers a button, and the
/// button has to be pressed. A single flick removing something from a shared
/// library would be far too easy to do by accident while scrolling with messy
/// hands.
///
/// Everything Hearth deletes is soft-deleted (§4), so [onRestore] is a real
/// restore rather than a re-creation — the row comes back with the same id and
/// everything already logged against it keeps resolving. That is what makes an
/// undo in a snackbar honest here rather than a confirmation dialog.
///
/// **Give it a key tied to the item's id, never its position.** Flutter matches
/// list elements by index, so an unkeyed row hands its swiped-open state to
/// whatever moves up into its place when the list shifts.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    required this.name,
    required this.onDelete,
    required this.onRestore,
    required this.child,
    super.key,
  });

  /// What to call the thing, in the snackbar and to a screen reader.
  final String name;

  final Future<void> Function() onDelete;
  final Future<void> Function() onRestore;

  final Widget child;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  /// How far a swipe has to travel before it counts.
  static const double _swipeDistance = 40;

  /// How far the row slides to uncover the button.
  static const double _revealed = 0.32;

  bool _open = false;
  double _dragged = 0;

  Future<void> _delete() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String name = widget.name;

    await widget.onDelete();
    if (!mounted) return;

    setState(() => _open = false);
    showUndoSnackBar(
      messenger,
      message: 'Deleted $name',
      onUndo: widget.onRestore,
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      // Reachable without the gesture: a swipe is not something a screen
      // reader user can discover (§6.3).
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: 'Delete ${widget.name}'): _delete,
      },
      // The gesture wraps the whole row, not the sliding child. Inside the
      // slide its hit area would stay where the row started, so once the row
      // moved the part you could see would not be the part you could grab.
      child: GestureDetector(
        onHorizontalDragStart: (_) => _dragged = 0,
        onHorizontalDragUpdate: (DragUpdateDetails details) =>
            _dragged += details.primaryDelta ?? 0,
        onHorizontalDragEnd: (DragEndDetails details) {
          // Distance as well as speed. Velocity alone meant a slow, deliberate
          // swipe did nothing — which is exactly how someone swipes when they
          // mean it.
          final double velocity = details.primaryVelocity ?? 0;
          final bool left = _dragged < -_swipeDistance || velocity < -300;
          final bool right = _dragged > _swipeDistance || velocity > 300;
          if (left && !_open) setState(() => _open = true);
          if (right && _open) setState(() => _open = false);
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: HearthSpacing.sm),
                  // Hidden from assistive tech while the row covers it.
                  // Announcing a control nobody can reach — whose reveal is a
                  // gesture a screen reader user cannot discover — is worse
                  // than not announcing it; the custom action above is how
                  // they delete, and it works whatever the row is doing.
                  child: ExcludeSemantics(
                    excluding: !_open,
                    child: TextButton.icon(
                      onPressed: _open ? _delete : null,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              offset: _open ? const Offset(-_revealed, 0) : Offset.zero,
              // Through A11y.motion, not a bare Duration: this is the only
              // animation in the app, and motion respects the OS setting
              // (§6.3). The row still moves aside — it just arrives there
              // rather than sliding.
              duration: A11y.motion(context, const Duration(milliseconds: 180)),
              curve: Curves.easeOut,
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
