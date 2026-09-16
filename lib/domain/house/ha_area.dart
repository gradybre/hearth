/// Which room a thing is in, and who is allowed to decide that
/// (`docs/HOME_ASSISTANT_SPEC.md` §4.2, and §3's "do not infer identity from
/// similar names").
///
/// Pure Dart, like the rest of `lib/domain/` — no Flutter, no client, no
/// wire format. The registries arrive here already turned into plain values,
/// so every rule below can be tested without a Raspberry Pi answering.
///
/// The rule this file exists to hold: **grouping follows registry
/// relationships, never resemblance.** Home Assistant knows which entities
/// belong to which device and which device sits in which area; it says so with
/// ids. Two entities that both say "Front Door" are evidence of nothing — a
/// porch light and a garage light get named alike in every house — and an app
/// that clusters on that eventually puts a control on the wrong physical
/// thing. §9's matrix spells out the same thing from the other end: duplicate
/// friendly names are a required test case, and "never retarget by label".
///
/// Two failures are therefore structurally impossible here rather than merely
/// avoided:
///
///  * **Nothing merges by name.** The only clustering key is a device id.
///  * **Nothing disappears.** Every entity handed in comes out in exactly one
///    group; missing metadata costs an entity its *room*, never its place on
///    the dashboard. A registry Hearth cannot read at all — §6 says asking for
///    administrator rights is not allowed, so this is ordinary operation and
///    not an error — degrades to names and one unassigned group.
library;

import 'package:meta/meta.dart';

import 'entity_id.dart';

/// Trimmed, with blank treated as absent.
///
/// Home Assistant will hand back `""` for a name nobody set, and an empty
/// string rendered as a label is a card with no words on it. Absent is the
/// honest answer, and callers already have to handle absent.
String? _clean(String? value) {
  if (value == null) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// One room, as Home Assistant's area registry describes it.
///
/// Hearth never invents, renames, or reorders these — §4.2 keeps names and
/// rooms owned by Home Assistant.
@immutable
class HaArea {
  const HaArea._({required this.id, this.name});

  /// Null when the entry carries no usable id.
  ///
  /// Null rather than throwing: §9 requires malformed metadata to cost one
  /// skipped registry row, not the dashboard. An area Hearth cannot identify
  /// simply stops being able to name a room, and the entities that pointed at
  /// it are still drawn.
  static HaArea? tryCreate({required String? id, String? name}) {
    final String? areaId = _clean(id);
    if (areaId == null) return null;
    return HaArea._(id: areaId, name: _clean(name));
  }

  final String id;

  /// Null when the registry gave no name. The words for that are the UI's —
  /// this layer will not put an id where a room name goes.
  final String? name;
}

/// One physical device, as the device registry describes it.
///
/// This is the relationship that makes "related entities" a fact rather than a
/// guess: a plug that reports power exposes a switch and two sensors, and they
/// belong together because they share this id.
@immutable
class HaDeviceEntry {
  const HaDeviceEntry._({required this.id, this.name, this.areaId});

  /// Null when the entry carries no usable id — see [HaArea.tryCreate].
  static HaDeviceEntry? tryCreate({
    required String? id,
    String? name,
    String? areaId,
  }) {
    final String? deviceId = _clean(id);
    if (deviceId == null) return null;
    return HaDeviceEntry._(
      id: deviceId,
      name: _clean(name),
      areaId: _clean(areaId),
    );
  }

  final String id;
  final String? name;

  /// The room the device sits in. An entity of this device inherits it — but
  /// only when that entity does not name a room of its own.
  final String? areaId;
}

/// One entity, as the entity registry describes it.
@immutable
class HaEntityEntry {
  const HaEntityEntry._({
    required this.id,
    this.name,
    this.deviceId,
    this.areaId,
  });

  /// Null when the entry has no id Hearth can address.
  ///
  /// [EntityId.tryParse] is the same gate every other entity id passes, so a
  /// registry row for `switch.` or `not an id` is dropped here rather than
  /// becoming a row nothing can ever be sent to.
  static HaEntityEntry? tryCreate({
    required String? entityId,
    String? name,
    String? deviceId,
    String? areaId,
  }) {
    final EntityId? id = EntityId.tryParse(_clean(entityId));
    if (id == null) return null;
    return HaEntityEntry._(
      id: id,
      name: _clean(name),
      deviceId: _clean(deviceId),
      areaId: _clean(areaId),
    );
  }

  final EntityId id;
  final String? name;

  /// The device this entity belongs to, when the registry says so.
  final String? deviceId;

  /// The entity's own room. §4.2: this overrides the device's area where
  /// provided — the in-wall switch lives in the hall even though its device is
  /// filed under the living room.
  final String? areaId;
}

/// The three registries, or the honest absence of them.
///
/// [HaRegistry.unavailable] is not an error state. §6 forbids demanding
/// administrator credentials for basic control, and registry access is exactly
/// what may need them, so a perfectly healthy connection can land here. What
/// changes is only how much Hearth is able to say: names still work, rooms and
/// device relationships do not exist, and [HouseGrouping] degrades to a single
/// unassigned group.
@immutable
class HaRegistry {
  const HaRegistry._({
    required Map<String, HaArea> areas,
    required Map<String, HaDeviceEntry> devices,
    required Map<EntityId, HaEntityEntry> entities,
    required this.isAvailable,
  }) : _areas = areas,
       _devices = devices,
       _entities = entities;

  /// Registry metadata could not be read. Ordinary operation, not a failure.
  const HaRegistry.unavailable()
    : _areas = const <String, HaArea>{},
      _devices = const <String, HaDeviceEntry>{},
      _entities = const <EntityId, HaEntityEntry>{},
      isAvailable = false;

  /// Builds an index. Duplicate ids keep the first entry seen.
  ///
  /// First-wins rather than last-wins so the result does not depend on how a
  /// server happened to order its response: a dashboard whose rooms reshuffle
  /// between two identical reads is its own kind of wrong. Duplicates are not
  /// expected — this is defence against a malformed answer, per §9.
  factory HaRegistry.from({
    Iterable<HaArea> areas = const <HaArea>[],
    Iterable<HaDeviceEntry> devices = const <HaDeviceEntry>[],
    Iterable<HaEntityEntry> entities = const <HaEntityEntry>[],
  }) {
    final Map<String, HaArea> areaById = <String, HaArea>{};
    for (final HaArea area in areas) {
      areaById.putIfAbsent(area.id, () => area);
    }
    final Map<String, HaDeviceEntry> deviceById = <String, HaDeviceEntry>{};
    for (final HaDeviceEntry device in devices) {
      deviceById.putIfAbsent(device.id, () => device);
    }
    final Map<EntityId, HaEntityEntry> entityById = <EntityId, HaEntityEntry>{};
    for (final HaEntityEntry entity in entities) {
      entityById.putIfAbsent(entity.id, () => entity);
    }
    return HaRegistry._(
      areas: areaById,
      devices: deviceById,
      entities: entityById,
      isAvailable: true,
    );
  }

  final Map<String, HaArea> _areas;
  final Map<String, HaDeviceEntry> _devices;
  final Map<EntityId, HaEntityEntry> _entities;

  /// False when registry metadata could not be read at all.
  final bool isAvailable;

  /// The named room, or null when this registry has never heard of [id].
  ///
  /// A room Hearth cannot name is still a room; see [areaIdOf].
  HaArea? area(String? id) => id == null ? null : _areas[id];

  /// The device, or null when the registry has no entry under that id.
  HaDeviceEntry? device(String? id) => id == null ? null : _devices[id];

  /// The registry's own record for an entity, or null when it has none.
  HaEntityEntry? entity(EntityId id) => _entities[id];

  /// Which room an entity belongs to, or null for none.
  ///
  /// §4.2's inheritance rule, and the one subtlety in it: an entity area that
  /// this registry cannot *name* is still returned. Falling through to the
  /// device's area would take an entity somebody deliberately moved and file
  /// it back under the room it was moved out of — a hole in the area registry
  /// silently undoing a user's assignment. Better an unnamed room than a
  /// confidently wrong one.
  String? areaIdOf(EntityId id) {
    final HaEntityEntry? entry = _entities[id];
    if (entry == null) return null;
    final String? own = entry.areaId;
    if (own != null) return own;
    return _devices[entry.deviceId]?.areaId;
  }
}

/// An entity the dashboard is showing, as the state snapshot knows it.
///
/// [friendlyName] is the `friendly_name` attribute Home Assistant reports,
/// which already folds in any registry rename. It is the fallback label when
/// the registry is unreadable — §4.2's "use entity names" path.
@immutable
class DiscoveredEntity {
  const DiscoveredEntity(this.id, {this.friendlyName});

  final EntityId id;
  final String? friendlyName;
}

/// What kind of heading a group carries.
enum HouseGroupKind {
  /// The user's own shortlist, first on the dashboard (§4.2).
  favourites,

  /// A Home Assistant area.
  room,

  /// Everything with no area — §4.2 requires this be a *clear* group, so it
  /// is never hidden and never folded into a neighbouring room.
  unassigned,
}

/// One entity as a dashboard would draw it.
@immutable
class HouseEntityView {
  const HouseEntityView({
    required this.id,
    required this.displayName,
    required this.isFavourite,
    required this.nameIsAmbiguous,
  });

  final EntityId id;

  /// Registry name, else the reported friendly name, else the object id.
  ///
  /// The last fallback is deliberately unprettified. Home Assistant owns
  /// names (§4.2), and a label Hearth invented by title-casing a slug reads
  /// exactly like one somebody chose, which makes it impossible to tell that
  /// nobody has named this thing yet.
  final String displayName;

  final bool isFavourite;

  /// True when something else in the same group shows the same name.
  ///
  /// The duplicate-friendly-name case from §9. Hearth may not rename anything,
  /// so the fix is not a better label: it is telling the UI that this label
  /// alone does not identify the row, and that the card needs its device or
  /// its entity id alongside before anyone taps it. §4.2 keeps raw ids in a
  /// details view, so this flag is what earns one a place on the face of the
  /// card.
  final bool nameIsAmbiguous;
}

/// Entities that Home Assistant says belong to the same physical device.
///
/// One device can appear in more than one of these — once per room its
/// entities are assigned to — which is the honest rendering of a device whose
/// entities have been split up. Merging those back together would mean
/// ignoring an assignment somebody made on purpose.
@immutable
class HouseDeviceGroup {
  const HouseDeviceGroup({
    required this.deviceId,
    required this.deviceName,
    required this.entities,
  });

  /// Null when the registry claims no device for these entities, in which
  /// case [entities] holds exactly one. There is no key that could honestly
  /// put two unrelated entities together.
  final String? deviceId;

  /// Null when the device registry has no entry under [deviceId]. The shared
  /// id is still a real relationship worth grouping on; only the name is
  /// missing.
  final String? deviceName;

  final List<HouseEntityView> entities;
}

/// One heading on the dashboard, and what sits under it.
@immutable
class HouseGroup {
  const HouseGroup({
    required this.kind,
    required this.areaId,
    required this.name,
    required this.devices,
  });

  final HouseGroupKind kind;

  /// The Home Assistant area id, non-null exactly for [HouseGroupKind.room].
  final String? areaId;

  /// The room's name, null when the area registry could not supply one.
  ///
  /// Null for favourites and unassigned too: those headings are Hearth's own
  /// words and belong to the UI layer, which has the translations and the
  /// theme. This layer will not hand back an English string to be printed.
  final String? name;

  final List<HouseDeviceGroup> devices;

  /// Every entity under this heading, in render order.
  List<HouseEntityView> get entities => <HouseEntityView>[
    for (final HouseDeviceGroup device in devices) ...device.entities,
  ];
}

/// The whole dashboard: favourites first, then rooms, then the unassigned.
///
/// §4.2 fixes that order, so it is computed here rather than left to a widget
/// to remember.
@immutable
class HouseGrouping {
  const HouseGrouping._(this.groups);

  /// Arranges [entities] into the groups §4.2 describes.
  ///
  /// [favourites] is the user's local shortlist in the user's own order (§2
  /// keeps it device-local). A favourite appears in the favourites group and
  /// *not* again under its room: every entity is drawn exactly once, which is
  /// what makes "nothing was lost" a countable property rather than a hope.
  /// Favourites naming entities that are not present are ignored — a removed
  /// selection is the selection model's problem to report, and §4.2 is clear
  /// it must never be quietly reassigned to a similar entity.
  ///
  /// Duplicates in [entities] collapse to the first occurrence.
  factory HouseGrouping.of({
    required Iterable<DiscoveredEntity> entities,
    HaRegistry registry = const HaRegistry.unavailable(),
    Iterable<EntityId> favourites = const <EntityId>[],
  }) {
    final Map<EntityId, DiscoveredEntity> present =
        <EntityId, DiscoveredEntity>{};
    for (final DiscoveredEntity entity in entities) {
      present.putIfAbsent(entity.id, () => entity);
    }

    final Set<EntityId> favourited = <EntityId>{};
    final List<EntityId> favouriteOrder = <EntityId>[];
    for (final EntityId id in favourites) {
      if (present.containsKey(id) && favourited.add(id)) {
        favouriteOrder.add(id);
      }
    }

    String nameOf(EntityId id) =>
        registry.entity(id)?.name ??
        _clean(present[id]!.friendlyName) ??
        id.objectId;

    HouseEntityView viewOf(EntityId id) => HouseEntityView(
      id: id,
      displayName: nameOf(id),
      isFavourite: favourited.contains(id),
      nameIsAmbiguous: false, // Decided per group, below.
    );

    final List<HouseGroup> groups = <HouseGroup>[];

    // Favourites are a user-ordered shortlist, so each one stands on its own
    // rather than being reshuffled into device clusters. The device is still
    // named on each row for the card to show.
    if (favouriteOrder.isNotEmpty) {
      groups.add(
        _resolveAmbiguity(
          HouseGroup(
            kind: HouseGroupKind.favourites,
            areaId: null,
            name: null,
            devices: <HouseDeviceGroup>[
              for (final EntityId id in favouriteOrder)
                HouseDeviceGroup(
                  deviceId: registry.entity(id)?.deviceId,
                  deviceName: registry
                      .device(registry.entity(id)?.deviceId)
                      ?.name,
                  entities: <HouseEntityView>[viewOf(id)],
                ),
            ],
          ),
        ),
      );
    }

    // Bucket the rest by room. A null key is "no area at all" — which is also
    // every entity when the registry could not be read.
    final Map<String?, List<EntityId>> byArea = <String?, List<EntityId>>{};
    for (final EntityId id in present.keys) {
      if (favourited.contains(id)) continue;
      byArea.putIfAbsent(registry.areaIdOf(id), () => <EntityId>[]).add(id);
    }

    final List<String> roomIds = byArea.keys.nonNulls.toList()
      ..sort((String a, String b) {
        final String? nameA = registry.area(a)?.name;
        final String? nameB = registry.area(b)?.name;
        // Rooms Hearth can name come first, alphabetically; the rest fall to
        // the end in a stable order rather than sorting as if they were blank.
        if (nameA != null && nameB != null) {
          final int byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
          return byName != 0 ? byName : a.compareTo(b);
        }
        if (nameA != null) return -1;
        if (nameB != null) return 1;
        return a.compareTo(b);
      });

    for (final String areaId in roomIds) {
      groups.add(
        _resolveAmbiguity(
          HouseGroup(
            kind: HouseGroupKind.room,
            areaId: areaId,
            name: registry.area(areaId)?.name,
            devices: _cluster(byArea[areaId]!, registry, viewOf),
          ),
        ),
      );
    }

    final List<EntityId>? unassigned = byArea[null];
    if (unassigned != null && unassigned.isNotEmpty) {
      groups.add(
        _resolveAmbiguity(
          HouseGroup(
            kind: HouseGroupKind.unassigned,
            areaId: null,
            name: null,
            devices: _cluster(unassigned, registry, viewOf),
          ),
        ),
      );
    }

    final HouseGrouping grouping = HouseGrouping._(
      List<HouseGroup>.unmodifiable(groups),
    );
    // The invariant the whole file is for: in and out, once each.
    assert(
      grouping.entityCount == present.length,
      'grouping lost or duplicated an entity: '
      '${present.length} in, ${grouping.entityCount} out',
    );
    return grouping;
  }

  /// Favourites, then rooms, then unassigned. Empty groups are omitted.
  final List<HouseGroup> groups;

  /// Every entity on the dashboard, in render order.
  List<HouseEntityView> get allEntities => <HouseEntityView>[
    for (final HouseGroup group in groups) ...group.entities,
  ];

  int get entityCount => allEntities.length;

  /// Groups entities that share a device id, and nothing else.
  ///
  /// The clustering key is the device id or, absent one, the entity's own id —
  /// which can match nothing else, so an entity with no device relationship is
  /// always a cluster of one. That is the structural half of "do not infer
  /// identity from similar names": there is no branch here that could consult
  /// a label even if somebody wanted it to.
  static List<HouseDeviceGroup> _cluster(
    List<EntityId> ids,
    HaRegistry registry,
    HouseEntityView Function(EntityId) viewOf,
  ) {
    final Map<String, List<EntityId>> byDevice = <String, List<EntityId>>{};
    for (final EntityId id in ids) {
      final String? deviceId = registry.entity(id)?.deviceId;
      byDevice
          .putIfAbsent(deviceId ?? 'entity:${id.value}', () => <EntityId>[])
          .add(id);
    }

    final List<HouseDeviceGroup> clusters = <HouseDeviceGroup>[
      for (final List<EntityId> members in byDevice.values)
        HouseDeviceGroup(
          deviceId: registry.entity(members.first)?.deviceId,
          deviceName: registry
              .device(registry.entity(members.first)?.deviceId)
              ?.name,
          entities: <HouseEntityView>[
            for (final EntityId id in members) viewOf(id),
          ]..sort(_byLabelThenId),
        ),
    ];

    clusters.sort((HouseDeviceGroup a, HouseDeviceGroup b) {
      final String? nameA = a.deviceName;
      final String? nameB = b.deviceName;
      if (nameA != null && nameB != null) {
        final int byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
        if (byName != 0) return byName;
      } else if (nameA != null) {
        return -1;
      } else if (nameB != null) {
        return 1;
      }
      // Named-alike or unnamed alike: fall through to ids, which are unique,
      // so the order is total and a redraw cannot reshuffle the dashboard.
      return a.entities.first.id.value.compareTo(b.entities.first.id.value);
    });
    return List<HouseDeviceGroup>.unmodifiable(clusters);
  }

  static int _byLabelThenId(HouseEntityView a, HouseEntityView b) {
    final int byName = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    return byName != 0 ? byName : a.id.value.compareTo(b.id.value);
  }

  /// Marks every row whose label is shared by another row under the same
  /// heading.
  ///
  /// Scoped to the group because that is what a reader sees at once: the same
  /// name in two different rooms is told apart by the rooms. Within one
  /// heading nothing tells them apart, so the card has to say more.
  static HouseGroup _resolveAmbiguity(HouseGroup group) {
    final Map<String, int> counts = <String, int>{};
    for (final HouseEntityView entity in group.entities) {
      final String key = entity.displayName.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (!counts.values.any((int count) => count > 1)) return group;

    return HouseGroup(
      kind: group.kind,
      areaId: group.areaId,
      name: group.name,
      devices: List<HouseDeviceGroup>.unmodifiable(<HouseDeviceGroup>[
        for (final HouseDeviceGroup device in group.devices)
          HouseDeviceGroup(
            deviceId: device.deviceId,
            deviceName: device.deviceName,
            entities: <HouseEntityView>[
              for (final HouseEntityView entity in device.entities)
                HouseEntityView(
                  id: entity.id,
                  displayName: entity.displayName,
                  isFavourite: entity.isFavourite,
                  nameIsAmbiguous:
                      (counts[entity.displayName.toLowerCase()] ?? 0) > 1,
                ),
            ],
          ),
      ]),
    );
  }
}
