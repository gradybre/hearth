import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/app_shell.dart';
import 'package:hearth/app/shell/destinations.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/app/theme/hearth_theme.dart';

import '../../support/app_harness.dart';
import '../../support/fake_kitchen.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) =>
    pumpHearthApp(tester, size: size);

void main() {
  const Size phone = Size(390, 844);
  const Size desktop = Size(1440, 900);

  group('responsive navigation (spec §6.2)', () {
    testWidgets('a phone-width window gets bottom tabs', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a desktop-width window gets the sidebar', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, desktop);
      expect(find.byType(NavigationBar), findsNothing);
      // The sidebar is Hearth's own widget, so it is identified by the
      // destinations it renders rather than by a Material type. Scoped to its
      // semantics, because a screen is entitled to a heading that happens to
      // match a destination name — "Recipes" appears in both.
      for (final AppDestination d in foodDestinations) {
        expect(find.bySemanticsLabel(d.semanticLabel), findsOneWidget);
      }
    });

    testWidgets('a narrow desktop window behaves like a phone', (
      WidgetTester tester,
    ) async {
      // The switch is on width, not platform — a half-width macOS window
      // should not squeeze a sidebar into nothing.
      await _pumpAt(tester, const Size(700, 900));
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('destinations', () {
    testWidgets('all four Food sections are present', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      for (final AppDestination d in foodDestinations) {
        expect(
          find.text(d.label),
          findsWidgets,
          reason: '${d.label} should appear in navigation',
        );
      }
    });

    testWidgets('tapping a destination switches sections', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      // Recipes is the landing section; an empty library is what a new
      // household actually sees (spec §5.8).
      expect(find.text('Your library is empty'), findsOneWidget);

      await tester.tap(find.text('Shopping').last);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Your library is empty'), findsNothing);
      // The real shopping list, since phase 4 — it used to be the honest
      // placeholder, and its copy is what this asserted.
      expect(find.text('Shopping for'), findsOneWidget);
    });

    testWidgets('sections keep their state across tab switches', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      await tester.tap(find.text('Plan').last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Recipes').last);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Your library is empty'), findsOneWidget);
    });
  });

  group('accessibility of the shell (spec §6.3)', () {
    testWidgets('the sidebar labels every destination for a screen reader', (
      WidgetTester tester,
    ) async {
      // Pumped without the router: this is what AppShell itself guarantees.
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        // The shell hosts the app-wide cook timer bar, so it needs a scope
        // even pumped on its own.
        ProviderScope(
          overrides: [cookTimersProvider.overrideWith(FakeCookTimers.new)],
          child: MaterialApp(
            theme: HearthTheme.light(),
            home: AppShell(
              section: builtSections.first,
              currentIndex: 0,
              onDestinationSelected: (_) {},
              onLeaveSection: () {},
              child: const Center(child: Text('content')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      for (final AppDestination d in foodDestinations) {
        expect(
          find.bySemanticsLabel(d.semanticLabel),
          findsOneWidget,
          reason: 'missing spoken label for ${d.label}',
        );
      }
      handle.dispose();
    });

    // Regression guard for a defect that shipped silently once: a nested
    // Navigator (as every go_router shell route creates) emits a `scopesRoute`
    // semantics node that drops sibling nodes, which hid the entire navigation
    // chrome from screen readers while every visual test still passed. The
    // router deliberately avoids nested navigators; this test is what keeps it
    // that way.
    testWidgets(
      'navigation chrome is reachable by a screen reader in the real app',
      (WidgetTester tester) async {
        await _pumpAt(tester, desktop);
        final SemanticsHandle handle = tester.ensureSemantics();

        for (final AppDestination d in foodDestinations) {
          expect(
            find.bySemanticsLabel(d.semanticLabel),
            findsOneWidget,
            reason: 'missing spoken label for ${d.label}',
          );
        }
        handle.dispose();
      },
    );

    testWidgets('bottom tabs meet the minimum touch target', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      final SemanticsHandle handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('rendered text meets the contrast guideline', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, phone);
      final SemanticsHandle handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
