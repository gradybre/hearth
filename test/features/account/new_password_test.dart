import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/auth/password_recovery.dart';
import 'package:hearth/features/account/new_password_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fake_auth.dart';

/// Setting a new password on the session a recovery link opened (spec §8.3,
/// R13).
///
/// The rule this is all in aid of: a recovery link does not open a form, it
/// opens a *session*. Supabase signs the user in with it, so without a gate
/// the app opens on their meal plan holding a session minted by an email —
/// and the thing they came to do is three taps away, on a session they cannot
/// use to get back in tomorrow.
void main() {
  late FakeAuthGateway auth;
  late PasswordRecovery recovery;

  setUp(() {
    auth = FakeAuthGateway(signedIn: FakeAuthGateway.anAccount);
    recovery = PasswordRecovery();
  });

  tearDown(() => recovery.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Object>[
          authGatewayProvider.overrideWithValue(auth),
          passwordRecoveryProvider.overrideWithValue(recovery),
        ].cast(),
        child: MaterialApp(
          theme: HearthTheme.light(),
          home: const NewPasswordScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> type(
    WidgetTester tester,
    String password, {
    String? confirm,
  }) async {
    await tester.enterText(find.byType(TextField).first, password);
    await tester.enterText(find.byType(TextField).last, confirm ?? password);
    await tester.pump();
  }

  testWidgets('a password and its repeat reach the gateway', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await type(tester, 'a good long one');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump();

    expect(auth.setPasswords, <String>['a good long one']);
    expect(find.text('Password set'), findsOneWidget);
  });

  testWidgets('and the flag only drops once that has been seen', (
    WidgetTester tester,
  ) async {
    // Clearing it on success would swap this screen for the meal plan in the
    // same frame, and "password set" would be a message nobody ever saw.
    recovery.begin();
    await pump(tester);
    await type(tester, 'a good long one');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump();

    expect(recovery.isPending, isTrue, reason: 'dropped before it was read');

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(recovery.isPending, isFalse);
  });

  testWidgets('two that do not match are refused before the round trip', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await type(tester, 'a good long one', confirm: 'a good long onf');
    await tester.tap(find.text('Save password'));
    await tester.pump();

    expect(find.text('These do not match'), findsOneWidget);
    expect(auth.setPasswords, isEmpty, reason: 'it asked anyway');
  });

  testWidgets('and one too short is too', (WidgetTester tester) async {
    await pump(tester);
    await type(tester, 'short');
    await tester.tap(find.text('Save password'));
    await tester.pump();

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(auth.setPasswords, isEmpty);
  });

  testWidgets('a link that has expired says what to do next', (
    WidgetTester tester,
  ) async {
    // The most likely failure by a distance, and the one where a developer's
    // sentence is worst: somebody locked out of their account reading
    // "AuthApiException: token has expired or is invalid".
    auth.setPasswordFails = 'token has expired or is invalid';
    await pump(tester);
    await type(tester, 'a good long one');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('token has expired'), findsOneWidget);
    expect(
      find.text('Password set'),
      findsNothing,
      reason: 'a refusal must not look like a success',
    );
  });

  testWidgets('leaving without setting one signs the session out', (
    WidgetTester tester,
  ) async {
    // A recovery session that is not going to be used for recovery is not a
    // session anybody asked for. Leaving it standing would mean a link out of
    // an email had quietly logged somebody in.
    recovery.begin();
    await pump(tester);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump();

    expect(auth.signOuts, 1);
    expect(recovery.isPending, isFalse);
  });

  group('the gate (spec §8.3)', () {
    // The rule the whole thing exists for. Everything above is about the
    // screen; this is about the screen being the *only* one reachable.
    testWidgets('a recovery session lands here, not in the meal plan', (
      WidgetTester tester,
    ) async {
      recovery.begin();
      await pumpHearthApp(
        tester,
        extraOverrides: <Object>[
          supabaseReadyProvider.overrideWithValue(true),
          passwordRecoveryProvider.overrideWithValue(recovery),
          authGatewayProvider.overrideWithValue(auth),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Set a new password'), findsOneWidget);
      expect(
        find.text('Recipes'),
        findsNothing,
        reason: 'the app opened on content while holding a recovery session',
      );
    });

    testWidgets('and the app opens normally once it is set', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        extraOverrides: <Object>[
          supabaseReadyProvider.overrideWithValue(true),
          passwordRecoveryProvider.overrideWithValue(recovery),
          authGatewayProvider.overrideWithValue(auth),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Set a new password'), findsNothing);
      expect(find.text('Recipes'), findsWidgets);
    });
  });

  group('a recovery that arrives before anything is listening', () {
    test('is not lost between reading the value and subscribing', () async {
      // The gap an async generator leaves: yield the current value, then
      // subscribe. The stream is a broadcast one, so an event arriving in
      // between goes to nobody — and the value already read was the one from
      // before it. A link handled during startup is exactly when that gap is
      // open, and the cost is the gate never closing.
      final PasswordRecovery flag = PasswordRecovery();
      addTearDown(flag.dispose);
      flag.begin();

      final ProviderContainer container = ProviderContainer(
        overrides: <Object>[passwordRecoveryProvider.overrideWithValue(flag)]
            .cast(),
      );
      addTearDown(container.dispose);

      final List<bool> seen = <bool>[];
      container.listen(passwordRecoveryPendingProvider, (
        AsyncValue<bool>? _,
        AsyncValue<bool> next,
      ) {
        if (next.value case final bool value) seen.add(value);
      }, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);

      expect(
        seen.first,
        isTrue,
        reason: 'the recovery that had already started was never reported',
      );
    });
  });

  group('the fact itself', () {
    test('starts false, and a link turns it on', () {
      final PasswordRecovery flag = PasswordRecovery();
      addTearDown(flag.dispose);
      expect(flag.isPending, isFalse);
      flag.begin();
      expect(flag.isPending, isTrue);
    });

    test('and it re-emits only on a change', () async {
      final PasswordRecovery flag = PasswordRecovery();
      addTearDown(flag.dispose);
      final List<bool> seen = <bool>[];
      flag.watch().listen(seen.add);

      flag.begin();
      flag.begin();
      flag.end();
      await Future<void>.delayed(Duration.zero);

      expect(seen, <bool>[true, false]);
    });
  });
}
