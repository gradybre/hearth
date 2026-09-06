import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/sync/library_sync.dart';
import 'package:hearth/data/sync/record_sync.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/data/sync/sync_checkpoints.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/data/sync/sync_scope.dart';

/// Checkpoints belong to somebody (spec §7.1, R05).
///
/// The first version of these keys was `sync.watermark.<table>` — no user, no
/// household. One device, two accounts, and the second inherits the first's
/// checkpoint; because a checkpoint only moves forward, everything the second
/// account wrote before that moment is never asked for again.
void main() {
  const SyncScope alice = SyncScope(
    userId: 'user-alice',
    householdId: 'house-1',
  );
  const SyncScope bob = SyncScope(userId: 'user-bob', householdId: 'house-2');

  late HearthDatabase db;
  late _FakeGateway gateway;
  late PreferenceStore preferences;
  late PendingWriteStore queue;
  SyncScope current = alice;

  LibrarySync syncFor() => LibrarySync(
    engine: SyncEngine(queue: queue, gateway: gateway),
    recipes: RecipeStore(db),
    foods: FoodStore(db),
    queue: queue,
    preferences: preferences,
    scope: () => current,
  );

  RecordSync recordSyncFor() => RecordSync(
    engine: SyncEngine(queue: queue, gateway: gateway),
    rows: RemoteRows(db),
    queue: queue,
    preferences: preferences,
    scope: () => current,
  );

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    gateway = _FakeGateway();
    preferences = PreferenceStore(db);
    queue = PendingWriteStore(db);
    current = alice;
  });

  tearDown(() => db.close());

  group('the key carries who it is for', () {
    test('user and household both, so either changing invalidates it', () {
      expect(
        alice.watermarkKeyFor('recipes'),
        isNot(bob.watermarkKeyFor('recipes')),
      );
      expect(
        alice.watermarkKeyFor('recipes'),
        isNot(
          const SyncScope(
            userId: 'user-alice',
            householdId: 'house-2',
          ).watermarkKeyFor('recipes'),
        ),
      );
      // Accepting an invitation to another household changes which library
      // the server will hand over; a checkpoint from the old one would skip
      // the new one's history exactly as a stranger's would.
    });

    test('and is versioned, so a v1 key can never be mistaken for one', () {
      expect(
        alice.watermarkKeyFor('recipes'),
        isNot(SyncScope.legacyKeyFor('recipes')),
      );
    });
  });

  group('a second account on the same device', () {
    test('does not inherit the first account\'s checkpoint', () async {
      await syncFor().pull();
      expect(
        gateway.sinceFor('recipes'),
        isNull,
        reason: 'the first pull is whole',
      );

      // Alice's second pull uses her checkpoint, as it should.
      await syncFor().pull();
      expect(gateway.sinceFor('recipes'), isNotNull);

      // Bob signs in on the same phone. His library is years old; every row
      // in it predates Alice's checkpoint, so a pull that reached back only
      // to her last sync would return nothing and he would see an empty
      // cookbook for ever.
      current = bob;
      await syncFor().pull();

      expect(gateway.sinceFor('recipes'), isNull);
      expect(gateway.sinceFor('foods'), isNull);
    });

    test(
      'and does not overwrite it either, so she is not reset in turn',
      () async {
        // Asserted on the stored value itself rather than on the date. Every
        // write in this test lands within a millisecond or two of the last,
        // so "is it recent" is true whether the key is shared or not — the
        // question is whether it is still *her* value.
        await syncFor().pull();
        final String? hers = await preferences.read(
          alice.watermarkKeyFor('recipes'),
        );
        expect(hers, isNotNull);

        // Bob signs in on the same phone and pulls the whole library.
        current = bob;
        await syncFor().pull();

        expect(
          await preferences.read(alice.watermarkKeyFor('recipes')),
          hers,
          reason:
              'a shared key would have been overwritten by his pass, and '
              'she would re-read the library every time he used the phone',
        );
        expect(
          await preferences.read(bob.watermarkKeyFor('recipes')),
          isNotNull,
        );
      },
    );
  });

  group('a checkpoint from before this was scoped', () {
    test(
      'is not used, because it may have been advanced past truncation',
      () async {
        // R04: an unpaged pull took the first thousand rows and moved the
        // watermark past the rest. Any v1 key may be sitting past rows this
        // device has never seen, so it is not trustworthy even for the account
        // that wrote it.
        await preferences.write(
          SyncScope.legacyKeyFor('recipes'),
          DateTime.utc(2026, 1, 1).toIso8601String(),
        );

        await syncFor().pull();

        expect(gateway.sinceFor('recipes'), isNull);
      },
    );

    test('and is deleted rather than left to be found again', () async {
      await preferences.write(
        SyncScope.legacyKeyFor('recipes'),
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );
      await preferences.write(
        SyncScope.legacyKeyFor('foods'),
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );

      await syncFor().pull();

      expect(await preferences.read(SyncScope.legacyKeyFor('recipes')), isNull);
      expect(await preferences.read(SyncScope.legacyKeyFor('foods')), isNull);
    });
  });

  group('the account changing while a pull is in flight', () {
    test('does not move the checkpoint', () async {
      // The pass began under Alice's session and asked the server for her
      // rows. If the session becomes Bob's halfway through, the rest of the
      // answers are his — and writing them under her checkpoint would
      // advance it over data she has never been sent.
      gateway.onFetch = () => current = bob;

      await syncFor().pull();
      current = alice;
      gateway.onFetch = null;
      await syncFor().pull();

      expect(
        gateway.sinceFor('recipes'),
        isNull,
        reason: 'the abandoned pass must not have left a checkpoint behind',
      );
    });

    test('and says so, rather than reporting a clean run', () async {
      gateway.onFetch = () => current = bob;

      final PullResult result = await syncFor().pull();

      expect(result.abandonedScope, isTrue);
    });
  });

  group('signing out deliberately', () {
    // Not what keeps two accounts apart — the scoped key already does that.
    // This is the repair lever: a checkpoint only moves forward, so a row
    // whose server timestamp ends up behind it can never be asked for again,
    // and "sign out and back in" has to actually mean something.
    test(
      'forgets every checkpoint, this account\'s and any other\'s',
      () async {
        await syncFor().pull();
        await syncFor().pull();
        expect(gateway.sinceFor('recipes'), isNotNull);

        await SyncCheckpoints(
          preferences: preferences,
          scope: () => current,
        ).forgetEverything();

        await syncFor().pull();
        expect(gateway.sinceFor('recipes'), isNull);
        expect(gateway.sinceFor('foods'), isNull);
      },
    );

    test('including a v1 key nobody has pulled past yet', () async {
      await preferences.write(
        SyncScope.legacyKeyFor('meal_plan_entries'),
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );

      await SyncCheckpoints(
        preferences: preferences,
        scope: () => current,
      ).forgetEverything();

      expect(
        await preferences.read(SyncScope.legacyKeyFor('meal_plan_entries')),
        isNull,
      );
    });

    test('and touches nothing else on the device', () async {
      // The sweep is by prefix, and the prefix sits next to every other
      // device-local setting in the same table. Signing out must not put the
      // app back into light mode on somebody's dark phone.
      await preferences.write(PreferenceStore.themeChoice, 'dark');
      await preferences.write(PreferenceStore.launchTarget, 'plan');
      await syncFor().pull();

      await SyncCheckpoints(
        preferences: preferences,
        scope: () => current,
      ).forgetEverything();

      expect(await preferences.read(PreferenceStore.themeChoice), 'dark');
      expect(await preferences.read(PreferenceStore.launchTarget), 'plan');
    });
  });

  group('clearing while a pull is in flight', () {
    test('is not undone by the pass finishing afterwards', () async {
      // The repair lever's whole job. Someone taps Sync now, then Sign out;
      // the pass is still working through its tables when the checkpoints are
      // swept, and if it writes its checkpoint back the sweep silently did
      // nothing at all.
      await syncFor().pull();
      await syncFor().pull();
      expect(gateway.sinceFor('recipes'), isNotNull);

      final SyncCheckpoints checkpoints = SyncCheckpoints(
        preferences: preferences,
        scope: () => current,
      );
      gateway.onFetch = () => checkpoints.forgetEverything();

      final PullResult result = await syncFor().pull();
      expect(result.abandonedScope, isTrue);

      gateway.onFetch = null;
      await syncFor().pull();
      expect(
        gateway.sinceFor('recipes'),
        isNull,
        reason: 'the swept checkpoint must not have been written back',
      );
    });
  });

  group('the records path, which keeps its own copy of all this', () {
    // A plan and a day's logs are one person's, so this path is where an
    // inherited checkpoint costs somebody their own history rather than the
    // household's. It has its own `_pullTable`, so it needs its own tests:
    // covering one of two twins is how the paging guard shipped half-blind.
    test('a second account does not inherit the first\'s checkpoint', () async {
      await recordSyncFor().pull();
      await recordSyncFor().pull();
      expect(gateway.sinceFor('meal_plan_entries'), isNotNull);

      current = bob;
      await recordSyncFor().pull();

      expect(gateway.sinceFor('meal_plan_entries'), isNull);
      expect(gateway.sinceFor('macro_targets'), isNull);
    });

    test('a v1 checkpoint is discarded rather than inherited', () async {
      await preferences.write(
        SyncScope.legacyKeyFor('meal_plan_entries'),
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );

      await recordSyncFor().pull();

      expect(gateway.sinceFor('meal_plan_entries'), isNull);
      expect(
        await preferences.read(SyncScope.legacyKeyFor('meal_plan_entries')),
        isNull,
      );
    });

    test('the memberships stage does not run for the wrong account', () async {
      // It is the one stage that *deletes* local rows: favourites and
      // cookbook contents the server did not send are removed. Run under a
      // session that changed underneath it, it would not write the wrong
      // favourites so much as delete the right ones — and it holds the two
      // widest network waits in the pass.
      // Flipped *inside* the memberships fetch, not before it. An earlier
      // flip is caught by the per-table check and never reaches this stage at
      // all — which is how the first version of this test passed with the
      // membership check deleted.
      gateway.onFetch = () {
        if (gateway.wasAsked('recipe_favorites')) current = bob;
      };

      final PullResult result = await recordSyncFor().pull();

      expect(
        result.abandonedScope,
        isTrue,
        reason:
            'the answers arrived under a session that was no longer the '
            'one that asked, so nothing may be replaced from them',
      );
    });

    test('an account change mid-pass leaves no checkpoint behind', () async {
      gateway.onFetch = () => current = bob;

      final PullResult result = await recordSyncFor().pull();

      expect(result.abandonedScope, isTrue);

      current = alice;
      gateway.onFetch = null;
      await recordSyncFor().pull();
      expect(gateway.sinceFor('meal_plan_days'), isNull);
    });
  });
}

class _FakeGateway implements RemoteGateway {
  /// Per table, because both are pulled in one pass: asserting on the last
  /// call answers for foods and says nothing about recipes.
  final Map<String, DateTime?> asked = <String, DateTime?>{};
  void Function()? onFetch;

  DateTime? sinceFor(String table) => asked[table];

  /// Distinct from `sinceFor(table) == null`, which is also what a pull that
  /// asked for everything looks like. A test about a stage that was never
  /// reached needs to tell those two apart.
  bool wasAsked(String table) => asked.containsKey(table);

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) async {}

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async {
    asked[entityTable] = since;
    onFetch?.call();
    return const <RemoteRecord>[];
  }

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async {
    asked[entityTable] = since;
    onFetch?.call();
    return const <RemoteRecord>[];
  }
}
