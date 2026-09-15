import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every question the app asks can be read at the largest text (§6.3).
///
/// An `AlertDialog` sizes itself to its content and then stops. Past the
/// height it is allowed, the column runs off the bottom and takes the actions
/// with it — so the confirming button and Cancel, the only two things the
/// dialog exists for, end up off the screen with no way to reach them. On a
/// 320-point phone at three times the text, that is not a hypothetical: the
/// sign-out question overflowed by 12 points and the password-reset question
/// by 204.
///
/// `scrollable: true` is the whole fix, and the app had already settled on it
/// — three dialogs set it, three did not, and nothing said which was the
/// convention. A rule is cheaper than finding the next one the way these two
/// were found, which was by accident, while a sweep was being widened for a
/// different reason.
///
/// Deliberately a text scan rather than a widget test. The behavioural tests
/// beside the screens prove the two that were broken are fixed; this proves
/// nobody adds a seventh without it, including on a screen no sweep reaches.
void main() {
  test('every AlertDialog in lib/ is scrollable', () {
    final List<String> missing = <String>[];

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      if (!source.contains('AlertDialog(')) continue;

      // Each occurrence carries its own answer: one file can hold a dialog
      // that scrolls and one that does not, which is exactly how these two
      // were missed — `settings_screen.dart` has two, and counting the file
      // once would have called it done as soon as either was fixed.
      int from = 0;
      while (true) {
        final int at = source.indexOf('AlertDialog(', from);
        if (at < 0) break;
        from = at + 1;
        // The constructor's own argument list, to the first closing paren at
        // depth zero. Nested calls inside it are counted through, so an
        // argument that is itself a widget does not end the search early.
        int depth = 0;
        int end = at + 'AlertDialog('.length - 1;
        for (int i = end; i < source.length; i++) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        final String arguments = source.substring(at, end);
        if (!arguments.contains('scrollable: true')) {
          final int line = '\n'.allMatches(source.substring(0, at)).length + 1;
          missing.add('${entity.path}:$line');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These dialogs cannot scroll, so at large text their buttons go off '
          'the bottom with no way to reach them. Add `scrollable: true`:\n'
          '  ${missing.join('\n  ')}',
    );
  });
}
