import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
      // The real shopping list, since phase 4. Its empty state is the copy
      // asserted here — it no longer opens on a date range (spec §5.7).
      expect(find.text('Nothing on the list yet.'), findsOneWidget);
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

  group('a room with a single tab', () {
    // House has one destination (spec §11), and `NavigationBar` asserts
    // it has at least two. So the shell drew nothing at all rather than a
    // thermostat: an assertion in the bottom bar takes the body down with it,
    // and `/thermostat` rendered zero widgets of text.
    //
    // Driven through the router because the harness opens on Recipes and the
    // way to another room is the route, not a tab.
    Future<void> goToTheHouse(WidgetTester tester, Size size) async {
      await _pumpAt(tester, size);
      await pumpFrames(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/thermostat');
      await pumpFrames(tester, frames: 10);
    }

    testWidgets('opens its screen on a phone rather than a blank page', (
      WidgetTester tester,
    ) async {
      await goToTheHouse(tester, phone);

      expect(find.text('Thermostat'), findsWidgets);
    });

    testWidgets('and shows no tab bar, which could only say where you are', (
      WidgetTester tester,
    ) async {
      // One tab is a row with nothing to choose. The section bar above the
      // content already names the room and carries the way out of it, so
      // there is nothing lost by leaving the bar off.
      await goToTheHouse(tester, phone);

      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('while a wide window keeps its sidebar', (
      WidgetTester tester,
    ) async {
      // The sidebar builds a row per destination and asserts nothing, so one
      // tab is a rail with one row — and it still carries the way home and
      // the way into Settings, which is most of what it is for.
      await goToTheHouse(tester, desktop);

      expect(find.text('Thermostat'), findsWidgets);
      expect(
        find.bySemanticsLabel(houseDestinations.single.semanticLabel),
        findsOneWidget,
      );
      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('the inset the OS reserves at the top of the screen', () {
    // A phone with a notch. Every one of the four tab screens is a Scaffold
    // with a SafeArea body and no app bar, so the shell must not hand them a
    // MediaQuery that still has the status bar in it — its own section bar has
    // already stood clear of it.
    const EdgeInsets notch = EdgeInsets.only(top: 47);

    /// The library's own heading, which is the topmost thing a section screen
    /// draws. Scoped to the shell's content slot, because "Recipes" is also
    /// the name of a tab.
    final Finder header = find.descendant(
      of: find.byType(IndexedStack),
      matching: find.text('Recipes'),
    );

    testWidgets('is spent once, not once by the shell and again by the '
        'screen inside it', (WidgetTester tester) async {
      await _pumpAt(tester, phone);
      await pumpFrames(tester);
      final double flat = tester.getTopLeft(header).dy;

      await pumpHearthApp(tester, size: phone, viewPadding: notch);
      await pumpFrames(tester);
      final double inset = tester.getTopLeft(header).dy;

      // The whole layout moves down by the status bar, once. Twice — which is
      // what shipped — is 94, and looks like a stray band of empty paper above
      // every screen in the app.
      expect(
        inset - flat,
        notch.top,
        reason:
            'the status bar inset was applied ${(inset - flat) / notch.top}'
            ' times',
      );
    });

    testWidgets('because the shell spends it and passes on what is left', (
      WidgetTester tester,
    ) async {
      // The guarantee behind the measurement above, stated where a future
      // reader will find it: whatever the shell draws its section bar clear
      // of, the screen below must not be asked to clear again.
      await pumpHearthApp(tester, size: phone, viewPadding: notch);
      await pumpFrames(tester);

      final MediaQueryData inner = MediaQuery.of(
        tester.element(find.byType(IndexedStack)),
      );
      expect(inner.padding.top, 0);
    });

    testWidgets('and the sidebar layout is left alone, having never doubled '
        'it', (WidgetTester tester) async {
      await pumpHearthApp(tester, size: desktop, viewPadding: notch);
      await pumpFrames(tester);

      // No horizontal bar above the content on a desktop window, so the
      // section screen keeps its own status-bar inset to spend.
      final MediaQueryData inner = MediaQuery.of(
        tester.element(find.byType(IndexedStack)),
      );
      expect(inner.padding.top, notch.top);
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
