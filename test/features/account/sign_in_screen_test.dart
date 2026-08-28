import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/features/account/sign_in_screen.dart';

import '../../support/fake_auth.dart';

Future<FakeAuthGateway> pumpSignIn(
  WidgetTester tester, {
  bool requiresConfirmation = false,
}) async {
  final FakeAuthGateway auth = FakeAuthGateway(
    requiresConfirmation: requiresConfirmation,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authGatewayProvider.overrideWithValue(auth)],
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: const SignInScreen(),
      ),
    ),
  );
  await tester.pump();
  return auth;
}

Future<void> fillIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.enterText(find.byType(TextField).last, password);
  await tester.pump();
}

void main() {
  group('signing in', () {
    testWidgets('opens on sign in, not on account creation', (
      WidgetTester tester,
    ) async {
      // Most openings are a returning user; the rarer case is the one that
      // should cost an extra tap.
      await pumpSignIn(tester);

      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('a wrong password is said plainly, without saying which half', (
      WidgetTester tester,
    ) async {
      // Naming which of the two was wrong is free information for someone
      // guessing at an address.
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.nextFailure = const AuthFailure(
        'That email and password do not match an account.',
      );

      await fillIn(tester, 'cook@example.com', 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(
        find.text('That email and password do not match an account.'),
        findsOneWidget,
      );
    });

    testWidgets('the failure is announced, not just coloured', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.nextFailure = const AuthFailure('Nope.');

      await fillIn(tester, 'cook@example.com', 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.bySemanticsLabel('Nope.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the button is inert while the request is in flight', (
      WidgetTester tester,
    ) async {
      // Otherwise an impatient double tap is two sign-up attempts, and the
      // second one fails with "already registered".
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.gate = Completer<void>();
      await fillIn(tester, 'cook@example.com', 'a-long-password-1A');

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Just a moment…'), findsOneWidget);

      auth.gate!.complete();
      await tester.pump();
    });
  });

  group('creating an account', () {
    testWidgets('says what the password has to be before it is rejected', (
      WidgetTester tester,
    ) async {
      await pumpSignIn(tester);
      await tester.tap(find.text('Create an account'));
      await tester.pump();

      expect(find.textContaining('At least 12 characters'), findsOneWidget);
    });

    testWidgets('an unconfirmed sign-up is a notice, not an error', (
      WidgetTester tester,
    ) async {
      // The account exists. Treating it as a failure sends the user round
      // again to make a second one.
      await pumpSignIn(tester, requiresConfirmation: true);
      await tester.tap(find.text('Create an account'));
      await tester.pump();

      await fillIn(tester, 'cook@example.com', 'a-long-password-1A');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.textContaining('Check your email'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('switching back to sign in clears the message', (
      WidgetTester tester,
    ) async {
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.nextFailure = const AuthFailure('Nope.');
      await fillIn(tester, 'cook@example.com', 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Nope.'), findsOneWidget);

      await tester.tap(find.text('Create an account'));
      await tester.pump();

      expect(find.text('Nope.'), findsNothing);
    });
  });
}
