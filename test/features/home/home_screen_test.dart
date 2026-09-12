import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';

import '../../support/app_harness.dart';

Future<void> pumpHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) => pumpHearthApp(tester, size: size, launchTarget: LaunchTarget.home);

void main() {
  group('the way into the house (spec §6.2)', () {
    testWidgets('the app can open on it', (WidgetTester tester) async {
      await pumpHome(tester);
      await pumpFrames(tester);

      expect(find.text('Hearth'), findsOneWidget);
      // No section chrome: the home screen is above the shell, not inside it.
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('every built section is offered as a way in', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);
      await pumpFrames(tester);

      for (final AppSection section in builtSections) {
        expect(find.text(section.label), findsOneWidget);
        expect(find.text(section.blurb), findsOneWidget);
      }
    });

    testWidgets('every section on the home screen is somewhere you can go', (
      WidgetTester tester,
    ) async {
      // A dead tile teaches people that tapping does nothing, and they carry
      // that lesson into the tiles that work. Every room has its tabs now, so
      // every card announces itself and every card opens — what is unfinished
      // is said on the screen behind it, not by a card that refuses.
      await pumpHome(tester);
      await pumpFrames(tester);

      final SemanticsHandle handle = tester.ensureSemantics();
      for (final AppSection section in appSections) {
        expect(
          find.bySemanticsLabel(section.semanticLabel),
          findsOneWidget,
          reason: '${section.label} is not on the home screen',
        );
      }
      handle.dispose();
    });

    testWidgets('and the empty rooms are still named as empty', (
      WidgetTester tester,
    ) async {
      // Four identical cards, three of them opening on "Not built yet.", is
      // less honest than the wall of promises the footer was written to
      // avoid. Giving the rooms tabs took that footer away with it, because
      // it read `unbuiltSections` — which is now permanently empty — and
      // nothing replaced it. So it asks the rooms whether anything is behind
      // their tabs instead.
      await pumpHome(tester);
      await pumpFrames(tester);

      expect(find.textContaining('Still being built'), findsOneWidget);
      for (final AppSection section in appSections) {
        expect(
          find.textContaining(section.label),
          section.isFurnished ? findsOneWidget : findsNWidgets(2),
          reason: section.isFurnished
              ? '${section.label} is furnished and should be named once'
              : '${section.label} should be on a card and in the footer',
        );
      }
    });

    testWidgets('which is asked of the screens, not of a flag', (
      WidgetTester tester,
    ) async {
      // The same reason `isBuilt` is derived: a boolean saying "furnished"
      // can disagree with a room whose every tab draws the placeholder, and
      // the one that would be believed is the boolean.
      expect(
        appSections
            .where((AppSection s) => s.isFurnished)
            .map((AppSection s) => s.id),
        <String>['nutrition', 'home'],
        reason: 'House is furnished now that the thermostat is a real screen',
      );
    });

    testWidgets('tapping Nutrition goes into the section', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);

      // Landed on the section's first tab, with its own tabs under it.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Your library is empty'), findsOneWidget);
    });

    testWidgets('settings are reachable from here, since they are the app\'s '
        'and not one room\'s', (WidgetTester tester) async {
      await pumpHome(tester, size: const Size(500, 2400));
      await pumpFrames(tester);

      await tester.tap(find.byTooltip('Settings'));
      await pumpFrames(tester);

      expect(find.text('Appearance'), findsOneWidget);
    });
  });

  group('accessibility of the home screen (spec §6.3)', () {
    testWidgets('each way in says what room it opens', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHome(tester);
      await pumpFrames(tester);

      for (final AppSection section in builtSections) {
        expect(find.bySemanticsLabel(section.semanticLabel), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('the cards meet the minimum touch target', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHome(tester);
      await pumpFrames(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('rendered text meets the contrast guideline', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHome(tester);
      await pumpFrames(tester);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    for (final Brightness brightness in Brightness.values) {
      final String theme = brightness == Brightness.light ? 'light' : 'dark';
      for (final double scale in <double>[1.0, 2.0, 3.0]) {
        testWidgets('it survives ${scale}x text in $theme', (
          WidgetTester tester,
        ) async {
          // Dynamic type is honoured, not capped: the layout gives way, the
          // text does not stop growing.
          await pumpHearthApp(
            tester,
            launchTarget: LaunchTarget.home,
            textScale: scale,
            brightness: brightness,
          );
          await pumpFrames(tester);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('on a wide window (spec §6.2)', () {
    testWidgets('the column stops widening rather than stretching a card '
        'across the desk', (WidgetTester tester) async {
      await pumpHome(tester, size: const Size(1440, 900));
      await pumpFrames(tester);

      final double width = tester.getSize(find.byType(ListView).first).width;
      expect(width, lessThanOrEqualTo(640));
    });
  });
}
