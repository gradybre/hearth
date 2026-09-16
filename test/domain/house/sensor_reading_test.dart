import 'dart:io';

import 'package:hearth/domain/house/entity_id.dart';
import 'package:hearth/domain/house/entity_state.dart';
import 'package:hearth/domain/house/sensor_reading.dart';
import 'package:test/test.dart';

/// A reading has to be either true or silent
/// (`docs/HOME_ASSISTANT_SPEC.md` §3, §4.2).
///
/// Two of these groups are the whole reason the file exists: `on` must mean
/// Open, and nothing that is not a reading may borrow the reassuring word.
void main() {
  EntityState reported(
    String? raw, {
    String? deviceClass,
    String? unit,
    Freshness freshness = Freshness.live,
  }) => EntityState(
    availability: Availability.fromState(raw),
    freshness: freshness,
    raw: raw,
    attributes: <String, Object?>{
      'device_class': ?deviceClass,
      'unit_of_measurement': ?unit,
    },
  );

  BinarySensorReading binary(
    String? raw, {
    String? deviceClass,
    Freshness freshness = Freshness.live,
  }) => BinarySensorReading(
    reported(raw, deviceClass: deviceClass, freshness: freshness),
  );

  NumericSensorReading numeric(
    String? raw, {
    String? deviceClass,
    String? unit,
    Freshness freshness = Freshness.live,
  }) => NumericSensorReading(
    reported(raw, deviceClass: deviceClass, unit: unit, freshness: freshness),
  );

  group("Home Assistant's `on` is the abnormal state, not the switched-on one", () {
    test('a door reporting `on` is Open', () {
      // The one-character mistake: read `on` as "switched on" and every door
      // in the house is reported backwards, and convincingly.
      final BinarySensorReading door = binary('on', deviceClass: 'door');
      expect(door.isActive, isTrue);
      expect(door.words.text, 'Open');
      expect(door.words.tone, SensorTone.attention);
    });

    test('and reporting `off` is Closed', () {
      final BinarySensorReading door = binary('off', deviceClass: 'door');
      expect(door.isActive, isFalse);
      expect(door.words.text, 'Closed');
      expect(door.words.tone, SensorTone.settled);
    });

    test('window and opening are the same contact sensor in other words', () {
      expect(binary('on', deviceClass: 'window').words.text, 'Open');
      expect(binary('off', deviceClass: 'window').words.text, 'Closed');
      expect(binary('on', deviceClass: 'opening').words.text, 'Open');
      expect(binary('off', deviceClass: 'opening').words.text, 'Closed');
    });

    test('motion and occupancy say Detected and Clear', () {
      expect(binary('on', deviceClass: 'motion').words.text, 'Detected');
      expect(binary('off', deviceClass: 'motion').words.text, 'Clear');
      expect(binary('on', deviceClass: 'occupancy').words.text, 'Detected');
      expect(binary('off', deviceClass: 'occupancy').words.text, 'Clear');
    });

    test('moisture says Leak, and Leak is the `on` one', () {
      expect(binary('on', deviceClass: 'moisture').words.text, 'Leak');
      expect(
        binary('on', deviceClass: 'moisture').words.tone,
        SensorTone.attention,
      );
      expect(binary('off', deviceClass: 'moisture').words.text, 'Dry');
    });

    test('a binary battery is Low when `on` — a full battery reads `off`', () {
      // The same inversion again, and the one people get backwards most: `on`
      // here is the fault condition.
      expect(binary('on', deviceClass: 'battery').words.text, 'Low');
      expect(
        binary('on', deviceClass: 'battery').words.tone,
        SensorTone.attention,
      );
      expect(binary('off', deviceClass: 'battery').words.text, 'OK');
    });

    test('an unrecognised class gets neutral words, not borrowed ones', () {
      final BinarySensorReading odd = binary('on', deviceClass: 'tamper');
      expect(odd.deviceClass, BinarySensorClass.unrecognised);
      expect(odd.words.text, 'Active');
      expect(
        odd.words.text,
        isNot(anyOf('Open', 'Closed', 'Leak', 'Dry')),
        reason: 'guessing a class is how a tamper sensor reports a door',
      );
      expect(binary('off', deviceClass: 'tamper').words.text, 'Inactive');
    });

    test('and so does a sensor with no class at all', () {
      expect(binary('on').deviceClass, BinarySensorClass.unrecognised);
      expect(binary('on').words.text, 'Active');
    });
  });

  group('unknown is never rendered as safe or inactive', () {
    // Every binary class, every way of having no reading. A door sensor with a
    // flat battery reports nothing, and rendering nothing as "Closed" tells
    // somebody the house is secure at the moment it stopped being able to say.
    for (final BinarySensorClass klass in BinarySensorClass.values) {
      for (final MapEntry<String, EntityState> silence in <String, EntityState>{
        'unknown': reported('unknown', deviceClass: klass.wire),
        'unavailable': reported('unavailable', deviceClass: klass.wire),
        'no state at all': reported(null, deviceClass: klass.wire),
        'a state string nobody understands': reported(
          'jammed',
          deviceClass: klass.wire,
        ),
        'never read': EntityState(
          availability: Availability.unknown,
          freshness: Freshness.neverRead,
          attributes: <String, Object?>{'device_class': klass.wire},
        ),
      }.entries) {
        test('${klass.name}: ${silence.key} is not "${klass.restingWord}"', () {
          final BinarySensorReading sensor = BinarySensorReading(silence.value);
          expect(
            sensor.words.text,
            isNot(klass.restingWord),
            reason: 'silence must never read as the reassuring word',
          );
          expect(
            sensor.words.text,
            isNot(klass.activeWord),
            reason: 'nor as an alarm nobody actually raised',
          );
          expect(sensor.words.tone, SensorTone.noReading);
          expect(sensor.words.hasReading, isFalse);
          expect(sensor.hasReading, isFalse);
          expect(
            sensor.isActive,
            isNull,
            reason: 'there is no boolean to give; a default here is a lie',
          );
        });
      }
    }

    test('unavailable and unknown stay different sentences', () {
      // §4.2 keeps them distinct all the way to the screen: one is a thing
      // that has not said, the other a thing nobody can reach.
      expect(
        binary('unavailable', deviceClass: 'door').words.text,
        'Unavailable',
      );
      expect(binary('unknown', deviceClass: 'door').words.text, 'Unknown');
    });

    test('a cold offline launch invents nothing (§5.3)', () {
      const EntityState cold = EntityState.neverRead();
      expect(const BinarySensorReading(cold).words.text, 'Connect to update');
      expect(const NumericSensorReading(cold).words.text, 'Connect to update');
      expect(const NumericSensorReading(cold).value, isNull);
    });
  });

  group('a value nobody can verify is qualified, never dropped', () {
    test('"Last known: closed", not "Closed"', () {
      final BinarySensorReading door = binary(
        'off',
        deviceClass: 'door',
        freshness: Freshness.lastKnown,
      );
      expect(door.words.text, 'Last known: closed');
      expect(door.words.isLastKnown, isTrue);
      expect(door.words.hasReading, isTrue);
    });

    test('an unverifiable open door still reads as one worth noticing', () {
      final BinarySensorReading door = binary(
        'on',
        deviceClass: 'door',
        freshness: Freshness.lastKnown,
      );
      expect(door.words.text, 'Last known: open');
      expect(
        door.words.tone,
        SensorTone.attention,
        reason: 'the doubt belongs in the wording, not in dropping the icon',
      );
    });

    test('an acronym stays an acronym mid-sentence', () {
      expect(
        binary(
          'off',
          deviceClass: 'battery',
          freshness: Freshness.lastKnown,
        ).words.text,
        'Last known: OK',
      );
    });

    test('and a stale number keeps its unit', () {
      expect(
        numeric(
          '21.5',
          deviceClass: 'temperature',
          unit: '°C',
          freshness: Freshness.lastKnown,
        ).words.text,
        'Last known: 21.5 °C',
      );
    });
  });

  group('numeric readings: missing is not zero', () {
    test('a value is shown with the unit that was reported', () {
      final NumericSensorReading temp = numeric(
        '21.5',
        deviceClass: 'temperature',
        unit: '°C',
      );
      expect(temp.value, 21.5);
      expect(temp.unit, '°C');
      expect(temp.deviceClass, NumericSensorClass.temperature);
      expect(temp.words.text, '21.5 °C');
    });

    test('zero is a real reading, which is why absence may not borrow it', () {
      final NumericSensorReading idle = numeric(
        '0',
        deviceClass: 'power',
        unit: 'W',
      );
      expect(idle.value, 0);
      expect(idle.words.text, '0 W');
      expect(idle.hasReading, isTrue);
    });

    for (final String silence in <String>['unavailable', 'unknown']) {
      test('a $silence power sensor has no value, not 0', () {
        final NumericSensorReading dead = numeric(
          silence,
          deviceClass: 'power',
          unit: 'W',
        );
        expect(dead.value, isNull, reason: 'no reading is not a reading of 0');
        expect(dead.words.text, isNot(contains('0')));
        expect(dead.words.tone, SensorTone.noReading);
        expect(dead.hasReading, isFalse);
      });
    }

    test('a number that is not a number is Unknown, still not 0', () {
      final NumericSensorReading broken = numeric('n/a', unit: 'W');
      expect(broken.value, isNull);
      expect(broken.words.text, 'Unknown');
    });

    test('the sensor keeps its own precision', () {
      // 21.0 and 21 are different statements about a thermometer, so the
      // digits go out exactly as they came in.
      expect(numeric('21.0', unit: '°C').words.text, '21.0 °C');
      expect(numeric('21', unit: '°C').words.text, '21 °C');
    });

    test('a unitless sensor is shown without an invented unit', () {
      final NumericSensorReading count = numeric('3');
      expect(count.unit, isNull);
      expect(count.words.text, '3');
    });

    test('and an empty unit string counts as none', () {
      expect(numeric('3', unit: '   ').unit, isNull);
      expect(numeric('3', unit: '   ').words.text, '3');
    });

    test('no threshold turns a low battery into an alarm by itself', () {
      // Where the warning line sits is Brendan's call (§12), not a default
      // invented in the domain layer.
      expect(
        numeric('4', deviceClass: 'battery', unit: '%').words.tone,
        SensorTone.settled,
      );
    });
  });

  group('a sensor is read-only', () {
    test('the domain decides what a reading is, never the name', () {
      // `switch.front_door_sensor` reports `on` too. §3 forbids inferring
      // semantics from a name, and a switch drawn as a door is a control on
      // something nobody meant to operate.
      final EntityId? id = EntityId.tryParse('switch.front_door_sensor');
      expect(SensorReading.forEntity(id!, reported('on')), isNull);
      expect(
        SensorReading.forEntity(
          EntityId.tryParse('binary_sensor.front_door')!,
          reported('on', deviceClass: 'door'),
        ),
        isA<BinarySensorReading>(),
      );
      expect(
        SensorReading.forEntity(
          EntityId.tryParse('sensor.hall_temperature')!,
          reported('21'),
        ),
        isA<NumericSensorReading>(),
      );
      expect(
        SensorReading.forEntity(
          EntityId.tryParse('light.kitchen')!,
          reported('on'),
        ),
        isNull,
      );
    });

    test('and nothing in this file can operate anything', () {
      // §3: never imply a sensor can open or lock a door. The guard is on the
      // source rather than the API because the absence of a method is exactly
      // what cannot be asserted from the outside.
      const String path = 'lib/domain/house/sensor_reading.dart';
      final List<String> code = File(path).readAsLinesSync();
      const List<String> operating = <String>[
        'call_service',
        'turn_on',
        'turn_off',
        'Command',
        'execute',
      ];
      final List<String> offenders = <String>[
        for (int i = 0; i < code.length; i++)
          // Comments may name these; only code may not contain them. The line
          // number is the real one in the file, so a failure points at it.
          if (!code[i].trimLeft().startsWith('//'))
            for (final String word in operating)
              if (code[i].contains(word)) '$path:${i + 1}  ${code[i].trim()}',
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'a sensor is read-only; move anything that operates hardware into '
            'the command layer:\n${offenders.join('\n')}',
      );
    });
  });

  group('a battery is associated with a device, not chosen separately', () {
    test('no associated battery is not a full one', () {
      // A mains-powered device has nothing to say here. "OK" would be an
      // answer to a question it was never asked.
      const SensorWithBattery mains = SensorWithBattery(
        reading: BinarySensorReading(EntityState.neverRead()),
      );
      expect(mains.battery, isNull);
      expect(mains.batteryWords, isNull);
    });

    test('an associated battery reads as its own percentage', () {
      final SensorWithBattery door = SensorWithBattery(
        reading: binary('off', deviceClass: 'door'),
        battery: numeric('42', deviceClass: 'battery', unit: '%'),
      );
      expect(door.reading.words.text, 'Closed');
      expect(door.batteryWords!.text, '42 %');
    });

    test('and a silent battery does not report 100%', () {
      final SensorWithBattery door = SensorWithBattery(
        reading: binary('off', deviceClass: 'door'),
        battery: numeric('unavailable', deviceClass: 'battery', unit: '%'),
      );
      expect(door.batteryWords!.tone, SensorTone.noReading);
      expect(door.batteryWords!.text, 'Unavailable');
    });
  });

  group('SensorWords is a value', () {
    test('equal words compare equal', () {
      expect(
        binary('on', deviceClass: 'door').words,
        binary('on', deviceClass: 'window').words,
      );
      expect(
        binary('on', deviceClass: 'door').words,
        isNot(binary('off', deviceClass: 'door').words),
      );
      expect(
        binary('on', deviceClass: 'door').words.hashCode,
        binary('on', deviceClass: 'window').words.hashCode,
      );
    });
  });
}
