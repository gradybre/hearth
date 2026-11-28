import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/app/widgets/hearth_marks.dart';
import 'package:hearth/app/widgets/hearth_sketch.dart';

import '../support/app_harness.dart';

/// Where Hearth's own drawings appear, and where they get out of the way
/// (spec §6.1, §6.3, and the November 2026 templates).
///
/// Three marks, drawn from path data rather than shipped as pictures, so
/// they take a theme colour and stay crisp at any size. What they must never
/// do is cost the words anything: they are decoration, they say nothing a
/// screen reader needs, and at accessibility text sizes they go.
void main() {
  Future<void> pumpHome(WidgetTester tester, {double textScale = 1.0}) async {
    await pumpHearthApp(
      tester,
      launchTarget: LaunchTarget.home,
      textScale: textScale,
    );
    await pumpFrames(tester, frames: 8);
  }

  testWidgets('the room that leads is drawn above its name', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    final BuiltSection leader = builtSections.first;
    expect(leader.sketch, isNotNull, reason: 'the leading room has no mark');
    final Rect drawing = tester.getRect(find.byType(HearthSketch).first);
    final Rect name = tester.getRect(find.text(leader.label));
    expect(drawing.bottom, lessThanOrEqualTo(name.top));
  });

  testWidgets('a room with a drawing gets it, and one without gets a glyph', (
    WidgetTester tester,
  ) async {
    // The rooms will not all be drawn on the same day. A row with a gap in
    // it where the others have a mark reads as a row that failed to load.
    await pumpHome(tester);

    final int drawn = appSections
        .where((AppSection s) => s.sketch != null)
        .length;
    expect(find.byType(HearthSketch), findsNWidgets(drawn));
    for (final AppSection section in appSections) {
      if (section.sketch != null) continue;
      expect(
        find.byIcon(section.icon),
        findsOneWidget,
        reason: '${section.label} has neither a drawing nor its glyph',
      );
    }
  });

  testWidgets('and the drawings say nothing out loud', (
    WidgetTester tester,
  ) async {
    // Every sketch sits beside words that already carry the meaning. A
    // screen reader announcing "sketch of a pot" in front of "Nutrition"
    // reads the decoration twice and the room once (spec §6.3).
    await pumpHome(tester);

    for (final Element element in find.byType(HearthSketch).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
        reason: 'a drawing is announcing itself',
      );
    }
  });

  testWidgets('at accessibility text sizes the drawing gives up the room', (
    WidgetTester tester,
  ) async {
    // Decoration is the first thing to go when the words need the space: at
    // three times the text a 150pt drawing above a 102pt heading puts the
    // button that logs a meal off the bottom of a phone.
    await pumpHome(tester, textScale: 3.0);

    final Rect name = tester.getRect(find.text(builtSections.first.label));
    for (final Element element in find.byType(HearthSketch).evaluate()) {
      final RenderBox box = element.renderObject! as RenderBox;
      expect(
        box.localToGlobal(Offset.zero).dy,
        greaterThan(name.top),
        reason: 'the hero is still drawn at three times the text',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sidebar carries the wordmark and the pot', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: const Size(1280, 900));
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Hearth'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is HearthSketch && w.svg == kPotMark,
      ),
      findsWidgets,
    );
  });

  testWidgets('and drops them when the words need the column', (
    WidgetTester tester,
  ) async {
    // "Hearth" is one word and a 208pt rail cannot wrap it. At three times
    // the text the wordmark alone is wider than the column, and the rail is
    // already tight enough that a way home, a section heading and four rows
    // run past the bottom of a 400pt window.
    await pumpHearthApp(tester, size: const Size(1280, 900), textScale: 3.0);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Hearth'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
