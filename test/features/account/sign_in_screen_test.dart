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

  group('forgetting the password (spec §8.3)', () {
    testWidgets('the way out is offered on the screen where you got stuck', (
      WidgetTester tester,
    ) async {
      // The moment a person needs this is the moment they have just failed to
      // sign in. Burying it anywhere else is burying it.
      await pumpSignIn(tester);

      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('it is not offered while creating an account', (
      WidgetTester tester,
    ) async {
      // There is nothing to reset yet, and the row would only be one more
      // thing to read past.
      await pumpSignIn(tester);
      await tester.tap(find.text('Create an account'));
      await tester.pump();

      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('with no email typed it asks for one instead of failing', (
      WidgetTester tester,
    ) async {
      // Nothing has gone wrong — the form is just not finished. An inert
      // button that says nothing looks like a bug.
      final FakeAuthGateway auth = await pumpSignIn(tester);

      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      expect(
        find.textContaining('Type your email above first'),
        findsOneWidget,
      );
      expect(auth.resetsRequested, isEmpty);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('the address is sent trimmed, the way signing in sends it', (
      WidgetTester tester,
    ) async {
      final FakeAuthGateway auth = await pumpSignIn(tester);

      await fillIn(tester, '  cook@example.com  ', '');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      expect(auth.resetsRequested, <String>['cook@example.com']);
    });

    testWidgets('the reply never says whether that address has an account', (
      WidgetTester tester,
    ) async {
      // Otherwise this screen becomes a way to find out who is registered.
      // The gateway cannot tell us either, and that is deliberate.
      await pumpSignIn(tester);

      await fillIn(tester, 'stranger@example.com', '');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      expect(find.textContaining('If there is an account'), findsOneWidget);
    });

    testWidgets('a refusal is shown as an error, not as a reassurance', (
      WidgetTester tester,
    ) async {
      // Rate limiting is the one that actually happens, and telling someone
      // to go and check an inbox that will stay empty is worse than useless.
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.nextFailure = const AuthFailure(
        'That has been asked for a few times just now. Wait a minute and try '
        'again.',
      );

      await fillIn(tester, 'cook@example.com', '');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      expect(find.textContaining('Wait a minute'), findsOneWidget);
      expect(find.textContaining('If there is an account'), findsNothing);
    });

    testWidgets('signing in is barred while the request is in flight', (
      WidgetTester tester,
    ) async {
      final FakeAuthGateway auth = await pumpSignIn(tester);
      auth.gate = Completer<void>();
      await fillIn(tester, 'cook@example.com', '');

      await tester.tap(find.text('Forgot password?'));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      auth.gate!.complete();
      await tester.pump();
    });
  });
}
