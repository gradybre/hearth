import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';

import '../../support/app_harness.dart';

/// The room that leads, and what it offers from the front door (spec §6.2,
/// and the November 2026 templates).
///
/// Four cards of equal weight said something untrue about the house: the
/// rooms are not equal, one of them is the reason the app exists, and the
/// screen read as a menu of four equivalent choices. One hero and three rows
/// says which room you are almost certainly here for without taking the
/// others away.
void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    await pumpHearthApp(tester, size: size, launchTarget: LaunchTarget.home);
    await pumpFrames(tester, frames: 8);
  }

  BuiltSection leader() => builtSections.first;

  testWidgets('the first built room leads, and the rest are rows', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    final Rect hero = tester.getRect(find.text(leader().label));
    for (final BuiltSection other in builtSections.skip(1)) {
      final Rect row = tester.getRect(find.text(other.label));
      expect(
        row.top,
        greaterThan(hero.bottom),
        reason: '${other.label} is not below the room that leads',
      );
      expect(
        row.height,
        lessThan(hero.height),
        reason: '${other.label} is drawn as loud as the hero',
      );
    }
  });

  testWidgets('and only the room with an action is offered one', (
    WidgetTester tester,
  ) async {
    // The point of putting it in the registry: this screen knows that a
    // section may have an action, not which section or what it does. A
    // button on every room would be a row of buttons, and a row of buttons
    // has no primary.
    await pumpHome(tester);

    final int offered = builtSections
        .where((BuiltSection s) => s.primaryAction != null)
        .length;
    expect(find.byType(FilledButton), findsNWidgets(offered));
    expect(leader().primaryAction?.label, isNotNull);
    expect(find.text(leader().primaryAction!.label), findsOneWidget);
  });

  testWidgets('the action logs a meal without entering the room', (
    WidgetTester tester,
  ) async {
    // §5.6: every extra tap is a tax paid three times a day. From the front
    // door it is one tap to the meal and a second to the food.
    await pumpHome(tester);

    await tester.tap(find.text('Log food'));
    await pumpFrames(tester, frames: 16);

    expect(find.text('Log food to'), findsOneWidget);
    // Still at the front door: this opened a sheet, it did not go anywhere.
    expect(find.text('Hearth'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('and the way in is the link, not the whole hero', (
    WidgetTester tester,
  ) async {
    // A hero whose every pixel is a button swallows the button inside it.
    // Pressing the heading has to do nothing, or a press meant for "log a
    // meal" lands on "open the room".
    await pumpHome(tester);

    await tester.tap(find.text(leader().label));
    await pumpFrames(tester, frames: 12);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Hearth'), findsOneWidget);
  });

  testWidgets('the footer names the rooms with nothing in them, and no more', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    final Finder footer = find.textContaining('In development');
    expect(footer, findsOneWidget);
    final String line = tester.widget<Text>(footer).data!;
    for (final AppSection section in appSections) {
      expect(
        line.contains(section.label),
        !section.isFurnished,
        reason: section.isFurnished
            ? '${section.label} has something in it'
            : '${section.label} is empty and is not said to be',
      );
    }
    // Said in a different voice from everything above it: it is a sentence,
    // not a control, and nothing in it can be pressed.
    expect(tester.widget<Text>(footer).style?.fontStyle, FontStyle.italic);
  });

  testWidgets('every room is still a door', (WidgetTester tester) async {
    // The hero took four cards down to one and three rows. None of them was
    // allowed to stop being a way in: a named room you cannot walk into is
    // the wall of promises §6.2 exists to avoid.
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHome(tester);

    for (final AppSection section in appSections) {
      expect(
        find.bySemanticsLabel(section.semanticLabel),
        findsOneWidget,
        reason: '${section.label} has no way in',
      );
    }
    handle.dispose();
  });
}
