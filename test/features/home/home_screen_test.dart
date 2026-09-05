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

    testWidgets('a section that is not built is named but cannot be tapped', (
      WidgetTester tester,
    ) async {
      // A dead tile teaches people that tapping does nothing, and they carry
      // that lesson into the tiles that work. So the rooms that do not exist
      // yet are one sentence, not a grid of disappointments.
      await pumpHome(tester);
      await pumpFrames(tester);

      final SemanticsHandle handle = tester.ensureSemantics();
      for (final AppSection section in unbuiltSections) {
        expect(
          find.bySemanticsLabel(section.semanticLabel),
          findsNothing,
          reason: '${section.label} announced itself as somewhere to go',
        );
      }
      expect(find.textContaining('Still being built'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the sentence names them, so building one rewrites no copy', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);
      await pumpFrames(tester);

      for (final AppSection section in unbuiltSections) {
        expect(find.textContaining(section.label), findsOneWidget);
      }
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
