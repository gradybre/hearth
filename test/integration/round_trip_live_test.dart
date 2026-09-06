@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/repositories/recipe_repository.dart';
import 'package:hearth/data/sync/library_sync.dart';
import 'package:hearth/data/sync/record_sync.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/data/sync/sync_scope.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fixtures.dart';

/// The offline round-trip and the two-device round-trip (spec §9.3).
///
/// These are the two claims Hearth makes that cannot be checked any other way:
/// that a meal logged with no signal is still there afterwards, and that what
/// one person cooks the other can see. Every layer below has its own tests and
/// they all pass; what these cover is the wiring between them, which is where
/// the failures have actually been.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
///
/// Gated on the environment variable as well as the tag so a plain
/// `flutter test` skips them: they need a running stack, and a suite that is
/// red because a container is down teaches everyone to ignore red.
void main() {
  const String url = 'http://127.0.0.1:54321';
  final String? key = _live ? _publishableKey() : null;
  final String? skip = key == null ? 'supabase not running' : null;

  late SupabaseClient client;
  late String userId;
  late String householdId;

  setUpAll(() async {
    // flutter_test answers every HTTP request with a 400 unless this is off.
    HttpOverrides.global = null;
    if (key == null) return;
    client = SupabaseClient(url, key);
    final AuthResponse auth = await client.auth.signInWithPassword(
      email: 'pull@hearth.test',
      password: 'HearthPull2026a',
    );
    userId = auth.user!.id;
    final Map<String, dynamic> profile = await client
        .from('profiles')
        .select('household_id')
        .eq('id', userId)
        .single();
    householdId = profile['household_id'] as String;
  });

  tearDownAll(() async {
    if (key == null) return;
    await client.auth.signOut();
  });

  /// One device: its own local database, stores, and sync.
  ({
    HearthDatabase db,
    PendingWriteStore queue,
    RecipeStore recipes,
    PlanStore plans,
    _SwitchableGateway gateway,
    SyncEngine engine,
    LibrarySync library,
    RecordSync records,
  })
  device() {
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    final PendingWriteStore queue = PendingWriteStore(db);
    final _SwitchableGateway gateway = _SwitchableGateway(
      SupabaseRemoteGateway(client),
    );
    final SyncEngine engine = SyncEngine(queue: queue, gateway: gateway);
    final RecipeStore recipes = RecipeStore(db);
    return (
      db: db,
      queue: queue,
      recipes: recipes,
      plans: PlanStore(db),
      gateway: gateway,
      engine: engine,
      library: LibrarySync(
        engine: engine,
        recipes: recipes,
        foods: FoodStore(db),
        queue: queue,
        preferences: PreferenceStore(db),
        scope: () => SyncScope(userId: userId, householdId: householdId),
      ),
      records: RecordSync(
        engine: engine,
        rows: RemoteRows(db),
        queue: queue,
        preferences: PreferenceStore(db),
        scope: () => SyncScope(userId: userId, householdId: householdId),
      ),
    );
  }

  test('a meal logged with no signal is still there after reconnecting', () async {
    // The one outcome sync must never produce: a meal you logged in a
    // basement quietly disappearing (spec §7.1).
    final phone = device();
    addTearDown(phone.db.close);

    // Start from a clean day. Rows left by an earlier run would collide on
    // the (user, day) unique key and the failure would look like a bug in
    // the code rather than in the fixture.
    await client.from('meal_plan_entries').delete().inFilter(
      'meal_plan_day_id',
      <String>[PlanRepository.dayIdFor(userId: userId, date: DateTime.now())],
    );
    await client.from('meal_plan_days').delete().eq('user_id', userId);

    final String recipeId = _uuid('a1');
    await phone.recipes.upsert(
      aRecipe(
        id: recipeId,
        householdId: householdId,
        title: 'Logged offline',
        sections: <RecipeSection>[aSection(id: _uuid('a2'))],
      ),
      updatedAt: DateTime.now().toUtc(),
    );

    final PlanRepository plans = PlanRepository(
      database: phone.db,
      store: phone.plans,
      queue: phone.queue,
      userId: userId,
    );

    phone.gateway.offline = true;

    final MealPlanEntry logged = await plans.add(
      date: DateTime.now(),
      slot: MealSlot.dinner,
      refType: PlanRefType.recipe,
      refId: recipeId,
      servings: 2,
      loggedMacros: const Macros(kcal: 400, proteinG: 30, carbG: 20, fatG: 15),
      label: 'Logged offline',
    );

    final SyncResult whileOffline = await phone.engine.push();
    expect(whileOffline.pushed, 0);
    expect(whileOffline.stoppedBecauseOffline, isTrue);
    expect(
      whileOffline.stillQueued,
      greaterThan(0),
      reason: 'the queue is what stands between a basement and a lost meal',
    );

    phone.gateway.offline = false;
    final SyncResult reconnected = await phone.engine.push();

    expect(
      reconnected.failed,
      0,
      reason:
          'reconnect could not send: '
          '${(await phone.queue.pending(now: DateTime.now().toUtc().add(const Duration(days: 1)))).map((PendingWrite w) => w.lastError)}',
    );
    expect(reconnected.pushed, greaterThan(0));
    expect(reconnected.isFullyDrained, isTrue);

    final Map<String, dynamic> row = await client
        .from('meal_plan_entries')
        .select('servings, is_logged, macro_snapshot')
        .eq('id', logged.id)
        .single();

    expect(row['is_logged'], isTrue);
    expect((row['servings'] as num).toDouble(), 2);
    // 400 kcal per serving, two servings: the snapshot is what was eaten, and
    // it crossed the wire unchanged (spec §4).
    expect((row['macro_snapshot'] as Map<String, dynamic>)['kcal'], 800);
  }, skip: skip);

  test('what one device saves, the other sees', () async {
    final phone = device();
    final desktop = device();
    addTearDown(phone.db.close);
    addTearDown(desktop.db.close);

    final String recipeId = _uuid('b1');
    await RecipeRepository(
      database: phone.db,
      store: phone.recipes,
      queue: phone.queue,
      householdId: householdId,
    ).save(
      aRecipe(
        id: recipeId,
        householdId: householdId,
        title: 'Cooked on the phone',
        sections: <RecipeSection>[
          aSection(
            id: _uuid('b2'),
            ingredients: <RecipeIngredient>[
              // A real uuid, not the fixture's 'ing-0': Postgres types these
              // columns as uuid and rejects anything else outright.
              anIngredient(
                'smoked paprika',
                id: _uuid('b3'),
                sectionId: _uuid('b2'),
              ),
            ],
          ),
        ],
      ),
    );

    final SyncResult pushed = await phone.engine.push();
    expect(
      pushed.failed,
      0,
      reason:
          'the phone could not send it: '
          '${(await phone.queue.pending(now: DateTime.now().toUtc().add(const Duration(days: 1)))).map((PendingWrite w) => w.lastError)}',
    );
    expect(pushed.pushed, greaterThan(0));

    final PullResult pulled = await desktop.library.pull();
    expect(pulled.applied, greaterThan(0));

    final Recipe? arrived = await desktop.recipes.byId(recipeId);
    expect(arrived, isNotNull);
    expect(arrived!.title, 'Cooked on the phone');
    expect(arrived.allIngredients.single.name, 'smoked paprika');
  }, skip: skip);

  test('an older server copy never overwrites a newer local edit', () async {
    // Whole-record last-write-wins (spec §7.1). Getting this backwards loses
    // the edit the user made most recently, which is the one they remember.
    final phone = device();
    final desktop = device();
    addTearDown(phone.db.close);
    addTearDown(desktop.db.close);

    final String recipeId = _uuid('c1');
    final String sectionId = _uuid('c2');

    await RecipeRepository(
      database: phone.db,
      store: phone.recipes,
      queue: phone.queue,
      householdId: householdId,
    ).save(
      aRecipe(
        id: recipeId,
        householdId: householdId,
        title: 'The server version',
        sections: <RecipeSection>[aSection(id: sectionId)],
      ),
    );
    await phone.engine.push();

    // The desktop edited the same recipe more recently, and has not sent it.
    await desktop.recipes.upsert(
      aRecipe(
        id: recipeId,
        householdId: householdId,
        title: 'Edited here, later',
        sections: <RecipeSection>[aSection(id: sectionId)],
      ),
      updatedAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    await desktop.library.pull();

    expect((await desktop.recipes.byId(recipeId))!.title, 'Edited here, later');
  }, skip: skip);

  test(
    'a meal logged on one device shows up on the other, snapshot and all',
    () async {
      // The two-person promise, and the §4 one in the same breath: what was
      // eaten travels, and travels unchanged.
      final phone = device();
      final desktop = device();
      addTearDown(phone.db.close);
      addTearDown(desktop.db.close);

      await client.from('meal_plan_days').delete().eq('user_id', userId);

      final MealPlanEntry logged =
          await PlanRepository(
            database: phone.db,
            store: phone.plans,
            queue: phone.queue,
            userId: userId,
          ).add(
            date: DateTime.now(),
            slot: MealSlot.lunch,
            refType: PlanRefType.recipe,
            refId: _uuid('d1'),
            servings: 0.5,
            loggedMacros: const Macros(
              kcal: 300,
              proteinG: 20,
              carbG: 10,
              fatG: 8,
            ),
            label: 'Half a portion',
          );

      await phone.engine.push();
      await desktop.records.pull();

      final List<MealPlanEntry> arrived = await desktop.plans.entriesForDay(
        userId: userId,
        date: DateTime.now(),
      );

      final MealPlanEntry match = arrived.firstWhere(
        (MealPlanEntry e) => e.id == logged.id,
      );
      expect(match.isLogged, isTrue);
      expect(match.servings, 0.5);
      // Half of 300, frozen at log time and untouched by the journey.
      expect(match.macroSnapshot!.macros.kcal, 150);
    },
    skip: skip,
  );
}

/// A real gateway that can be told there is no network.
///
/// Wrapping rather than faking: the offline path has to be exercised against
/// the same code that talks to Supabase, or it only proves the fake works.
class _SwitchableGateway implements RemoteGateway {
  _SwitchableGateway(this._inner);

  final RemoteGateway _inner;
  bool offline = false;

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) {
    if (offline) throw const RemoteUnavailable('no connection');
    return _inner.push(
      entityTable: entityTable,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
  }

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) {
    if (offline) throw const RemoteUnavailable('no connection');
    return _inner.fetchChanged(entityTable: entityTable, since: since);
  }

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) {
    if (offline) throw const RemoteUnavailable('no connection');
    return _inner.fetchChangedAggregates(
      entityTable: entityTable,
      since: since,
    );
  }
}

/// Stable, unique ids so a run can assert on its own rows and no other.
String _uuid(String tag) {
  final String stamp = DateTime.now().microsecondsSinceEpoch
      .toRadixString(16)
      .padLeft(12, '0');
  return '${stamp.substring(0, 8)}-${stamp.substring(8, 12)}-4000-8000-'
      '${tag.padRight(12, '0')}';
}

/// Live tests run only when asked for: they need `supabase start`.
bool get _live => Platform.environment['HEARTH_LIVE'] == '1';

String? _publishableKey() {
  final File file = File('config/local.json');
  if (!file.existsSync()) return null;
  final RegExp pattern = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"');
  return pattern.firstMatch(file.readAsStringSync())?.group(1);
}
