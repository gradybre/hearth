import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/auth/account_cache.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';

/// Getting in on a cold start with no signal (spec §5.1).
///
/// The session lives in the Keychain and survives a restart perfectly well.
/// The only thing that needed the network was the household id, which lives in
/// a `profiles` row — so a signed-in user launching on a train landed on the
/// sign-in screen with a good session sitting right there.
void main() {
  late HearthDatabase db;
  late AccountCache cache;

  const HearthAccount brendan = HearthAccount(
    userId: 'user-1',
    email: 'b@example.com',
    householdId: 'household-1',
    shareCode: 'QH6RDP7J',
    displayName: 'Brendan',
  );

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    cache = AccountCache(PreferenceStore(db));
  });

  tearDown(() => db.close());

  test('nothing cached is nothing returned', () async {
    expect(await cache.forUser('user-1'), isNull);
  });

  test('a remembered account comes back whole', () async {
    await cache.remember(brendan);

    final HearthAccount? recalled = await cache.forUser('user-1');
    expect(recalled!.householdId, 'household-1');
    expect(recalled.email, 'b@example.com');
    expect(recalled.shareCode, 'QH6RDP7J');
    expect(recalled.displayName, 'Brendan');
  });

  test('it is never handed to a different user', () async {
    // The guard that matters. Signing in as someone else must not inherit the
    // previous person's household — that would put their recipes, their plan
    // and their partner's share code in front of a stranger.
    await cache.remember(brendan);

    expect(await cache.forUser('someone-else'), isNull);
  });

  test('signing out forgets it', () async {
    await cache.remember(brendan);
    await cache.forget();

    expect(await cache.forUser('user-1'), isNull);
  });

  test('a cache with no household is not usable', () async {
    // Half a cached account is worse than none: the household id is the one
    // thing every household-scoped query needs.
    await cache.remember(
      const HearthAccount(
        userId: 'user-1',
        email: 'b@example.com',
        householdId: '',
      ),
    );

    expect(await cache.forUser('user-1'), isNull);
  });

  test('nonsense in the store is ignored rather than thrown', () async {
    await PreferenceStore(db).write('auth.last_account', 'not json');

    expect(await cache.forUser('user-1'), isNull);
  });
}
