import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/house/ha_selection.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/domain/house/entity_id.dart';

/// Which devices this phone shows (`docs/HOME_ASSISTANT_SPEC.md` §4.2, §5.3).
void main() {
  late HearthDatabase db;
  late HouseSelectionStore store;

  final EntityId door = EntityId.tryParse('binary_sensor.front_door')!;
  final EntityId lamp = EntityId.tryParse('light.kitchen')!;
  final EntityId plug = EntityId.tryParse('switch.kettle')!;

  final String key = HouseSelectionStore.keyFor(
    userId: 'user-a',
    householdId: 'house-1',
    connectionId: 'conn-1',
  );

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = HouseSelectionStore(PreferenceStore(db));
  });

  tearDown(() => db.close());

  group('a dashboard is chosen, not discovered', () {
    test('nothing is selected to begin with', () async {
      // §4.1: "Nothing is selected automatically merely because it appeared."
      expect((await store.read(key)).isEmpty, isTrue);
    });

    test('and what goes in comes back in order', () async {
      // Order is a local choice (§4.2), so a set would lose it every read.
      await store.write(
        key,
        const HouseSelection().with_(lamp).with_(door).with_(plug),
      );
      expect((await store.read(key)).chosen, <EntityId>[lamp, door, plug]);
    });

    test('and adding the same thing twice does not add it twice', () async {
      // A double tap on a review screen must not put a device on the list
      // twice — two cards for one plug can disagree with each other.
      final HouseSelection twice = const HouseSelection()
          .with_(lamp)
          .with_(lamp);
      expect(twice.chosen, <EntityId>[lamp]);
    });
  });

  group('favourites are a promotion, not a separate list', () {
    test('only something chosen can be one', () async {
      final HouseSelection selection = const HouseSelection().favouring(
        lamp,
        yes: true,
      );
      expect(selection.favourites, isEmpty);
    });

    test('and removing a device revokes its promotion', () async {
      // Otherwise the favourite comes back the moment the device is re-added,
      // which is a preference somebody expressed once and then revoked.
      final HouseSelection selection = const HouseSelection()
          .with_(lamp)
          .favouring(lamp, yes: true)
          .without(lamp);

      expect(selection.chosen, isEmpty);
      expect(selection.favourites, isEmpty);
    });

    test(
      'and a stored favourite that is no longer chosen is dropped',
      () async {
        // The record on disk was written by an older version of this code and
        // will one day have been written by a newer one. Resolve rather than
        // trust.
        const HouseSelection incoherent = HouseSelection(
          chosen: <EntityId>[],
          favourites: <EntityId>{},
        );
        expect(incoherent.settled.favourites, isEmpty);

        await store.write(
          key,
          HouseSelection(
            chosen: <EntityId>[lamp],
            favourites: <EntityId>{door},
          ),
        );
        expect((await store.read(key)).favourites, isEmpty);
      },
    );
  });

  group('a device that stopped existing stays visibly missing', () {
    test('rather than being quietly dropped', () async {
      // §4.2: a removed selection stays until a person deals with it. Dropping
      // it silently hides that a door sensor stopped existing, which is the
      // one thing somebody would want to know.
      final HouseSelection selection = const HouseSelection()
          .with_(door)
          .with_(lamp);

      expect(selection.missingFrom(<EntityId>{lamp}), <EntityId>[door]);
      expect(
        selection.chosen,
        contains(door),
        reason: 'reported, not repaired',
      );
    });

    test('and is never swapped for something with a similar name', () async {
      // §9: "Never retarget by label." A new `binary_sensor.front_door_2` is
      // not the old sensor, whatever it is called.
      final EntityId lookalike = EntityId.tryParse(
        'binary_sensor.front_door_2',
      )!;
      final HouseSelection selection = const HouseSelection().with_(door);

      expect(selection.missingFrom(<EntityId>{lookalike}), <EntityId>[door]);
    });
  });

  group('what is written down', () {
    test('is references, never readings', () async {
      // §5.3: do not store raw HA responses — they can carry access tokens and
      // signed media URLs. A stored name would also go stale the moment
      // somebody renamed the thing in Home Assistant.
      await store.write(key, const HouseSelection().with_(lamp));
      final String raw = (await PreferenceStore(db).read(key))!;

      expect(raw, contains('light.kitchen'));
      expect(raw, isNot(contains('attributes')));
      expect(raw, isNot(contains('state')));
    });

    test('and a record from a version this code cannot read is ignored', () async {
      // Losing a dashboard is a minute's work to redo. Interpreting an unknown
      // shape silently rearranges one, which is not.
      await PreferenceStore(db)
          .write(key, '{"v":99,"chosen":["light.kitchen"]}');
      expect((await store.read(key)).isEmpty, isTrue);
    });

    test('and so is a corrupt one', () async {
      await PreferenceStore(db).write(key, 'not json at all');
      expect((await store.read(key)).isEmpty, isTrue);
    });

    test('and an unparseable id in a good record costs that id only', () async {
      await PreferenceStore(db).write(
        key,
        '{"v":1,"chosen":["light.kitchen","switch.","",7],"favourites":[]}',
      );
      expect((await store.read(key)).chosen, <EntityId>[lamp]);
    });
  });

  group('every context keeps its own dashboard', () {
    test('so signing in as somebody else does not inherit one', () async {
      await store.write(key, const HouseSelection().with_(lamp));

      final String elsewhere = HouseSelectionStore.keyFor(
        userId: 'user-b',
        householdId: 'house-1',
        connectionId: 'conn-1',
      );
      expect((await store.read(elsewhere)).isEmpty, isTrue);
    });

    test('and forgetting a user takes every household of theirs', () async {
      final String otherHousehold = HouseSelectionStore.keyFor(
        userId: 'user-a',
        householdId: 'house-2',
        connectionId: 'conn-1',
      );
      final String somebodyElse = HouseSelectionStore.keyFor(
        userId: 'user-b',
        householdId: 'house-1',
        connectionId: 'conn-1',
      );
      await store.write(key, const HouseSelection().with_(lamp));
      await store.write(otherHousehold, const HouseSelection().with_(door));
      await store.write(somebodyElse, const HouseSelection().with_(plug));

      await store.forgetEverything(HouseSelectionStore.userPrefix('user-a'));

      expect((await store.read(key)).isEmpty, isTrue);
      expect((await store.read(otherHousehold)).isEmpty, isTrue);
      expect((await store.read(somebodyElse)).chosen, <EntityId>[
        plug,
      ], reason: 'another person on the same phone keeps theirs');
    });

    test('and never other settings sitting beside it', () async {
      // The reason `forgetEverything` takes a prefix: the preference table
      // holds the whole app's settings, and a household change must not wipe
      // somebody's theme or launch preference.
      await PreferenceStore(db).write('theme.choice', 'dark');
      await store.write(key, const HouseSelection().with_(lamp));

      await store.forgetEverything(HouseSelectionStore.userPrefix('user-a'));

      expect(await PreferenceStore(db).read('theme.choice'), 'dark');
    });
  });
}
