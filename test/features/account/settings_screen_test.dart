import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/theme_choice.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
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
  HearthDatabase? database,
  FileShare? fileShare,
  HearthAccount? account = FakeAuthGateway.anAccount,
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
        if (fileShare case final FileShare share)
          fileShareProvider.overrideWithValue(share),
      ],
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return SettingsHarness(auth: auth, database: db);
}

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
        'Cook together',
        'Syncing',
        'Your data',
      ]) {
        expect(find.text(section), findsOneWidget, reason: 'missing $section');
      }
    });

    testWidgets('sections are headings, so they can be jumped between', (
      WidgetTester tester,
    ) async {
      // A screen reader should be able to skip to Appearance rather than
      // reading every row above it (spec §6.3).
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester);

      expect(
        tester.getSemantics(find.text('Appearance')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the destructive one is last, under everything else', (
      WidgetTester tester,
    ) async {
      // Sign out sits below export and sync so a mis-tap on the way down the
      // list cannot land on it.
      await pumpSettings(tester);

      expect(
        tester.getTopLeft(find.text('Sign out')).dy,
        greaterThan(tester.getTopLeft(find.text('Export my data')).dy),
      );
    });
  });

  group('the share code', () {
    testWidgets('is shown so a partner can type it', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);
      expect(find.text('QRSTUV23'), findsOneWidget);
    });

    testWidgets('is spelled out letter by letter for a screen reader', (
      WidgetTester tester,
    ) async {
      // "QRSTUV23" read as a word is not a code anyone can write down.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester);

      expect(
        find.bySemanticsLabel('Your household code is Q R S T U V 2 3'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('joining', () {
    testWidgets('sends the code that was typed', (WidgetTester tester) async {
      final SettingsHarness harness = await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(harness.auth.joined, <String>['WXYZ2345']);
    });

    testWidgets('says what joining did, since it is not undoable here', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

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
      final SettingsHarness harness = await pumpSettings(tester);
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
      await pumpSettings(tester);
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
      await pumpSettings(tester);

      for (final ThemeChoice choice in ThemeChoice.values) {
        expect(find.text(choice.label), findsOneWidget);
      }
    });

    testWidgets('a fresh install shows the device as the chosen one', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpSettings(tester);
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
      // (spec §6.3).
      await pumpSettings(tester);
      await pumpFrames(tester);

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('picking dark writes it to the device, not to the household', (
      WidgetTester tester,
    ) async {
      final SettingsHarness harness = await pumpSettings(tester);
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
      await pumpSettings(tester);
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
      final SettingsHarness harness = await pumpSettings(tester);

      await tapReset(tester);

      expect(find.textContaining('cook@example.com'), findsWidgets);
      expect(harness.auth.resetsRequested, isEmpty);
    });

    testWidgets('backing out sends nothing', (WidgetTester tester) async {
      final SettingsHarness harness = await pumpSettings(tester);

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
      final SettingsHarness harness = await pumpSettings(tester);

      await tapReset(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(harness.auth.resetsRequested, <String>['cook@example.com']);
    });

    testWidgets('and says the next step is in an inbox, not here', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      await tapReset(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await pumpFrames(tester);

      expect(find.textContaining('On its way'), findsOneWidget);
    });

    testWidgets('a refusal is said out loud rather than swallowed', (
      WidgetTester tester,
    ) async {
      // Rate limiting is the realistic one, and a silent no-op would have
      // someone waiting on an email that was never sent.
      final SettingsHarness harness = await pumpSettings(tester);
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
        account: const HearthAccount(
          userId: 'local-user',
          householdId: 'local-household',
          email: '',
        ),
      );

      expect(find.text('Reset password'), findsNothing);
      expect(find.text('Signed in as'), findsNothing);
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
      await pumpSettings(tester, database: db, fileShare: share);

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
      await pumpSettings(tester);

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
