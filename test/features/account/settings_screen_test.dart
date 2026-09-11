import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/theme_choice.dart';
import 'package:hearth/core/build_info.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/features/account/settings_kit.dart';
import 'package:hearth/features/account/settings_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/fake_auth.dart';
import '../../support/fixtures.dart';

/// Everything the screen needs, so a test can reach for the one part it is
/// about.
class SettingsHarness {
  SettingsHarness({required this.auth, required this.database});

  final FakeAuthGateway auth;
  final HearthDatabase database;
}

Future<SettingsHarness> pumpSettings(
  WidgetTester tester, {

  /// Which settings screen this test is about.
  ///
  /// There are seven now: an index and the six pages behind it (review §7.8).
  /// Each is pumped on its own rather than driven through the index, because
  /// what these tests are about is the controls; how the index behaves has a
  /// file of its own.
  Widget page = const SettingsScreen(),
  HearthDatabase? database,
  FileShare? fileShare,
  PreferenceStore? preferences,
  HearthAccount? account = FakeAuthGateway.anAccount,

  /// The answer to "when were we last in step?", as a future the test
  /// controls. A real read resolves inside the first pump here, so without a
  /// seam the loading frame is not observable — and a branch no test can
  /// reach is a branch nothing holds.
  Future<DateTime?>? lastFullSync,
}) async {
  // Tall enough for the whole screen: it is a ListView, so anything below the
  // fold is simply not built, and a finder cannot scroll to what does not
  // exist.
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Always a real database, never the developer's own: the appearance section
  // reads the device's stored theme, and without an override that read would
  // open the on-disk library the app itself uses.
  final HearthDatabase db =
      database ?? HearthDatabase.forTesting(NativeDatabase.memory());
  if (database == null) addTearDown(db.close);

  final FakeAuthGateway auth = FakeAuthGateway(signedIn: account);
  await tester.pumpWidget(
    ProviderScope(
      // accountProvider is left wired to the gateway rather than stubbed, so
      // a screen holding a stale account is visible here rather than only on
      // a device.
      overrides: [
        authGatewayProvider.overrideWithValue(auth),
        // The sync panel lives on this screen; neither of these should reach
        // a database or a clock in a widget test.
        syncControllerProvider.overrideWith(FakeSyncController.new),
        pendingWriteCountProvider.overrideWith(
          (Ref ref) => Stream<int>.value(0),
        ),
        // Named seams rather than a generic override list: flutter_riverpod 3
        // does not export the `Override` type, only the methods that make one.
        databaseProvider.overrideWithValue(db),
        if (preferences case final PreferenceStore store)
          preferenceStoreProvider.overrideWithValue(store),
        if (fileShare case final FileShare share)
          fileShareProvider.overrideWithValue(share),
        if (lastFullSync case final Future<DateTime?> answer)
          lastFullSyncProvider.overrideWith((Ref ref) => answer),
      ],
      child: MaterialApp(theme: HearthTheme.light(), home: page),
    ),
  );
  await tester.pump();
  return SettingsHarness(auth: auth, database: db);
}

/// The tick inside one particular answer's row.
///
/// The screen has two lists of mutually exclusive answers now, so counting
/// checks across the whole screen no longer says anything.
Finder tickOn(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(SettingsChoiceRow),
  ),
  matching: find.byIcon(Icons.check),
);

void main() {
  group('how the screen is laid out', () {
    testWidgets('it calls itself Settings, because that is what it is', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('related settings are gathered under named sections', (
      WidgetTester tester,
    ) async {
      // The complaint this screen was rebuilt for was that everything was
      // dumped in one column with nothing to navigate by.
      await pumpSettings(tester);

      for (final String section in <String>[
        'Account',
        'Appearance',
        'Opens on',
        'Cook together',
        'Syncing',
        'Your data',
      ]) {
        expect(find.text(section), findsOneWidget, reason: 'missing $section');
      }
    });

    group('the diagnostics line (handoff §12.3)', () {
      // What a bug report needs and what the panel could not say. Everything
      // else in Syncing describes the *last attempt*; a device that has not
      // managed a full pass since Tuesday looks identical to one that synced a
      // minute ago, because the last attempt failed the same way both times.

      testWidgets('says which build is asking', (WidgetTester tester) async {
        await pumpSettings(tester, page: const SyncSettingsScreen());
        await tester.scrollUntilVisible(
          find.textContaining('Hearth ${BuildInfo.appVersion}'),
          200,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.textContaining('Hearth ${BuildInfo.appVersion}'),
          findsOneWidget,
        );
        expect(
          find.textContaining('data ${BuildInfo.schemaVersion}'),
          findsOneWidget,
          reason:
              'the app version and the schema version come apart — a build that '
              'failed to migrate is the same app on an older schema, which is '
              'exactly the state somebody would be reporting',
        );
      });

      testWidgets('but says nothing about it while it is still being read', (
        WidgetTester tester,
      ) async {
        // Loading is not the same answer as "never". Reported as one, a device
        // that syncs hourly says "no full sync yet" for the frame somebody
        // screenshots — this panel telling the exact kind of lie it exists to
        // prevent.
        // A read that has not answered, held open on purpose. A real one
        // resolves inside the first pump, so the frame that matters is not
        // otherwise reachable from a test.
        await pumpSettings(
          tester,
          page: const SyncSettingsScreen(),
          lastFullSync: Completer<DateTime?>().future,
        );

        expect(
          find.textContaining('No full sync yet'),
          findsNothing,
          reason: 'it answered before it had read the answer',
        );
      });

      testWidgets('and says plainly when there has never been a full sync', (
        WidgetTester tester,
      ) async {
        // The honest answer on a device that has never managed one, and the
        // one a blank would hide.
        await pumpSettings(tester, page: const SyncSettingsScreen());
        await tester.scrollUntilVisible(
          find.textContaining('No full sync yet'),
          200,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.textContaining('No full sync yet'), findsOneWidget);
      });
    });

    testWidgets('an index row says where its setting stands, out loud too', (
      WidgetTester tester,
    ) async {
      // The section headers this used to check are page titles now. What
      // replaced them is a row carrying its own value — and a row that
      // announced "Appearance" and a chevron would have dropped the one thing
      // it was added to say (spec §6.3).
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester);

      expect(
        tester.getSemantics(find.text('Appearance')),
        isSemantics(label: 'Appearance. Follow the device', isButton: true),
      );
      handle.dispose();
    });

    testWidgets('the destructive one is last, under everything else', (
      WidgetTester tester,
    ) async {
      // Sign out sits below export and sync so a mis-tap on the way down the
      // list cannot land on it.
      await pumpSettings(tester);

      // Export is a page of its own now, so what has to be above Sign out is
      // the row that leads to it.
      expect(
        tester.getTopLeft(find.text('Sign out')).dy,
        greaterThan(tester.getTopLeft(find.text('Your data')).dy),
      );
    });
  });

  group('the share code', () {
    testWidgets('is shown so a partner can type it', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester, page: const HouseholdSettingsScreen());
      expect(find.text('QRSTUV23'), findsOneWidget);
    });

    testWidgets('is spelled out letter by letter for a screen reader', (
      WidgetTester tester,
    ) async {
      // "QRSTUV23" read as a word is not a code anyone can write down.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const HouseholdSettingsScreen());

      expect(
        find.bySemanticsLabel('Your household code is Q R S T U V 2 3'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('and the copy button beside it can still be reached', (
      WidgetTester tester,
    ) async {
      // The label above is spoken by a wrapper that excludes its descendants,
      // and the copy button is one of them: a screen-reader user heard the
      // code and then had no way to put it on the clipboard (spec §6.3).
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const HouseholdSettingsScreen());

      expect(
        tester.getSemantics(find.byTooltip('Copy code')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('joining', () {
    testWidgets('sends the code that was typed', (WidgetTester tester) async {
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const HouseholdSettingsScreen(),
      );

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(harness.auth.joined, <String>['WXYZ2345']);
    });

    testWidgets('says what joining did, since it is not undoable here', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester, page: const HouseholdSettingsScreen());

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(find.textContaining('Joined.'), findsOneWidget);
    });

    testWidgets('a bad code is reported without clearing what was typed', (
      WidgetTester tester,
    ) async {
      // Retyping an eight-character code because of one wrong letter is a
      // small cruelty.
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const HouseholdSettingsScreen(),
      );
      harness.auth.nextFailure = const AuthFailure(
        'No household matches that code. Check it and try again.',
      );

      await tester.enterText(find.byType(TextField), 'BADCODE1');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(find.textContaining('No household matches'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'BADCODE1',
      );
    });

    testWidgets('and it is announced, not only printed', (
      WidgetTester tester,
    ) async {
      // A live region with no label of its own announces nothing: the words
      // sit on a child node, and the node flagged live has nothing to say.
      // The person who cannot see the message is the person who most needs
      // to be told the code was refused (spec §6.3).
      const String refusal =
          'No household matches that code. Check it and '
          'try again.';
      final SemanticsHandle handle = tester.ensureSemantics();
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const HouseholdSettingsScreen(),
      );
      harness.auth.nextFailure = const AuthFailure(refusal);

      await tester.enterText(find.byType(TextField), 'BADCODE1');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(
        tester.getSemantics(find.text(refusal)),
        isSemantics(isLiveRegion: true, label: refusal),
      );
      handle.dispose();
    });
  });

  group('signing out', () {
    testWidgets('asks first, and does nothing if you back out', (
      WidgetTester tester,
    ) async {
      final SettingsHarness harness = await pumpSettings(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.auth.signOuts, 0);
    });

    testWidgets('says the recipes stay behind, because they do', (
      WidgetTester tester,
    ) async {
      // The household owns the library, not the person leaving it (§5.1).
      // Said twice on purpose — once on the row, once in the dialog — so this
      // asks the dialog specifically.
      await pumpSettings(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('stay in the household'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('signs out when confirmed', (WidgetTester tester) async {
      final SettingsHarness harness = await pumpSettings(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.auth.signOuts, 1);
    });
  });

  group('after joining', () {
    testWidgets('the code shown is the new household, not the old one', (
      WidgetTester tester,
    ) async {
      // Joining moves the user without touching their session, so nothing in
      // auth fires. A screen left holding the old account goes on showing the
      // previous household's code — and whoever types it lands somewhere else
      // entirely.
      await pumpSettings(tester, page: const HouseholdSettingsScreen());
      expect(find.text('QRSTUV23'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      await tester.pump();

      expect(find.text('WXYZ2345'), findsOneWidget);
      expect(find.text('QRSTUV23'), findsNothing);
    });
  });

  group('choosing light or dark (spec §6.1)', () {
    testWidgets('all three answers are offered, the device among them', (
      WidgetTester tester,
    ) async {
      // "Follow the device" is a real answer, not the absence of one.
      await pumpSettings(tester, page: const AppearanceSettingsScreen());

      for (final ThemeChoice choice in ThemeChoice.values) {
        expect(find.text(choice.label), findsOneWidget);
      }
    });

    testWidgets('a fresh install shows the device as the chosen one', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const AppearanceSettingsScreen());
      await pumpFrames(tester);

      expect(
        tester.getSemantics(find.text(ThemeChoice.system.label)),
        isSemantics(isSelected: true, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('the chosen one is marked, not merely tinted', (
      WidgetTester tester,
    ) async {
      // Which option is chosen has to survive being seen in greyscale
      // (spec §6.3). Scoped to the row rather than counted across the screen:
      // Appearance is now two lists of answers — the theme and the launch
      // screen — and each carries its own tick.
      await pumpSettings(tester, page: const AppearanceSettingsScreen());
      await pumpFrames(tester);

      expect(tickOn(ThemeChoice.system.label), findsOneWidget);
      expect(tickOn(ThemeChoice.dark.label), findsNothing);
    });

    testWidgets('picking dark writes it to the device, not to the household', (
      WidgetTester tester,
    ) async {
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const AppearanceSettingsScreen(),
      );
      await pumpFrames(tester);

      await tester.tap(find.text(ThemeChoice.dark.label));
      await pumpFrames(tester);

      expect(
        await PreferenceStore(harness.database)
            .read(PreferenceStore.themeChoice),
        'dark',
      );
    });

    testWidgets('and the tick moves to it', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const AppearanceSettingsScreen());
      await pumpFrames(tester);

      await tester.tap(find.text(ThemeChoice.dark.label));
      await pumpFrames(tester);

      expect(
        tester.getSemantics(find.text(ThemeChoice.dark.label)),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.text(ThemeChoice.system.label)),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('a choice that could not be saved goes back and says so', (
      WidgetTester tester,
    ) async {
      // The tick used to move and stay moved even when the write failed, so
      // the app was dark until the next launch and then quietly light again
      // with nothing ever said about it.
      final SemanticsHandle handle = tester.ensureSemantics();
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await pumpSettings(
        tester,
        page: const AppearanceSettingsScreen(),
        database: db,
        preferences: UnwritablePreferences(db),
      );
      await pumpFrames(tester);

      await tester.tap(find.text(ThemeChoice.dark.label));
      await pumpFrames(tester);

      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(
        tester.getSemantics(find.text(ThemeChoice.system.label)),
        isSemantics(isSelected: true),
        reason: 'dark stayed ticked though nothing was written',
      );
      handle.dispose();
    });
  });

  group('choosing where Hearth opens (spec §6.2)', () {
    testWidgets('the home screen and every built section are offered', (
      WidgetTester tester,
    ) async {
      // Read off the section registry rather than listed here, so a pillar
      // added later offers itself without this screen being touched.
      await pumpSettings(tester, page: const StartSettingsScreen());

      for (final LaunchTarget target in LaunchTarget.options) {
        expect(find.text(target.label), findsOneWidget);
      }
      expect(
        find.text('Nutrition'),
        findsOneWidget,
        reason: 'the one built section should be offerable as a landing',
      );
    });

    testWidgets('a device that has never said lands on the home screen', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const StartSettingsScreen());
      await pumpFrames(tester);

      expect(tickOn(LaunchTarget.home.label), findsOneWidget);
      expect(
        tester.getSemantics(find.text(LaunchTarget.home.label)),
        isSemantics(isSelected: true, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('picking Nutrition writes it to the device, not the '
        'household', (WidgetTester tester) async {
      // The whole point of it being device-local: one person opening straight
      // into Nutrition must not move where their partner's app opens.
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const StartSettingsScreen(),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);

      expect(
        await PreferenceStore(harness.database)
            .read(PreferenceStore.launchTarget),
        'section:nutrition',
      );
    });

    testWidgets('and the tick moves to it', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester, page: const StartSettingsScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);

      expect(tickOn('Nutrition'), findsOneWidget);
      expect(tickOn(LaunchTarget.home.label), findsNothing);
      handle.dispose();
    });

    testWidgets('a choice that could not be saved goes back and says so', (
      WidgetTester tester,
    ) async {
      // Nothing on screen moves when this is chosen — the whole of it happens
      // on the next launch — so a silently failed write would show as a tick
      // that lied until the app was next opened and then lied differently.
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await pumpSettings(
        tester,
        page: const StartSettingsScreen(),
        database: db,
        preferences: UnwritablePreferences(db),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);

      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(tickOn(LaunchTarget.home.label), findsOneWidget);
      expect(tickOn('Nutrition'), findsNothing);
    });

    testWidgets('it says the choice is this device only', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester, page: const StartSettingsScreen());
      expect(find.textContaining('This device only'), findsOneWidget);
    });
  });

  group('resetting the password (spec §8.3)', () {
    Future<void> tapReset(WidgetTester tester) async {
      await tester.tap(find.text('Reset password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('asks before mailing anyone, and names the address', (
      WidgetTester tester,
    ) async {
      // A stray tap in a settings list should not put a password-reset email
      // in front of someone.
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const AccountSettingsScreen(),
      );

      await tapReset(tester);

      expect(find.textContaining('cook@example.com'), findsWidgets);
      expect(harness.auth.resetsRequested, isEmpty);
    });

    testWidgets('backing out sends nothing', (WidgetTester tester) async {
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const AccountSettingsScreen(),
      );

      await tapReset(tester);
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);

      expect(harness.auth.resetsRequested, isEmpty);
    });

    testWidgets('confirming sends it to the address you are signed in as', (
      WidgetTester tester,
    ) async {
      // Never to something typed here: the point of the flow is that the
      // person holding the inbox is the person who gets to change it.
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const AccountSettingsScreen(),
      );

      await tapReset(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(harness.auth.resetsRequested, <String>['cook@example.com']);
      // And says so, which is what lets a refusal here explain itself: it
      // cannot tell this person anything about their own account that they do
      // not already know.
      expect(harness.auth.resetsClaimedAsOwn, <bool>[true]);
    });

    testWidgets('and says the next step is in an inbox, not here', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester, page: const AccountSettingsScreen());

      await tapReset(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(find.textContaining('On its way'), findsOneWidget);
    });

    testWidgets('and says where the link lands, since it is not in Hearth', (
      WidgetTester tester,
    ) async {
      // Nothing here listens for a recovery session and no redirect is asked
      // for, so the link opens whatever web page the project points at. Copy
      // that says "open the link to set a new password" describes a second
      // half of this flow that does not exist yet.
      await pumpSettings(tester, page: const AccountSettingsScreen());

      await tapReset(tester);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('browser'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(find.textContaining('in your browser'), findsOneWidget);
    });

    testWidgets('a refusal is said out loud rather than swallowed', (
      WidgetTester tester,
    ) async {
      // Rate limiting is the realistic one, and a silent no-op would have
      // someone waiting on an email that was never sent.
      final SettingsHarness harness = await pumpSettings(
        tester,
        page: const AccountSettingsScreen(),
      );
      harness.auth.nextFailure = const AuthFailure(
        'That has been asked for a few times just now. Wait a minute and try '
        'again.',
      );

      await tapReset(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(find.textContaining('Wait a minute'), findsOneWidget);
    });

    testWidgets('is not offered at all when there is no address to send to', (
      WidgetTester tester,
    ) async {
      // An unconfigured build signs you in as a local account with no email
      // and no backend. A row that could only ever fail is worse than none.
      await pumpSettings(
        tester,
        page: const AccountSettingsScreen(),
        account: const HearthAccount(
          userId: 'local-user',
          householdId: 'local-household',
          email: '',
        ),
      );

      expect(find.text('Reset password'), findsNothing);
      // The row stays, and says the true thing instead of an empty one. On
      // the old single page an account with nothing to say was best left out;
      // a page called Account with nothing on it about the account is not.
      expect(find.text('This device only'), findsOneWidget);
    });
  });

  group('taking your data with you (spec §7.4)', () {
    testWidgets('the export reaches the share sheet, with real content', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await RecipeStore(db).upsert(
        aRecipe(id: 'recipe-1', title: 'Chilli'),
        updatedAt: DateTime.utc(2026, 9, 3),
      );

      final FakeFileShare share = FakeFileShare();
      await pumpSettings(
        tester,
        page: const DataSettingsScreen(),
        database: db,
        fileShare: share,
      );

      await tester.tap(find.text('Export my data'));
      await pumpFrames(tester, frames: 20);

      expect(share.shared, isNotNull);
      expect(share.shared!.name, endsWith('.json'));
      final Map<String, Object?> json =
          jsonDecode(share.shared!.contents) as Map<String, Object?>;
      expect(json['format'], 'hearth-export');
      expect(json['recipes'], hasLength(1));
    });

    testWidgets('and it says photos are not in it before you tap', (
      WidgetTester tester,
    ) async {
      // Discovering that afterwards, from a file, would be too late.
      await pumpSettings(tester, page: const DataSettingsScreen());

      expect(find.textContaining('photos are not included'), findsOneWidget);
    });

    testWidgets('a failure is said out loud, not swallowed', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await pumpSettings(
        tester,
        page: const DataSettingsScreen(),
        database: db,
        fileShare: FakeFileShare(failWith: StateError('no share sheet')),
      );

      await tester.tap(find.text('Export my data'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('no share sheet'), findsOneWidget);
    });
  });
}

/// A share sheet that remembers what it was handed.
class FakeFileShare implements FileShare {
  FakeFileShare({this.failWith});

  final Object? failWith;
  ExportedFile? shared;

  @override
  Future<void> share(ExportedFile file) async {
    if (failWith case final Object error) throw error;
    shared = file;
  }
}

/// A device whose preference table refuses to be written to.
class UnwritablePreferences extends PreferenceStore {
  UnwritablePreferences(super.db);

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('the disk said no');
}
