import 'package:flutter/material.dart';

import '../theme/hearth_theme.dart';

/// Asks before an editor throws away work that has not been saved
/// (spec §5.2, review F01).
///
/// Both editors used to send Cancel straight to `Navigator.pop()`. Nothing
/// asked, and the tap that did it sits in the corner a back gesture lands in
/// — so a recipe retyped off a photograph, or forty minutes of a menu, went
/// in one slip with no way back.
///
/// One widget rather than the same dialog written twice, because the two
/// editors answering differently is how one of them quietly stops asking.
///
/// **Only when there is something to lose.** An editor that asks every time
/// teaches people to press Discard without reading it, and then it is not a
/// guard at all — it is a speed bump they have learned to take at speed. The
/// caller decides with [isDirty]; a clean editor closes on the first tap.
class UnsavedWorkGuard extends StatelessWidget {
  const UnsavedWorkGuard({
    required this.isDirty,
    required this.child,
    this.what = 'changes',
    super.key,
  });

  /// Whether anything would be lost by leaving now.
  final bool Function() isDirty;

  /// What the dialog says is at stake — "recipe", "food". Named rather than
  /// generic because "Discard changes?" over a half-typed recipe is a
  /// question about something the reader has to work out for themselves.
  final String what;

  final Widget child;

  /// Whether it is safe to leave, asking if it is not.
  ///
  /// Returns true when the caller should go ahead and pop. Safe to call from
  /// a button as well as from the system back gesture, which is the point of
  /// having it here: those two must not disagree.
  static Future<bool> confirm(BuildContext context, String what) async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Discard this $what?', style: context.text.sectionHeader),
        content: Text(
          'What you have typed has not been saved.',
          style: context.text.body,
        ),
        actions: <Widget>[
          // Keep editing first and last-pressed, because it is the answer
          // that loses nothing. Discard is the one worth having to reach for.
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    // Dismissed by tapping outside is not consent to lose anything.
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !isDirty(),
    onPopInvokedWithResult: (bool didPop, Object? result) async {
      if (didPop) return;
      if (!context.mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      if (await confirm(context, what)) navigator.pop();
    },
    child: child,
  );
}
