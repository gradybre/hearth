import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';

import '../../support/app_harness.dart';

/// Settings, from wherever you are (review §7's consistent access).
///
/// It lived on the home screen alone, so reaching it from inside a section
/// meant leaving the section first: back to Home, then in again. That is two
/// deliberate navigations to change a preference about the screen you were
/// already looking at.
void main() {
  /// Opens [tab] inside the nutrition section.
  Future<void> openTab(WidgetTester tester, String tab, {Size? size}) async {
    await pumpHearthApp(tester, size: size ?? const Size(390, 844));
    await tester.tap(find.text(tab).last);
    await pumpFrames(tester, frames: 12);
  }

  for (final String tab in <String>['Recipes', 'Plan', 'Shopping', 'Foods']) {
    testWidgets('$tab can reach Settings without going home first', (
      WidgetTester tester,
    ) async {
      await openTab(tester, tab);

      final Finder settings = find.byTooltip('Settings');
      expect(
        settings,
        findsOneWidget,
        reason: 'no way into Settings from $tab',
      );

      await tester.tap(settings);
      await pumpFrames(tester, frames: 20);
      expect(find.text('Settings'), findsWidgets);
    });
  }

  testWidgets('and so can a wide window, where the sidebar is the chrome', (
    WidgetTester tester,
  ) async {
    // The two layouts have different chrome — a bar above the content on a
    // phone, a sidebar beside it on a desktop — and "the same place
    // whichever screen you are on" has to hold in both or it holds in
    // neither.
    await openTab(tester, 'Recipes', size: const Size(1280, 900));

    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('the home screen keeps the one it already had', (
    WidgetTester tester,
  ) async {
    // Not moved, only joined. Home is where it has always been — and the
    // harness opens the nutrition shell unless told otherwise.
    await pumpHearthApp(tester, launchTarget: LaunchTarget.home);
    await pumpFrames(tester, frames: 12);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
