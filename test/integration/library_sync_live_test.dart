@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:hearth/data/sync/library_sync.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/data/sync/sync_scope.dart';
import 'package:hearth/domain/models/recipe.dart';
// Via supabase_flutter, which re-exports the client: depending on `supabase`
// directly would pin a second copy of a transitive package.
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sync against the real local Supabase stack (spec §9.3).
///
/// Not part of the default suite — it needs `supabase start` — but it is the
/// only place the client and the database are exercised against each other.
/// Everything else mocks one side or the other, and the bugs that matter here
/// live exactly in the join between them.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
///
/// Gated on the environment variable as well as the tag so a plain
/// `flutter test` skips them: they need a running stack, and a suite that is
/// red because a container is down teaches everyone to ignore red.
void main() {
  const String url = 'http://127.0.0.1:54321';
  final String? key = _live ? _publishableKey() : null;

  late SupabaseClient client;
  late HearthDatabase db;
  late LibrarySync sync;
  late RecipeStore recipes;

  setUpAll(() async {
    // flutter_test installs an HttpClient that answers every request with a
    // 400, so tests cannot reach the network by accident. This file wants the
    // network on purpose, so it takes the override off.
    HttpOverrides.global = null;
    if (key == null) return;
    client = SupabaseClient(url, key);
  });

  setUp(() async {
    if (key == null) return;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeStore(db);
    final PendingWriteStore queue = PendingWriteStore(db);
    final SyncEngine engine = SyncEngine(
      queue: queue,
      gateway: SupabaseRemoteGateway(client),
    );
    sync = LibrarySync(
      engine: engine,
      recipes: recipes,
      foods: FoodStore(db),
      queue: queue,
      preferences: PreferenceStore(db),
      scope: () => SyncScope(
        userId: client.auth.currentUser?.id ?? 'unknown',
        householdId: 'live',
      ),
    );
  });

  tearDown(() async {
    if (key == null) return;
    await db.close();
  });

  test('a signed-out pull brings nothing down', () async {
    // RLS answers with an empty result rather than an error, which is exactly
    // why the controller refuses to sync without an account: this is
    // indistinguishable from "nothing has changed".
    final PullResult result = await sync.pull();
    expect(result.applied, 0);
  }, skip: key == null ? 'supabase not running' : null);

  test('a signed-in pull brings the household library down', () async {
    await client.auth.signInWithPassword(
      email: 'pull@hearth.test',
      password: 'HearthPull2026a',
    );

    final PullResult result = await sync.pull();

    expect(
      result.applied,
      greaterThan(0),
      reason: 'the seeded recipe should have arrived',
    );

    final Recipe? paella = await recipes.byId(
      '11111111-1111-4111-8111-111111111111',
    );
    expect(paella, isNotNull);
    expect(paella!.title, "Partner's paella");
    expect(paella.allIngredients, hasLength(2));
    expect(paella.allSteps.single.timerSeconds, 120);

    await client.auth.signOut();
  }, skip: key == null ? 'supabase not running' : null);
}

/// Reads the local publishable key, which is gitignored and never in the repo.
/// Live tests run only when asked for: they need `supabase start`.
bool get _live => Platform.environment['HEARTH_LIVE'] == '1';

String? _publishableKey() {
  final File file = File('config/local.json');
  if (!file.existsSync()) return null;
  final RegExp pattern = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"');
  return pattern.firstMatch(file.readAsStringSync())?.group(1);
}
