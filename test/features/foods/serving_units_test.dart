import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import 'label_scan_test.dart' show openEditor;

/// The words a serving can be measured in (spec §5.3).
///
/// The list used to end at `item`, so a tub of protein powder had no way to
/// say "scoop" and a cereal box had no way to say "bar". Both got logged in a
/// word nobody uses, or not at all.
void main() {
  Future<void> openUnitMenu(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await pumpFrames(tester, frames: 10);
  }

  /// The menu is a lazily built scrolling list, so the packet words — which
  /// are deliberately at the bottom — are not on screen when it opens.
  Future<void> scrollMenuToEnd(WidgetTester tester) async {
    await tester.drag(find.text('Weight'), const Offset(0, -600));
    await pumpFrames(tester, frames: 10);
  }

  testWidgets('a serving can be a scoop, a bar, or a patty', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);
    await openUnitMenu(tester);
    await scrollMenuToEnd(tester);

    for (final String word in <String>['scoop', 'bar', 'patty', 'tortilla']) {
      expect(find.text(word), findsWidgets, reason: '$word should be offered');
    }
  });

  testWidgets('the packet words are grouped, not buried under fl oz', (
    WidgetTester tester,
  ) async {
    // Twenty-odd units is a list nobody reads to the bottom of, and the
    // bottom is where the new ones are.
    await openEditor(tester);
    await openUnitMenu(tester);

    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('Packets and pieces'), findsOneWidget);
  });

  testWidgets('a heading cannot be chosen as a unit', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);
    await openUnitMenu(tester);

    // Tapping it does nothing and the menu stays open — it is a label, and
    // "Packets and pieces" is not a unit anything can be measured in.
    await tester.tap(find.text('Packets and pieces'));
    await pumpFrames(tester);

    expect(find.text('Weight'), findsOneWidget);
  });
}
