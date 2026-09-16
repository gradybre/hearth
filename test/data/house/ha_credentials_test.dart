import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/house/ha_credentials.dart';

/// A bearer credential for somebody's house
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.2).
void main() {
  const HaCredentialScope scope = HaCredentialScope(
    userId: 'user-a',
    householdId: 'house-1',
    connectionId: 'conn-1',
  );
  // Obviously not a real one. `no_secrets_committed_test` scans for the shapes
  // real credentials take, and a fixture has to say it is a fixture.
  const String token = 'NOT_A_REAL_TOKEN_example_ha_long_lived';

  late _FakeVault storage;
  late HaCredentialStore store;

  setUp(() {
    storage = _FakeVault();
    store = HaCredentialStore(vault: storage);
  });

  group('a token goes to the keychain and nowhere else', () {
    test('and comes back', () async {
      await store.write(scope, token);
      expect(await store.read(scope), token);
    });

    test('under a key that is not the Supabase session key', () async {
      // §5.2: separately keyed, so signing out of Hearth and losing a house
      // are separate events.
      await store.write(scope, token);
      expect(storage.values.keys.single, isNot('hearth.supabase.session'));
      expect(storage.values.keys.single, startsWith('hearth.ha.token/'));
    });

    test('and an empty token is refused rather than stored', () async {
      // An empty string reads back as a present credential and then fails at
      // the server as an auth error, which sends somebody looking in
      // completely the wrong place.
      expect(
        () => store.write(scope, ''),
        throwsA(isA<HaCredentialException>()),
      );
      expect(storage.values, isEmpty);
    });
  });

  group('every context gets its own', () {
    test(
      'a different person on the same phone cannot read the first',
      () async {
        await store.write(scope, token);
        const HaCredentialScope other = HaCredentialScope(
          userId: 'user-b',
          householdId: 'house-1',
          connectionId: 'conn-1',
        );
        expect(await store.read(other), isNull);
      },
    );

    test('and neither can the same person in another household', () async {
      await store.write(scope, token);
      const HaCredentialScope moved = HaCredentialScope(
        userId: 'user-a',
        householdId: 'house-2',
        connectionId: 'conn-1',
      );
      expect(await store.read(moved), isNull);
    });

    test(
      'and a replacement connection does not collide with the old',
      () async {
        // What makes "replace the token" safe: the new one is written under a
        // new id, so the old one is still there to fall back to until the new
        // one has proved itself.
        await store.write(scope, token);
        const HaCredentialScope replacement = HaCredentialScope(
          userId: 'user-a',
          householdId: 'house-1',
          connectionId: 'conn-2',
        );
        await store.write(replacement, 'NOT_A_REAL_TOKEN_second');

        expect(await store.read(scope), token);
        expect(await store.read(replacement), 'NOT_A_REAL_TOKEN_second');
      },
    );
  });

  group('forgetting', () {
    test('one connection leaves the others alone', () async {
      const HaCredentialScope other = HaCredentialScope(
        userId: 'user-a',
        householdId: 'house-1',
        connectionId: 'conn-2',
      );
      await store.write(scope, token);
      await store.write(other, 'NOT_A_REAL_TOKEN_second');

      await store.forget(scope);

      expect(await store.read(scope), isNull);
      expect(await store.read(other), 'NOT_A_REAL_TOKEN_second');
    });

    test('a whole household takes only that household', () async {
      const HaCredentialScope elsewhere = HaCredentialScope(
        userId: 'user-a',
        householdId: 'house-2',
        connectionId: 'conn-1',
      );
      await store.write(scope, token);
      await store.write(elsewhere, 'NOT_A_REAL_TOKEN_second');

      await store.forgetEverything(
        HaCredentialScope.householdPrefix('user-a', 'house-1'),
      );

      expect(await store.read(scope), isNull);
      expect(await store.read(elsewhere), 'NOT_A_REAL_TOKEN_second');
    });

    test('a whole person takes every household of theirs', () async {
      const HaCredentialScope elsewhere = HaCredentialScope(
        userId: 'user-a',
        householdId: 'house-2',
        connectionId: 'conn-1',
      );
      const HaCredentialScope somebodyElse = HaCredentialScope(
        userId: 'user-b',
        householdId: 'house-1',
        connectionId: 'conn-1',
      );
      await store.write(scope, token);
      await store.write(elsewhere, 'NOT_A_REAL_TOKEN_second');
      await store.write(somebodyElse, 'NOT_A_REAL_TOKEN_third');

      await store.forgetEverything(HaCredentialScope.userPrefix('user-a'));

      expect(await store.read(scope), isNull);
      expect(await store.read(elsewhere), isNull);
      expect(await store.read(somebodyElse), 'NOT_A_REAL_TOKEN_third');
    });

    test('and never the Supabase session sitting beside it', () async {
      // The reason `forgetEverything` takes a prefix instead of calling
      // `deleteAll`: a household change must not sign the person out of
      // Hearth as a side effect.
      storage.values['hearth.supabase.session'] = 'NOT_A_REAL_SESSION';
      await store.write(scope, token);

      await store.forgetEverything(HaCredentialScope.userPrefix('user-a'));

      expect(storage.values['hearth.supabase.session'], 'NOT_A_REAL_SESSION');
    });
  });

  group('when the keychain will not cooperate', () {
    test('saving fails loudly rather than falling back', () async {
      // §4.1: losing secure-storage access must fail clearly. The failure a
      // person must never have is a token quietly written somewhere ordinary.
      storage.failing = true;
      await expectLater(
        store.write(scope, token),
        throwsA(isA<HaCredentialException>()),
      );
      expect(storage.values, isEmpty);
    });

    test('and the message carries nothing from the platform error', () async {
      // The platform exception can quote the value it was handling. Letting it
      // through is how a bearer token reaches a crash report.
      storage.failing = true;
      storage.failureMessage = 'Keychain error storing $token';

      await expectLater(
        store.write(scope, token),
        throwsA(
          isA<HaCredentialException>().having(
            (HaCredentialException e) => e.toString(),
            'toString',
            isNot(contains(token)),
          ),
        ),
      );
    });

    test('and reading fails the same way', () async {
      storage.failing = true;
      await expectLater(
        store.read(scope),
        throwsA(isA<HaCredentialException>()),
      );
    });
  });

  group('a scope is safe to say out loud', () {
    test('because it names a place rather than a secret', () {
      expect(scope.toString(), contains('user-a'));
      expect(scope.toString(), isNot(contains(token)));
    });
  });
}

/// An in-memory stand-in with a failure switch.
///
/// Deliberately not mocktail: the sweep behaviour depends on `readAll` and
/// `delete` agreeing with each other, and a fake that really holds the values
/// tests that agreement where a stubbed mock would only test the calls.
class _FakeVault implements HaSecretVault {
  final Map<String, String> values = <String, String>{};
  bool failing = false;
  String failureMessage = 'nope';

  void _check() {
    if (failing) throw StateError(failureMessage);
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    _check();
    return Map<String, String>.of(values);
  }
}
