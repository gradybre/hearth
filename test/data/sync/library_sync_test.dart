import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/sync/library_sync.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

class FakeGateway implements RemoteGateway {
  bool offline = false;
  List<RemoteRecord> changed = <RemoteRecord>[];
  DateTime? askedSince;
  int calls = 0;

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
  }) async => const <RemoteRecord>[];

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async {
    calls++;
    askedSince = since;
    if (offline) throw const RemoteUnavailable('no connection');
    return entityTable == 'recipes' ? changed : const <RemoteRecord>[];
  }
}

/// A recipe as it arrives from the server.
RemoteRecord remoteRecipe({
  String id = 'recipe-1',
  String title = 'Their braise',
  required DateTime updatedAt,
}) => RemoteRecord(
  id: id,
  updatedAt: updatedAt,
  payload: <String, Object?>{
    'id': id,
    'household_id': 'household-1',
    'title': title,
    'servings': 4,
    'tags': <String>['sunday'],
    'is_deleted': false,
    'updated_at': updatedAt.toIso8601String(),
    'sections': <Map<String, Object?>>[
      {'id': 'sec-1', 'recipe_id': id, 'name': 'Main', 'sort_order': 0},
    ],
    'ingredients': <Map<String, Object?>>[
      {
        'id': 'ing-1',
        'recipe_id': id,
        'section_id': 'sec-1',
        'name': 'olive oil',
        'quantity_canonical': 29.5735,
        'quantity_kind': 'volume',
        'quantity_unit': 'tbsp',
        'is_optional': false,
        'sort_order': 0,
      },
    ],
    'steps': <Map<String, Object?>>[
      {
        'id': 'step-1',
        'recipe_id': id,
        'section_id': 'sec-1',
        'step_number': 1,
        'body': 'Sear the beef',
      },
    ],
  },
);

void main() {
  late HearthDatabase db;
  late FakeGateway gateway;
  late RecipeStore recipes;
  late PendingWriteStore queue;
  late PreferenceStore preferences;
  late LibrarySync sync;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    gateway = FakeGateway();
    recipes = RecipeStore(db);
    queue = PendingWriteStore(db);
    preferences = PreferenceStore(db);
    sync = LibrarySync(
      engine: SyncEngine(queue: queue, gateway: gateway),
      recipes: recipes,
      foods: FoodStore(db),
      queue: queue,
      preferences: preferences,
    );
  });

  tearDown(() => db.close());

  group('a partner\'s recipe arrives', () {
    test('and is readable locally, whole', () async {
      // This is what a household is for: what one member adds, the other has.
      gateway.changed = <RemoteRecord>[remoteRecipe(updatedAt: t0)];

      final PullResult result = await sync.pull();

      expect(result.applied, 1);
      final Recipe? stored = await recipes.byId('recipe-1');
      expect(stored, isNotNull);
      expect(stored!.title, 'Their braise');
      expect(stored.allIngredients.single.name, 'olive oil');
      expect(stored.allSteps.single.text, 'Sear the beef');
    });

    test('its quantity survives the round trip', () async {
      gateway.changed = <RemoteRecord>[remoteRecipe(updatedAt: t0)];
      await sync.pull();

      final Recipe stored = (await recipes.byId('recipe-1'))!;
      expect(
        stored.allIngredients.single.quantity!.canonicalAmount,
        closeTo(29.5735, 0.001),
      );
    });
  });

  group('what a pull refuses to overwrite', () {
    test('a local copy that is newer', () async {
      await recipes.upsert(
        aRecipe(id: 'recipe-1', title: 'Mine, edited just now'),
        updatedAt: t0.add(const Duration(hours: 1)),
      );
      gateway.changed = <RemoteRecord>[remoteRecipe(updatedAt: t0)];

      final PullResult result = await sync.pull();

      expect(result.applied, 0);
      expect(result.skipped, 1);
      expect((await recipes.byId('recipe-1'))!.title, 'Mine, edited just now');
    });

    test('a local change that has not been sent yet', () async {
      // The server's copy predates the local change by definition, so taking
      // it would discard something done offline before it was ever sent.
      await recipes.upsert(
        aRecipe(id: 'recipe-1', title: 'Written on the train'),
        updatedAt: t0.subtract(const Duration(hours: 1)),
      );
      await queue.enqueue(
        entityTable: 'recipes',
        entityId: 'recipe-1',
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'id': 'recipe-1'},
        queuedAt: t0,
      );
      gateway.changed = <RemoteRecord>[remoteRecipe(updatedAt: t0)];

      final PullResult result = await sync.pull();

      expect(result.applied, 0);
      expect((await recipes.byId('recipe-1'))!.title, 'Written on the train');
    });
  });

  group('the watermark', () {
    test('is not set on the first pull, so everything comes down', () async {
      await sync.pull();
      expect(gateway.askedSince, isNull);
    });

    test('is used on the next pull, and overlaps the last one', () async {
      // Two devices' clocks disagree. Overlapping costs a few redundant
      // records, which last-write-wins discards anyway; not overlapping can
      // skip a record written between two pulls, forever.
      await sync.pull();
      final DateTime before = DateTime.now().toUtc();
      await sync.pull();

      expect(gateway.askedSince, isNotNull);
      expect(
        gateway.askedSince!.isBefore(before),
        isTrue,
        reason: 'the window should reach back past the previous run',
      );
    });

    test('does not move when the server could not be reached', () async {
      // Advancing it after an offline attempt would skip everything that
      // changed while this device was away.
      gateway.offline = true;
      await sync.pull();

      gateway.offline = false;
      await sync.pull();

      expect(gateway.askedSince, isNull);
    });

    test('offline is reported, not treated as an empty server', () async {
      gateway.offline = true;
      final PullResult result = await sync.pull();

      expect(result.stoppedBecauseOffline, isTrue);
      expect(result.applied, 0);
    });
  });
}
