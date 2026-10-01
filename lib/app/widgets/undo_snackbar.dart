import 'package:flutter/material.dart';

/// How long a delete's undo stays on screen before it is gone for good.
///
/// Long enough to notice what happened, read it, and decide — short enough
/// that it does not just sit there. Six seconds is a deliberate middle
/// ground, not a platform default; nudge this one constant if it turns out
/// to feel wrong in actual use.
const Duration undoWindow = Duration(seconds: 6);

/// The "Deleted X · Undo" snackbar every delete in Hearth uses.
///
/// One place rather than one copy per screen, because the two things that
/// matter here — how long it stays, and that tapping Undo makes it go away
/// immediately rather than sitting out the rest of [undoWindow] — are exactly
/// the kind of detail that quietly drifts apart between copies. [onUndo]
/// firing is what the user asked for; the snackbar continuing to display
/// afterwards is not.
/// [stackedAction] gives a longer confirmation the full row above Undo.
void showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required VoidCallback onUndo,
  bool stackedAction = false,
}) {
  messenger.hideCurrentSnackBar();
  final SnackBarAction undo = SnackBarAction(
    label: 'Undo',
    onPressed: () {
      // Acting on it is the decision; nothing is served by it lingering
      // for the rest of the window after that.
      messenger.hideCurrentSnackBar();
      onUndo();
    },
  );
  messenger.showSnackBar(
    SnackBar(
      // SnackBar's overflow layout still reserves 40% of the message row
      // for its action. Put the native action below the full-width message
      // here when requested, so large type does not become a narrow column.
      content: stackedAction
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(message),
                Align(alignment: Alignment.centerRight, child: undo),
              ],
            )
          : Text(message),
      duration: undoWindow,
      // Material's own default: a SnackBar with an action sets `persist` to
      // true unless told otherwise, and the auto-dismiss timer no-ops when it
      // is — every snackbar with an Undo button ignores `duration` entirely
      // unless this is set. That default is exactly the bug report this
      // exists to fix; without this line the window above does nothing.
      persist: false,
      action: stackedAction ? null : undo,
    ),
  );
}
