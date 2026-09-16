/// What a sensor is reporting, in words a person can trust
/// (`docs/HOME_ASSISTANT_SPEC.md` §3, §4.2).
///
/// Pure Dart. Two mistakes live here, each one character wide, each one a lie
/// about somebody's house:
///
///  * Home Assistant's `on` means the **active or abnormal** state, not
///    "switched on". A door sensor reporting `on` is *Open*. Read it the other
///    way and every door in the house is reported backwards, convincingly.
///  * absence is not a resting state. There is no path through this file from
///    unknown, unavailable or never-read to *Closed*, *Clear*, *Dry* or `0` —
///    because a door sensor with a flat battery reports nothing, and rendering
///    nothing as Closed tells somebody the house is secure at the moment it
///    stopped being able to tell.
///
/// The three-way distinction those rules need — a value, no value, and a value
/// nobody can currently verify — is already made in `entity_state.dart` and is
/// not re-derived here. This file only decides what to *say*.
///
/// Nothing here produces a control. §3 is explicit that Hearth must never
/// imply a sensor can open or lock a door, so a reading has no command on it,
/// not even when the state it reports is one somebody would want to change.
library;

import 'package:meta/meta.dart';

import 'entity_id.dart';
import 'entity_state.dart';

/// Whether a reading is the one worth noticing, the ordinary resting one, or
/// no reading at all.
///
/// Exists so the UI has something other than colour to switch on — §4.2
/// requires status never to depend on colour alone, which means the icon and
/// the wording have to come from the same decision the colour does.
enum SensorTone {
  /// Open, detected, leaking, low. The state a person would want to know.
  attention,

  /// Closed, clear, dry, fine. The ordinary resting state.
  settled,

  /// Nothing to report. Never [settled]: that conflation is the whole point
  /// of this file.
  noReading,
}

/// A binary sensor's device class, which is what decides the words.
///
/// Home Assistant reports the same `on`/`off` pair for all of these; only the
/// class says whether `on` means a door standing open or water on the floor.
/// An unrecognised class becomes [unrecognised] and gets deliberately colourless
/// words, because "Dry" on a sensor that turns out to measure something else
/// is worse than "Inactive" on one that measures a leak.
enum BinarySensorClass {
  /// §3's door/window/contact row. `on` is open.
  door('door', 'Open', 'Closed'),
  window('window', 'Open', 'Closed'),
  opening('opening', 'Open', 'Closed'),

  /// §3's motion/occupancy row. `on` is movement seen.
  motion('motion', 'Detected', 'Clear'),
  occupancy('occupancy', 'Detected', 'Clear'),

  /// §3's leak row. `on` is wet, which is the alarming one.
  moisture('moisture', 'Leak', 'Dry'),

  /// A battery reported as a binary rather than a percentage. `on` is *low* —
  /// the inversion that catches people, since a full battery reads `off`.
  battery('battery', 'Low', 'OK'),

  /// A class Hearth has no words for.
  unrecognised('', 'Active', 'Inactive');

  const BinarySensorClass(this.wire, this.activeWord, this.restingWord);

  /// The string Home Assistant uses in `device_class`.
  final String wire;

  /// What to say when the sensor reports `on`.
  final String activeWord;

  /// What to say when it reports `off`.
  final String restingWord;

  static BinarySensorClass parse(String? value) => values.firstWhere(
    (BinarySensorClass c) => c.wire == value && c != unrecognised,
    orElse: () => unrecognised,
  );
}

/// A numeric sensor's device class.
///
/// Only the five §3 names. It is deliberately not used to decide the unit:
/// the unit is whatever the sensor reported, because a household with one
/// thermometer in °C and one in °F is an ordinary household and converting
/// either one silently would misreport both.
enum NumericSensorClass {
  temperature('temperature'),
  humidity('humidity'),
  battery('battery'),
  power('power'),
  energy('energy'),
  unrecognised('');

  const NumericSensorClass(this.wire);

  final String wire;

  static NumericSensorClass parse(String? value) => values.firstWhere(
    (NumericSensorClass c) => c.wire == value && c != unrecognised,
    orElse: () => unrecognised,
  );
}

/// The words for one reading, and the tone they carry.
///
/// Built only by [SensorReading.words], so there is exactly one place where an
/// availability turns into a sentence.
@immutable
class SensorWords {
  const SensorWords._(this.text, this.tone, {this.isLastKnown = false});

  /// What to put on the card.
  final String text;

  final SensorTone tone;

  /// Whether [text] is a value Hearth can no longer verify, already qualified
  /// as "Last known: …". Exposed separately so a card can mark the whole row
  /// stale without parsing its own label.
  final bool isLastKnown;

  /// Whether there is a value behind these words at all.
  bool get hasReading => tone != SensorTone.noReading;

  @override
  bool operator ==(Object other) =>
      other is SensorWords &&
      other.text == text &&
      other.tone == tone &&
      other.isLastKnown == isLastKnown;

  @override
  int get hashCode => Object.hash(text, tone, isLastKnown);

  @override
  String toString() => text;
}

/// One sensor, ready to be shown.
///
/// Sealed rather than one class with a nullable number, because the two kinds
/// fail differently: a binary sensor can be neither open nor closed, and a
/// numeric one can have a value with no unit. Both share the refusal to turn
/// silence into reassurance, which lives in [words].
@immutable
sealed class SensorReading {
  const SensorReading(this.state);

  /// What Home Assistant last said, and how much of it Hearth trusts.
  final EntityState state;

  /// The reading for [id], or null when that entity is not a sensor.
  ///
  /// Dispatching on the domain rather than on the shape of the state string is
  /// what stops a switch being drawn as a door: `switch.front_door_sensor`
  /// also reports `on`, and §3 forbids inferring what a thing is from its name.
  static SensorReading? forEntity(EntityId id, EntityState state) =>
      switch (id.domain) {
        HaDomain.binarySensor => BinarySensorReading(state),
        HaDomain.sensor => NumericSensorReading(state),
        _ => null,
      };

  /// The words this reading should be shown as.
  SensorWords get words;

  /// Whether there is a value to show.
  bool get hasReading => words.hasReading;

  /// The reading's `device_class` attribute, or null when it has none.
  String? get _rawDeviceClass => switch (state.attributes['device_class']) {
    final String value => value,
    _ => null,
  };

  /// The words for the cases where there is no value, shared by both kinds.
  ///
  /// Returns null when Home Assistant does have a value — only then does the
  /// caller get as far as choosing a word for it. Every branch here is
  /// [SensorTone.noReading]; there is no route out of this method that reads
  /// as safe or inactive.
  SensorWords? get _absenceWords {
    // Checked before availability: a cold offline launch has no value *and*
    // no history, and §5.3 forbids inventing one to fill the gap.
    if (state.freshness == Freshness.neverRead) {
      return const SensorWords._('Connect to update', SensorTone.noReading);
    }
    return switch (state.availability) {
      Availability.unavailable => const SensorWords._(
        'Unavailable',
        SensorTone.noReading,
      ),
      Availability.unknown => const SensorWords._(
        'Unknown',
        SensorTone.noReading,
      ),
      Availability.known => null,
    };
  }

  /// Wraps a value Hearth can no longer verify: "Last known: closed" (§4.2).
  ///
  /// The word is lower-cased mid-sentence unless it is already an acronym —
  /// "Last known: ok" reads like a typo, which is its own small loss of trust.
  static SensorWords _lastKnown(String word, SensorTone tone) => SensorWords._(
    'Last known: ${word == word.toUpperCase() ? word : word.toLowerCase()}',
    tone,
    isLastKnown: true,
  );
}

/// A door, window, motion, leak or battery sensor.
final class BinarySensorReading extends SensorReading {
  const BinarySensorReading(super.state);

  /// What kind of thing this measures, and therefore which words it gets.
  BinarySensorClass get deviceClass => BinarySensorClass.parse(_rawDeviceClass);

  /// True for `on`, false for `off`, and **null when there is no answer**.
  ///
  /// Nullable on purpose: a `bool` here would need a default, and every
  /// available default is a lie about a door. Unknown, unavailable, never read
  /// and a state string that is neither `on` nor `off` all land on null, so a
  /// caller has to say out loud what it wants to show for them.
  bool? get isActive => switch (state.value) {
    'on' => true,
    'off' => false,
    // Home Assistant should only ever send those two for a binary sensor.
    // Anything else is metadata Hearth does not understand, and §9 requires
    // that to cost one honest "Unknown" rather than a guess or a crash.
    _ => null,
  };

  @override
  SensorWords get words {
    final SensorWords? absent = _absenceWords;
    if (absent != null) return absent;

    final bool? active = isActive;
    if (active == null) {
      return const SensorWords._('Unknown', SensorTone.noReading);
    }

    final String word = active
        ? deviceClass.activeWord
        : deviceClass.restingWord;
    // An open door nobody can currently see is still worth an icon, so the
    // tone follows the value; the doubt is carried by the wording.
    final SensorTone tone = active ? SensorTone.attention : SensorTone.settled;

    return state.freshness == Freshness.lastKnown
        ? SensorReading._lastKnown(word, tone)
        : SensorWords._(word, tone);
  }
}

/// A temperature, humidity, battery, power or energy reading.
final class NumericSensorReading extends SensorReading {
  const NumericSensorReading(super.state);

  NumericSensorClass get deviceClass =>
      NumericSensorClass.parse(_rawDeviceClass);

  /// The unit Home Assistant reported, or null when it reported none.
  ///
  /// Null rather than a guessed default: §3 says "with reported units", and a
  /// number shown next to the wrong unit is wrong twice over.
  String? get unit => switch (state.attributes['unit_of_measurement']) {
    final String value when value.trim().isNotEmpty => value.trim(),
    _ => null,
  };

  /// The number, or **null when there is no reading** (§3: "Missing is not
  /// zero").
  ///
  /// Zero is a real reading a real meter takes — a plug drawing no power says
  /// 0 W — which is exactly why absence may never borrow it. A sensor that has
  /// not reported has no value; it has not reported 0.
  double? get value => double.tryParse(state.value?.trim() ?? '');

  @override
  SensorWords get words {
    final SensorWords? absent = _absenceWords;
    if (absent != null) return absent;

    // Known, but not a number Dart can read. Same answer as any other
    // metadata Hearth does not understand, and still not 0.
    if (value == null) {
      return const SensorWords._('Unknown', SensorTone.noReading);
    }

    // The digits exactly as Home Assistant sent them. Re-formatting would mean
    // choosing a precision the sensor never claimed: `21.0` and `21` are
    // different statements about a thermometer.
    final String digits = state.value!.trim();
    final String text = unit == null ? digits : '$digits ${unit!}';

    // No thresholds. Whether 18% battery or 21 °C deserves attention is a
    // product decision (§12: open decisions are Brendan's), and inventing one
    // here would put a warning icon on a reading nobody asked to be warned
    // about.
    return state.freshness == Freshness.lastKnown
        ? SensorReading._lastKnown(text, SensorTone.settled)
        : SensorWords._(text, SensorTone.settled);
  }
}

/// A chosen device's reading together with the battery that belongs to it.
///
/// §3: read-only diagnostics such as battery are excluded from discovery by
/// default but "may be associated with a chosen device" — the person picked a
/// door sensor, not a door sensor and a battery percentage, and should still
/// be told when the thing is about to stop reporting.
///
/// [battery] being null means no battery entity was associated. It does not
/// mean the battery is empty, and it does not mean it is full: a device on
/// mains power has nothing to say here at all.
@immutable
class SensorWithBattery {
  const SensorWithBattery({required this.reading, this.battery});

  /// The reading the person actually chose.
  final SensorReading reading;

  /// Its battery level, where one was associated.
  final NumericSensorReading? battery;

  /// The battery's words, or null when there is no associated battery.
  ///
  /// Null rather than "OK": a device that reports no battery is not a device
  /// reporting a healthy one, and the difference matters on the card that is
  /// meant to warn you before a door sensor goes quiet.
  SensorWords? get batteryWords => battery?.words;
}
