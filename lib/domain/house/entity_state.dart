/// What a thing is doing, and how sure Hearth is about it
/// (`docs/HOME_ASSISTANT_SPEC.md` §4.2, §6.1).
///
/// Pure Dart. The whole point of this file is one distinction the spec makes
/// four separate times, in four different words:
///
///  * an opened door says **Open**;
///  * a lost connection says **Unavailable**, or **Last known: closed** —
///    never an unqualified **Closed**;
///  * unknown is never rendered as safe or inactive;
///  * a broken connection makes the whole snapshot unverified, even when the
///    individual timestamps look recent.
///
/// Those are all the same rule: *absence of news is not good news.* A door
/// sensor whose battery died reports nothing, and an app that renders nothing
/// as "Closed" tells you the house is secure because it stopped being able to
/// tell. So there is no path through this file that turns an unknown into a
/// boolean without the caller saying what to do about it.
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Whether Home Assistant currently knows the answer.
///
/// Home Assistant spells two of these as ordinary state strings — `unknown`
/// and `unavailable` — which is why they have to be lifted out before any
/// value is read. A sensor whose state string is literally `unavailable` does
/// not have the value "unavailable"; it has no value.
enum Availability {
  /// Home Assistant has a current answer.
  known,

  /// The entity exists and Home Assistant is talking to it, but it has not
  /// reported a value — a sensor that has never sent one, or one that has
  /// explicitly said it does not know.
  unknown,

  /// Home Assistant cannot reach the thing. The integration is down, the
  /// battery is flat, the hub is unplugged.
  unavailable;

  static Availability fromState(String? state) => switch (state) {
    null => Availability.unknown,
    'unknown' => Availability.unknown,
    'unavailable' => Availability.unavailable,
    _ => Availability.known,
  };

  /// Whether a value can be read at all. False for both failure kinds, which
  /// is the point: the two are shown differently but neither carries a value.
  bool get hasValue => this == known;
}

/// How much Hearth trusts what it is holding, independent of what Home
/// Assistant said (§6.1).
///
/// Separate from [Availability] because they fail independently. Home
/// Assistant can be perfectly sure a door is closed while Hearth's socket has
/// been dead for ten minutes — the reading is *stale* rather than unknown, and
/// the honest words for that are "Last known: closed", not "Closed".
enum Freshness {
  /// Read over a connection that is currently up.
  live,

  /// The last thing a now-broken connection said. Still worth showing, but
  /// only ever qualified.
  lastKnown,

  /// Nothing has ever been read in this session. §5.3 forbids inventing a
  /// reading after a cold offline launch, so a card in this state says
  /// "Connect to update" and shows no value at all.
  neverRead,
}

/// One entity's state at one moment.
///
/// [raw] is the state string exactly as Home Assistant sent it, and is only
/// meaningful when [availability] is [Availability.known] — the two failure
/// kinds put their own words in that field, which is precisely the trap this
/// type exists to close.
@immutable
class EntityState {
  const EntityState({
    required this.availability,
    required this.freshness,
    this.raw,
    this.attributes = const <String, Object?>{},
    this.lastChanged,
    this.lastUpdated,
  });

  /// Nothing read yet: the cold-launch case, with no value to show.
  const EntityState.neverRead()
    : availability = Availability.unknown,
      freshness = Freshness.neverRead,
      raw = null,
      attributes = const <String, Object?>{},
      lastChanged = null,
      lastUpdated = null;

  final Availability availability;
  final Freshness freshness;

  /// The state string, or null when there is none. Never read this without
  /// checking [availability] first — see [value].
  final String? raw;

  final Map<String, Object?> attributes;

  /// When the *value* last changed, per Home Assistant.
  ///
  /// Deliberately separate from [lastUpdated] and from Hearth's own sync time
  /// (§6.1): an unchanged sensor can be healthy for days, and deciding it is
  /// stale because its value has not moved is how a working door sensor gets
  /// reported as broken.
  final DateTime? lastChanged;

  /// When Home Assistant last wrote the entity at all, including attribute
  /// changes that left the value alone.
  final DateTime? lastUpdated;

  /// The state string when there is one, and null otherwise.
  ///
  /// The only supported way to read a value. Returning null for both failure
  /// kinds forces the caller to decide what to show, which is what stops
  /// `unavailable` being rendered as a value in its own right.
  String? get value => availability.hasValue ? raw : null;

  /// Whether this may be shown as a current reading without qualification.
  ///
  /// Both halves have to hold: Home Assistant must know the answer, *and*
  /// Hearth must have heard it over a connection that is still up. Either one
  /// failing means the words on screen have to change.
  bool get isConfident => availability.hasValue && freshness == Freshness.live;

  /// The same reading, demoted because the connection went away.
  ///
  /// [Freshness.neverRead] does not become [Freshness.lastKnown] — there is
  /// nothing to remember, and inventing one is exactly what §5.3 forbids.
  EntityState staleNow() => freshness == Freshness.neverRead
      ? this
      : EntityState(
          availability: availability,
          freshness: Freshness.lastKnown,
          raw: raw,
          attributes: attributes,
          lastChanged: lastChanged,
          lastUpdated: lastUpdated,
        );

  /// Deep, and including [attributes].
  ///
  /// Leaving the attributes out looks harmless — they are "detail", and the
  /// state string is "the value". It is not harmless. A caller deciding
  /// whether anything moved writes the obvious line,
  ///
  ///     if (next == current) return;
  ///
  /// and an attribute-only change vanishes into it — including the event that
  /// confirms a brightness command, which changes `brightness` and nothing
  /// else. Home Assistant's `last_updated` does move when an attribute does,
  /// so the two usually differ by that field anyway; a payload without a
  /// timestamp, and a reading never taken, are where they do not. Leaning on a
  /// neighbouring field to carry a comparison this type claims to make is a
  /// coincidence rather than a contract.
  ///
  /// Deep rather than by identity because `hs_color` arrives as a list, and
  /// comparing the maps by reference would reproduce exactly the same bug one
  /// level further down.
  static const DeepCollectionEquality _attributes = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is EntityState &&
      other.availability == availability &&
      other.freshness == freshness &&
      other.raw == raw &&
      other.lastChanged == lastChanged &&
      other.lastUpdated == lastUpdated &&
      _attributes.equals(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
    availability,
    freshness,
    raw,
    lastChanged,
    lastUpdated,
    _attributes.hash(attributes),
  );
}
