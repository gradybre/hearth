import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

/// One labelled way in, rather than four icons stacked up (U05).
///
/// Three of the four were icon-only, which means their meaning lived in a
/// tooltip — something you get by hovering, on a device with no pointer. The
/// stack also grows every time a new way to add a recipe is built.
void main() {
  Future<void> openLibrary(WidgetTester tester, {double scale = 1.0}) async {
    await pumpHearthApp(tester, textScale: scale);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('the library offers one control, and it is labelled', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);

    expect(find.text('Add recipe'), findsOneWidget);
    // One, not a stack. An extended FAB is still a FloatingActionButton, so
    // the question is how many, not whether.
    expect(
      find.byType(FloatingActionButton),
      findsOneWidget,
      reason: 'the stacked icon buttons are still there',
    );
  });

  testWidgets('and it opens the four ways in, in words', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);
    await tester.tap(find.text('Add recipe'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Write a recipe'), findsOneWidget);
    expect(find.text('Import a recipe'), findsOneWidget);
    expect(find.text('Eat out'), findsOneWidget);
    expect(find.text('Generate with AI'), findsOneWidget);
  });

  // One pumped app each: pumping twice in a single case opens the database a
  // second time, which drift warns about and which is nothing to do with the
  // thing being tested.
  for (final (String label, String lands) in <(String, String)>[
    ('Write a recipe', 'Title'),
    ('Eat out', 'Eat out'),
  ]) {
    testWidgets('$label goes where it says', (WidgetTester tester) async {
      await openLibrary(tester);
      await tester.tap(find.text('Add recipe'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text(label));
      await pumpFrames(tester, frames: 16);

      expect(
        find.textContaining(lands),
        findsWidgets,
        reason: '$label did not lead anywhere useful',
      );
    });
  }

  testWidgets('and every way in is reachable on the smallest phone', (
    WidgetTester tester,
  ) async {
    // Four rows of prose at three times the text do not fit on a 568-point
    // screen: the last one is not even built. "No exception" is therefore
    // true whether the sheet scrolls or not — an unbuilt row cannot overflow
    // — so this asks for the row instead.
    await pumpHearthApp(tester, size: const Size(320, 568), textScale: 3.0);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Add recipe'));
    await pumpFrames(tester, frames: 12);
    expect(tester.takeException(), isNull);

    await tester.dragUntilVisible(
      find.text('Generate with AI'),
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    await pumpFrames(tester, frames: 4);

    expect(
      find.text('Generate with AI'),
      findsOneWidget,
      reason: 'the last way in cannot be reached at the largest text',
    );
    expect(tester.takeException(), isNull);
  });
}
