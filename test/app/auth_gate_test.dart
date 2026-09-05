import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/features/account/sign_in_screen.dart';
import 'package:hearth/main.dart';

import '../support/fake_auth.dart';

void main() {
  testWidgets('a re-emitted signed-out account keeps the sign-in screen', (
    WidgetTester tester,
  ) async {
    // The gate used to swap in a spinner whenever the account stream
    // re-emitted, which destroyed the sign-in screen's State — so a failed
    // sign-in wiped the typed email and the error message instead of showing
    // what went wrong.
    final StreamController<HearthAccount?> accounts =
        StreamController<HearthAccount?>();

    // The app root reads the device's theme choice before it paints anything,
    // and that read goes through the database. Without this it would be the
    // on-disk library the developer's own app uses.
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // The app root watches sync, and the real controller registers a
          // lifecycle observer, a debounce timer and a live Drift stream —
          // none of which fake async can drive, and any one of which left
          // running makes teardown hang rather than fail.
          syncControllerProvider.overrideWith(FakeSyncController.new),
          pendingWriteCountProvider.overrideWith(
            (Ref ref) => Stream<int>.value(0),
          ),
          supabaseReadyProvider.overrideWithValue(true),
          authGatewayProvider.overrideWithValue(FakeAuthGateway()),
          accountProvider.overrideWith((Ref ref) => accounts.stream),
        ],
        child: const HearthApp(),
      ),
    );

    accounts.add(null);
    await tester.pump();
    expect(find.byType(SignInScreen), findsOneWidget);

    // Something the user typed, which must survive the next emission.
    await tester.enterText(find.byType(TextField).first, 'cook@example.com');
    await tester.pump();

    accounts.add(null);
    await tester.pump();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(
      find.text('cook@example.com'),
      findsOneWidget,
      reason: 'the form was rebuilt from scratch and lost what was typed',
    );

    await accounts.close();
  });
}
