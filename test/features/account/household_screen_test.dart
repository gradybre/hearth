import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/features/account/household_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/fake_auth.dart';
import '../../support/fixtures.dart';

Future<FakeAuthGateway> pumpHousehold(
  WidgetTester tester, {
  HearthDatabase? database,
  FileShare? fileShare,
}) async {
  // Tall enough for the whole screen: it is a ListView, so anything below the
  // fold is simply not built, and a finder cannot scroll to what does not
  // exist.
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final FakeAuthGateway auth = FakeAuthGateway(
    signedIn: FakeAuthGateway.anAccount,
  );
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
        if (database case final HearthDatabase db)
          databaseProvider.overrideWithValue(db),
        if (fileShare case final FileShare share)
          fileShareProvider.overrideWithValue(share),
      ],
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: const HouseholdScreen(),
      ),
    ),
  );
  await tester.pump();
  return auth;
}

void main() {
  group('the share code', () {
    testWidgets('is shown so a partner can type it', (
      WidgetTester tester,
    ) async {
      await pumpHousehold(tester);
      expect(find.text('QRSTUV23'), findsOneWidget);
    });

    testWidgets('is spelled out letter by letter for a screen reader', (
      WidgetTester tester,
    ) async {
      // "QRSTUV23" read as a word is not a code anyone can write down.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHousehold(tester);

      expect(
        find.bySemanticsLabel('Your household code is Q R S T U V 2 3'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('joining', () {
    testWidgets('sends the code that was typed', (WidgetTester tester) async {
      final FakeAuthGateway auth = await pumpHousehold(tester);

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();

      expect(auth.joined, <String>['WXYZ2345']);
    });

    testWidgets('says what joining did, since it is not undoable here', (
      WidgetTester tester,
    ) async {
      await pumpHousehold(tester);

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
      final FakeAuthGateway auth = await pumpHousehold(tester);
      auth.nextFailure = const AuthFailure(
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
      final FakeAuthGateway auth = await pumpHousehold(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(auth.signOuts, 0);
    });

    testWidgets('says the recipes stay behind, because they do', (
      WidgetTester tester,
    ) async {
      // The household owns the library, not the person leaving it (§5.1).
      await pumpHousehold(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('stay in the household'), findsOneWidget);
    });

    testWidgets('signs out when confirmed', (WidgetTester tester) async {
      final FakeAuthGateway auth = await pumpHousehold(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(auth.signOuts, 1);
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
      await pumpHousehold(tester);
      expect(find.text('QRSTUV23'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'WXYZ2345');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      await tester.pump();

      expect(find.text('WXYZ2345'), findsOneWidget);
      expect(find.text('QRSTUV23'), findsNothing);
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
      await pumpHousehold(tester, database: db, fileShare: share);

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
      await pumpHousehold(tester);

      expect(find.textContaining('photos are not included'), findsOneWidget);
    });

    testWidgets('a failure is said out loud, not swallowed', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await pumpHousehold(
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
