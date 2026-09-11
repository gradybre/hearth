import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/features/account/settings_kit.dart';

import '../../support/app_harness.dart';

/// Settings as an index rather than as a page (review §7.8, §6.2.4, §6.2.7).
///
/// The complaint, measured off the widget tree before any of this was
/// written: 1,920 points of content in a 788-point phone viewport, and 6,641
/// points in the 512-point viewport of a small phone at twice the text —
/// thirteen screens, with Sign out at the bottom of them. Every theme and
/// every start screen was expanded at once, each with a sentence explaining
/// the word above it, and on a 1280-point desktop the rows ran the full width
/// of the window.
void main() {
  Future<void> openSettings(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    SyncStatus? sync,
    int queued = 0,
  }) async {
    await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      syncStatus: sync,
      pendingWrites: queued,
    );
    await tester.tap(find.byTooltip('Settings').last);
    await pumpFrames(tester, frames: 12);
  }

  /// The settings page's own scroll position.
  ///
  /// Named rather than `Scrollable.last`: the shell underneath has scrollables
  /// of its own, and a height assertion that measured a tab bar would pass
  /// whatever this page did.
  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  group('the index is short enough to read', () {
    testWidgets('it fits a phone without scrolling at all', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);

      final ScrollPosition position = positionOf(tester);
      expect(
        position.maxScrollExtent,
        0,
        reason:
            'the index runs ${position.maxScrollExtent} points past a '
            '${position.viewportDimension}-point screen',
      );
    });

    testWidgets('and stays inside two screens at twice the text', (
      WidgetTester tester,
    ) async {
      // The case that was hopeless: thirteen viewports, and the way out of
      // the app at the far end of them. Dynamic type is honoured rather than
      // capped (spec §6.3), so what has to give is the number of rows.
      await openSettings(tester, size: const Size(320, 568), scale: 2);

      final ScrollPosition position = positionOf(tester);
      expect(
        position.maxScrollExtent,
        lessThan(position.viewportDimension),
        reason:
            'the index is '
            '${(position.maxScrollExtent + position.viewportDimension) / position.viewportDimension}'
            ' screens tall',
      );
    });
  });

  group('what the index says', () {
    testWidgets('one row per group, each saying where it stands', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);

      for (final String row in <String>[
        'Account',
        'Cook together',
        'Appearance',
        'Opens on',
        'Syncing',
        'Your data',
      ]) {
        expect(find.text(row), findsOneWidget, reason: '$row is not a row');
      }
      // The value beside the row is the point of an index: it answers "how is
      // this device set up" without anything being opened.
      expect(find.text('Follow the device'), findsOneWidget);
    });

    testWidgets('and no answer is expanded on it', (WidgetTester tester) async {
      await openSettings(tester);

      // The other two theme answers, and the prose under all three.
      expect(find.text('Light'), findsNothing);
      expect(find.text('Dark'), findsNothing);
      expect(
        find.textContaining('Paper cream'),
        findsNothing,
        reason: 'a sentence explaining the word "Light" is the word twice',
      );
      expect(find.textContaining('The day you are in'), findsNothing);
    });

    testWidgets('sign out is still here, and still last', (
      WidgetTester tester,
    ) async {
      // Two taps away would be worse, not better: it is the one thing on this
      // screen somebody needs in a hurry, and it is already alone at the
      // bottom where nothing else can be hit by mistake.
      await openSettings(tester);

      expect(find.text('Sign out'), findsOneWidget);
      final double signOut = tester.getTopLeft(find.text('Sign out')).dy;
      for (final String above in <String>['Account', 'Your data']) {
        expect(tester.getTopLeft(find.text(above)).dy, lessThan(signOut));
      }
    });
  });

  group('the pages behind it', () {
    testWidgets('appearance holds the three answers, and the tick', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Appearance'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Follow the device'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('opens-on keeps the words that say whose app moves', (
      WidgetTester tester,
    ) async {
      // Not narration: it is the answer to "will this change my partner's
      // phone", and the answer is no. §6.2.4 asks for repeated explanation to
      // go and for consequences to stay where the consequence is.
      await openSettings(tester);
      await tester.tap(find.text('Opens on'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Today'), findsOneWidget);
      expect(find.textContaining('This device only'), findsOneWidget);
    });

    testWidgets('cook together keeps the words that say what joining does', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Cook together'));
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('your libraries become one'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('and going back lands on the index, not out of settings', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Appearance'));
      await pumpFrames(tester, frames: 12);
      await tester.pageBack();
      await pumpFrames(tester, frames: 12);

      expect(find.text('Syncing'), findsOneWidget);
    });
  });

  testWidgets('a desktop window does not stretch the rows across it', (
    WidgetTester tester,
  ) async {
    // §6.2.7, and the same answer the four section screens got: a window is
    // as wide as somebody dragged it and a row of settings is not.
    await openSettings(tester, size: const Size(1280, 900));

    // The card the rows sit in, and the list that holds it. Both, because a
    // bounded card inside an unbounded list would still be a row of settings
    // laid across a metre of desk, and measuring only the inner box is how
    // that would pass.
    final double card = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Appearance'),
                matching: find.byType(SettingsGroup),
              )
              .first,
        )
        .width;
    final double list = tester
        .getSize(
          find.descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(ListView),
          ),
        )
        .width;

    expect(
      list,
      lessThanOrEqualTo(HearthLayout.readingWidth),
      reason: 'the settings list is $list points wide',
    );
    expect(card, lessThanOrEqualTo(list));
  });

  group('the syncing row', () {
    testWidgets('leads with the problem rather than the last good pass', (
      WidgetTester tester,
    ) async {
      // A sync that fails quietly is a sync nobody fixes (spec §7.1), and the
      // index is the screen people look at now. A device that has stopped
      // being able to send must not read as a device that is fine.
      await openSettings(
        tester,
        sync: const SyncStatus.failed('the server said no'),
      );

      expect(find.textContaining('the server said no'), findsOneWidget);
    });

    testWidgets('and says what is waiting when nothing has failed', (
      WidgetTester tester,
    ) async {
      // §7.8's own sketch asks for "Last synced … · Pending …". Writes queued
      // behind a lift with no signal are not a failure, but they are still
      // the reason a partner has not seen tonight's plan.
      await openSettings(tester, queued: 3);

      expect(find.textContaining('3 waiting'), findsOneWidget);
    });

    testWidgets('and falls back to when it was last in step', (
      WidgetTester tester,
    ) async {
      await openSettings(tester);

      expect(find.textContaining('No full sync yet'), findsOneWidget);
    });
  });
}
