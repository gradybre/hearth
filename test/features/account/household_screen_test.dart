import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/features/account/household_screen.dart';

import '../../support/fake_auth.dart';

Future<FakeAuthGateway> pumpHousehold(WidgetTester tester) async {
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
}
