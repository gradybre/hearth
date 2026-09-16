import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/features/account/settings_screen.dart';

import 'settings_screen_test.dart' show pumpSettings;

/// The questions Settings asks, at the largest text somebody might use.
///
/// An `AlertDialog` sizes itself to its content and then stops: past the
/// height it is allowed, the column simply runs off the bottom and takes the
/// buttons with it. Which means the confirming button and Cancel — the only
/// two things the dialog exists for — can be off the screen with no way to
/// reach them, on a phone whose owner has turned the text up.
///
/// §6.3 says dynamic type is honoured, and `scrollable: true` is what honours
/// it here. Three of the app's dialogs already set it; these did not.
void main() {
  /// The smallest phone Hearth targets, at the largest accessibility step.
  Future<void> openSettings(WidgetTester tester, {Widget? page}) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await pumpSettings(tester, page: page ?? const SettingsScreen());
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();
  }

  testWidgets('the sign-out question fits a small phone at the largest text', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);
    // Three times the text puts the row well below the fold, and a lazy list
    // does not build what is off the screen.
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the sign-out question overflowed at 3x on a 320pt phone',
    );
  });

  testWidgets('and so does the password-reset question', (
    WidgetTester tester,
  ) async {
    // The longer of the two: it names the address and explains that the link
    // opens a browser, which at 3x is most of a small phone before either
    // button is reached.
    await openSettings(tester, page: const AccountSettingsScreen());
    await tester.scrollUntilVisible(find.text('Reset password'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(find.text('Send a reset link?'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the password-reset question overflowed at 3x on a 320pt phone',
    );
  });
}
