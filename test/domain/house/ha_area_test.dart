import 'package:hearth/domain/house/entity_id.dart';
import 'package:hearth/domain/house/ha_area.dart';
import 'package:test/test.dart';

/// Rooms come from Home Assistant's registries, and from nothing else
/// (`docs/HOME_ASSISTANT_SPEC.md` §4.2, §3, §9).
///
/// The bug every test here is aimed at is a dashboard that attaches a control
/// to the wrong physical thing. It looks like a feature until a porch light
/// turns on the garage, so the adversarial cases come first.
void main() {
  group('two things called the same are still two things', () {
    test('a shared name never joins two devices', () {
      // §3: do not infer identity from similar names. Every house has a
      // "Front Door" light and a "Front Door" sensor named by different
      // people on different days.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight),
          DiscoveredEntity(_garageLight),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[_area('outside', 'Outside')],
          devices: <HaDeviceEntry>[
            _device('porch', 'Porch fitting', 'outside'),
            _device('garage', 'Garage fitting', 'outside'),
          ],
          entities: <HaEntityEntry>[
            _entity(_porchLight, name: 'Front Door', deviceId: 'porch'),
            _entity(_garageLight, name: 'Front Door', deviceId: 'garage'),
          ],
        ),
      );

      final HouseGroup outside = grouping.groups.single;
      expect(
        outside.devices,
        hasLength(2),
        reason: 'one name, two devices — clustering them would be the bug',
      );
      expect(outside.devices.map((HouseDeviceGroup d) => d.deviceId), <String>[
        'garage',
        'porch',
      ]);
      expect(
        outside.entities.every((HouseEntityView e) => e.nameIsAmbiguous),
        isTrue,
        reason: 'the label alone cannot identify either row',
      );
    });

    test('and a name shared across rooms is not ambiguous', () {
      // The room already tells them apart, so the card does not need to
      // shout. Ambiguity is scoped to what a reader sees under one heading.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight),
          DiscoveredEntity(_garageLight),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[
            _area('outside', 'Outside'),
            _area('garage_area', 'Garage'),
          ],
          devices: <HaDeviceEntry>[
            _device('porch', 'Porch fitting', 'outside'),
            _device('garage', 'Garage fitting', 'garage_area'),
          ],
          entities: <HaEntityEntry>[
            _entity(_porchLight, name: 'Ceiling', deviceId: 'porch'),
            _entity(_garageLight, name: 'Ceiling', deviceId: 'garage'),
          ],
        ),
      );

      expect(grouping.groups, hasLength(2));
      expect(
        grouping.allEntities.any((HouseEntityView e) => e.nameIsAmbiguous),
        isFalse,
      );
    });
  });

  group('an entity area overrides its device area', () {
    test('even when that splits the device across two rooms', () {
      // The in-wall switch filed under the living room whose second entity
      // somebody deliberately moved to the hall. Putting them back together
      // would silently undo that.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_plugSwitch),
          DiscoveredEntity(_plugPower),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[
            _area('living', 'Living room'),
            _area('hall', 'Hall'),
          ],
          devices: <HaDeviceEntry>[_device('plug', 'Wall plug', 'living')],
          entities: <HaEntityEntry>[
            _entity(_plugSwitch, name: 'Lamp', deviceId: 'plug'),
            _entity(
              _plugPower,
              name: 'Lamp power',
              deviceId: 'plug',
              areaId: 'hall',
            ),
          ],
        ),
      );

      expect(grouping.groups.map((HouseGroup g) => g.name), <String>[
        'Hall',
        'Living room',
      ]);
      expect(grouping.groups.first.entities.single.id, _plugPower);
      expect(grouping.groups.last.entities.single.id, _plugSwitch);
      expect(
        grouping.groups.first.devices.single.deviceId,
        'plug',
        reason: 'the split rows still say which device they came from',
      );
    });

    test('and an unnamed area is not quietly swapped for the device room', () {
      // A hole in the area registry means Hearth cannot name the room. It
      // does not mean the assignment was never made — falling back to the
      // device's area would file the entity under the room it was moved out
      // of, confidently and wrongly.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[DiscoveredEntity(_plugPower)],
        registry: HaRegistry.from(
          areas: <HaArea>[_area('living', 'Living room')],
          devices: <HaDeviceEntry>[_device('plug', 'Wall plug', 'living')],
          entities: <HaEntityEntry>[
            _entity(_plugPower, deviceId: 'plug', areaId: 'gone'),
          ],
        ),
      );

      final HouseGroup room = grouping.groups.single;
      expect(room.kind, HouseGroupKind.room);
      expect(room.areaId, 'gone');
      expect(
        room.name,
        isNull,
        reason: 'this layer will not print an id where a room name goes',
      );
    });

    test('and entities under one device in one room stay together', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_plugSwitch),
          DiscoveredEntity(_plugPower),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[_area('living', 'Living room')],
          devices: <HaDeviceEntry>[_device('plug', 'Wall plug', 'living')],
          entities: <HaEntityEntry>[
            _entity(_plugSwitch, name: 'Lamp', deviceId: 'plug'),
            _entity(_plugPower, name: 'Lamp power', deviceId: 'plug'),
          ],
        ),
      );

      final HouseDeviceGroup cluster = grouping.groups.single.devices.single;
      expect(cluster.deviceName, 'Wall plug');
      expect(cluster.entities.map((HouseEntityView e) => e.id), <EntityId>[
        _plugSwitch,
        _plugPower,
      ]);
    });
  });

  group('no registry at all is ordinary operation', () {
    test('everything falls into one clear unassigned group', () {
      // §6: metadata may need administrator rights and Hearth must not
      // demand them, so this path is normal — not an error, and not an empty
      // dashboard.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: 'Porch'),
          DiscoveredEntity(_garageLight, friendlyName: 'Garage'),
        ],
      );

      final HouseGroup group = grouping.groups.single;
      expect(group.kind, HouseGroupKind.unassigned);
      expect(group.entities.map((HouseEntityView e) => e.displayName), <String>[
        'Garage',
        'Porch',
      ]);
    });

    test('and the missing registry is stated, not inferred from emptiness', () {
      // A server with no areas configured is not the same situation as a
      // token that may not read the registry, and the UI explains them
      // differently.
      expect(const HaRegistry.unavailable().isAvailable, isFalse);
      expect(HaRegistry.from().isAvailable, isTrue);
    });

    test('and identical names still do not cluster', () {
      // The degraded path is where name-matching is most tempting, because
      // names are all there is. It is also where it is most dangerous.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: 'Front Door'),
          DiscoveredEntity(_garageLight, friendlyName: 'Front Door'),
        ],
      );

      final HouseGroup group = grouping.groups.single;
      expect(group.devices, hasLength(2));
      expect(
        group.devices.every((HouseDeviceGroup d) => d.deviceId == null),
        isTrue,
        reason: 'with no registry there is no relationship to claim',
      );
      expect(
        group.entities.every((HouseEntityView e) => e.nameIsAmbiguous),
        isTrue,
      );
    });

    test('and a nameless entity falls back to its object id', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: '   '),
        ],
      );
      expect(grouping.allEntities.single.displayName, 'porch');
    });
  });

  group('a registry with holes in it costs a room, never an entity', () {
    test('an entity the registry never mentions is still drawn', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: 'Porch'),
          DiscoveredEntity(_garageLight, friendlyName: 'Garage'),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[_area('outside', 'Outside')],
          devices: <HaDeviceEntry>[
            _device('porch', 'Porch fitting', 'outside'),
          ],
          entities: <HaEntityEntry>[
            _entity(_porchLight, name: 'Porch', deviceId: 'porch'),
          ],
        ),
      );

      expect(grouping.entityCount, 2);
      expect(grouping.groups.first.kind, HouseGroupKind.room);
      expect(grouping.groups.last.kind, HouseGroupKind.unassigned);
      expect(grouping.groups.last.entities.single.id, _garageLight);
    });

    test('a device id with no device entry is still a real relationship', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_plugSwitch),
          DiscoveredEntity(_plugPower),
        ],
        registry: HaRegistry.from(
          entities: <HaEntityEntry>[
            _entity(_plugSwitch, name: 'Lamp', deviceId: 'plug'),
            _entity(_plugPower, name: 'Lamp power', deviceId: 'plug'),
          ],
        ),
      );

      final HouseDeviceGroup cluster = grouping.groups.single.devices.single;
      expect(cluster.deviceId, 'plug');
      expect(cluster.deviceName, isNull);
      expect(cluster.entities, hasLength(2));
    });

    test('malformed registry rows are refused, not coerced', () {
      expect(HaEntityEntry.tryCreate(entityId: 'switch.'), isNull);
      expect(HaEntityEntry.tryCreate(entityId: null), isNull);
      expect(HaEntityEntry.tryCreate(entityId: 'not an id'), isNull);
      expect(HaArea.tryCreate(id: '  '), isNull);
      expect(HaDeviceEntry.tryCreate(id: null), isNull);
      expect(
        HaArea.tryCreate(id: 'outside', name: '')?.name,
        isNull,
        reason: 'a blank name is absent, not a card with no words on it',
      );
    });

    test('and a duplicated registry row keeps the first, not the last', () {
      // So two identical reads of a malformed answer cannot reshuffle the
      // dashboard between them.
      final HaRegistry registry = HaRegistry.from(
        areas: <HaArea>[_area('a', 'First'), _area('a', 'Second')],
        entities: <HaEntityEntry>[
          _entity(_porchLight, name: 'One', areaId: 'a'),
          _entity(_porchLight, name: 'Two', areaId: 'a'),
        ],
      );
      expect(registry.area('a')?.name, 'First');
      expect(registry.entity(_porchLight)?.name, 'One');
    });
  });

  group('favourites first, then rooms, then the unassigned', () {
    test('in the order §4.2 fixes', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_garageLight, friendlyName: 'Garage'),
          DiscoveredEntity(_porchLight),
          DiscoveredEntity(_plugSwitch),
          DiscoveredEntity(_plugPower),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[
            _area('outside', 'Outside'),
            _area('living', 'Living room'),
          ],
          devices: <HaDeviceEntry>[
            _device('porch', 'Porch fitting', 'outside'),
            _device('plug', 'Wall plug', 'living'),
          ],
          entities: <HaEntityEntry>[
            _entity(_porchLight, name: 'Porch', deviceId: 'porch'),
            _entity(_plugSwitch, name: 'Lamp', deviceId: 'plug'),
            _entity(_plugPower, name: 'Lamp power', deviceId: 'plug'),
          ],
        ),
        favourites: <EntityId>[_plugSwitch],
      );

      expect(grouping.groups.map((HouseGroup g) => g.kind), <HouseGroupKind>[
        HouseGroupKind.favourites,
        HouseGroupKind.room,
        HouseGroupKind.room,
        HouseGroupKind.unassigned,
      ]);
      expect(
        grouping.groups.map((HouseGroup g) => g.name).toList(),
        <String?>[null, 'Living room', 'Outside', null],
        reason:
            'rooms alphabetical; Hearth\'s own headings are the UI\'s words',
      );
    });

    test('a favourite is drawn once, in the user\'s own order', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_plugSwitch),
          DiscoveredEntity(_porchLight),
        ],
        registry: HaRegistry.from(
          areas: <HaArea>[_area('living', 'Living room')],
          devices: <HaDeviceEntry>[_device('plug', 'Wall plug', 'living')],
          entities: <HaEntityEntry>[
            _entity(
              _plugSwitch,
              name: 'Lamp',
              deviceId: 'plug',
              areaId: 'living',
            ),
            _entity(_porchLight, name: 'Porch', areaId: 'living'),
          ],
        ),
        favourites: <EntityId>[_porchLight, _plugSwitch],
      );

      expect(
        grouping.groups.first.entities.map((HouseEntityView e) => e.id),
        <EntityId>[_porchLight, _plugSwitch],
      );
      expect(
        grouping.groups,
        hasLength(1),
        reason: 'both favourited, so the room has nothing left to show',
      );
      expect(grouping.entityCount, 2);
      expect(
        grouping.groups.first.devices.first.deviceId,
        isNull,
        reason: 'the porch light has no device; favourites keep user order',
      );
      expect(grouping.groups.first.devices.last.deviceName, 'Wall plug');
    });

    test('and a favourite that is no longer present is not substituted', () {
      // §4.2: a removed selection stays missing. Nothing similar takes its
      // place here, and nothing crashes either.
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: 'Porch'),
        ],
        favourites: <EntityId>[_garageLight],
      );

      expect(grouping.groups.single.kind, HouseGroupKind.unassigned);
      expect(grouping.allEntities.single.id, _porchLight);
      expect(grouping.allEntities.single.isFavourite, isFalse);
    });
  });

  group('nothing is lost and nothing is drawn twice', () {
    test('every entity handed in comes out exactly once', () {
      final List<DiscoveredEntity> entities = <DiscoveredEntity>[
        DiscoveredEntity(_porchLight),
        DiscoveredEntity(_garageLight),
        DiscoveredEntity(_plugSwitch),
        DiscoveredEntity(_plugPower),
      ];
      final HouseGrouping grouping = HouseGrouping.of(
        entities: entities,
        registry: HaRegistry.from(
          areas: <HaArea>[_area('living', 'Living room')],
          devices: <HaDeviceEntry>[_device('plug', 'Wall plug', 'living')],
          entities: <HaEntityEntry>[
            _entity(_plugSwitch, deviceId: 'plug'),
            _entity(_plugPower, deviceId: 'plug', areaId: 'gone'),
            _entity(_porchLight),
          ],
        ),
        favourites: <EntityId>[_porchLight],
      );

      expect(
        grouping.allEntities.map((HouseEntityView e) => e.id).toSet(),
        entities.map((DiscoveredEntity e) => e.id).toSet(),
      );
      expect(grouping.entityCount, 4);
    });

    test('and a repeated entity collapses to one row', () {
      final HouseGrouping grouping = HouseGrouping.of(
        entities: <DiscoveredEntity>[
          DiscoveredEntity(_porchLight, friendlyName: 'Porch'),
          DiscoveredEntity(_porchLight, friendlyName: 'Porch again'),
        ],
      );
      expect(grouping.entityCount, 1);
      expect(grouping.allEntities.single.displayName, 'Porch');
    });
  });
}

final EntityId _porchLight = EntityId.tryParse('light.porch')!;
final EntityId _garageLight = EntityId.tryParse('light.garage')!;
final EntityId _plugSwitch = EntityId.tryParse('switch.lamp_plug')!;
final EntityId _plugPower = EntityId.tryParse('sensor.lamp_plug_power')!;

HaArea _area(String id, String? name) => HaArea.tryCreate(id: id, name: name)!;

HaDeviceEntry _device(String id, String? name, String? areaId) =>
    HaDeviceEntry.tryCreate(id: id, name: name, areaId: areaId)!;

HaEntityEntry _entity(
  EntityId id, {
  String? name,
  String? deviceId,
  String? areaId,
}) => HaEntityEntry.tryCreate(
  entityId: id.value,
  name: name,
  deviceId: deviceId,
  areaId: areaId,
)!;
