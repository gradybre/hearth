/// What Home Assistant calls a thing, and what Hearth is allowed to infer
/// from that (spec §11, `docs/HOME_ASSISTANT_SPEC.md` §3).
///
/// Pure Dart, like the rest of `lib/domain/` — no Flutter, no sockets, no
/// Home Assistant client. Everything here is about identity and meaning, so
/// both can be tested without a Raspberry Pi on the other end.
///
/// The rule this file exists to hold: **an entity id is an identity, not a
/// description.** `switch.front_door_light` is a switch somebody named after a
/// light, and reading the name as a capability is how an app ends up offering
/// a brightness slider that can only ever fail. The domain before the dot says
/// what *kind* of thing it is; what it can actually do comes from the
/// attributes Home Assistant reports, never from the words in the id.
library;

import 'package:meta/meta.dart';

/// The part of an entity id before the dot.
///
/// Deliberately not every domain Home Assistant has: this is the list of
/// things Hearth knows how to draw. Anything else parses to [unsupported],
/// which is a real answer the discovery screen shows — "Hearth cannot do
/// anything with this yet" — rather than a crash or, worse, a guess. §3 defers
/// locks, covers, alarms, scenes and the rest deliberately, and most of a real
/// Home Assistant is domains this app has no business touching.
enum HaDomain {
  /// Doors, windows, motion, leaks. Read-only; the device class says which
  /// words to use.
  binarySensor('binary_sensor'),

  /// Numbers with units: temperature, humidity, battery, power, energy.
  sensor('sensor'),

  /// Plugs and ordinary switches.
  switch_('switch'),

  /// Bulbs. Capabilities vary per bulb and are read from attributes.
  light('light'),

  /// Cameras and doorbells.
  camera('camera'),

  /// Doorbell rings and motion, as discrete happenings rather than states.
  event('event'),

  /// A domain Hearth does not draw.
  unsupported('');

  const HaDomain(this.wire);

  /// The string Home Assistant uses.
  final String wire;

  /// Whether Hearth can show this at all.
  bool get isSupported => this != unsupported;

  static HaDomain parse(String? value) => values.firstWhere(
    (HaDomain d) => d.wire == value && d != unsupported,
    orElse: () => unsupported,
  );
}

/// A Home Assistant entity id, parsed once so nothing downstream has to.
///
/// Home Assistant guarantees the shape `domain.object_id`. This refuses
/// anything else rather than coercing it: an id that does not parse is an id
/// Hearth cannot address, and pretending otherwise would mean sending a
/// command somewhere unintended. §6.2 is explicit that a command carries one
/// specific selected entity — which requires knowing exactly what that entity
/// is.
@immutable
class EntityId {
  const EntityId._({
    required this.domain,
    required this.domainName,
    required this.objectId,
  });

  /// Null when [raw] is not a well-formed entity id.
  ///
  /// Null rather than throwing, because malformed metadata is one of the
  /// cases §9 requires discovery to survive: a server answering with something
  /// unexpected should cost one skipped row, not the screen.
  static EntityId? tryParse(String? raw) {
    if (raw == null) return null;
    final int dot = raw.indexOf('.');
    // No dot, nothing before it, or nothing after it. A trailing dot is a
    // domain with no object, which addresses *every* entity in that domain —
    // exactly the empty target §6.2 forbids.
    if (dot <= 0 || dot == raw.length - 1) return null;
    // A second dot means this is not an entity id, whatever else it is.
    if (raw.indexOf('.', dot + 1) != -1) return null;

    final String domainName = raw.substring(0, dot);
    final String objectId = raw.substring(dot + 1);
    // Home Assistant's own slug rules: lower-case, digits, underscore. Being
    // strict here is what lets the rest of the app treat an `EntityId` as safe
    // to put in a request without re-checking it.
    if (!_slug.hasMatch(domainName) || !_slug.hasMatch(objectId)) return null;

    return EntityId._(
      domain: HaDomain.parse(domainName),
      domainName: domainName,
      objectId: objectId,
    );
  }

  static final RegExp _slug = RegExp(r'^[a-z0-9_]+$');

  /// What kind of thing this is. [HaDomain.unsupported] for a domain Hearth
  /// does not draw — which is still a valid, addressable id.
  final HaDomain domain;

  /// The domain exactly as Home Assistant spelled it.
  ///
  /// Kept as well as [domain] because an unsupported domain has no enum value
  /// to rebuild from, and a discovery screen that says "Hearth cannot show
  /// `lock`" is more use than one that says "Hearth cannot show ``". It is
  /// also what goes back on the wire, so a round trip is exact.
  final String domainName;

  /// The part after the dot.
  final String objectId;

  /// The id as Home Assistant spells it.
  String get value => '$domainName.$objectId';

  @override
  bool operator ==(Object other) =>
      other is EntityId &&
      other.domainName == domainName &&
      other.objectId == objectId;

  @override
  int get hashCode => Object.hash(domainName, objectId);

  @override
  String toString() => value;
}
