import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_thermostat.dart';
import 'package:hearth/data/adapters/thermostat.dart';
import 'package:hearth/domain/house/thermostat.dart';

/// The seam between Google's shape and Hearth's (spec §11).
void main() {
  group('reading what the function sent', () {
    test('a linked household with a reading', () {
      final ThermostatLink link = EdgeFunctionThermostat.linkFrom(
        <Object?, Object?>{
          'linked': true,
          'linkedByYou': true,
          'linkedAt': '2026-09-13T12:00:00Z',
          'device': <Object?, Object?>{
            'label': 'Hallway',
            'ambientC': 21.4,
            'humidityPercent': 43,
            'mode': 'HEAT',
            'availableModes': <Object?>['OFF', 'HEAT'],
            'hvac': 'HEATING',
            'heatC': 20.0,
            'eco': 'OFF',
          },
        },
      );

      expect(link.isLinked, isTrue);
      expect(link.linkedByYou, isTrue);
      expect(link.state!.label, 'Hallway');
      expect(link.state!.mode, ThermostatMode.heat);
      expect(link.state!.availableModes, <ThermostatMode>{
        ThermostatMode.off,
        ThermostatMode.heat,
      });
      expect(link.state!.hasFan, isFalse);
    });

    test('and a household that has never linked one', () {
      expect(
        EdgeFunctionThermostat.linkFrom(<Object?, Object?>{'linked': false})
            .isLinked,
        isFalse,
      );
    });

    test('but "linked, and nothing to show" is a failure, not an absence', () {
      // The server says this household has a thermostat. Reporting no
      // thermostat would put a Connect button in front of somebody whose link
      // is fine, and pressing it starts a consent flow for no reason.
      expect(
        () => EdgeFunctionThermostat.linkFrom(<Object?, Object?>{
          'linked': true,
          'device': null,
        }),
        throwsA(isA<ThermostatException>()),
      );
    });

    test('a mode this build has never heard of does not blank the screen', () {
      final ThermostatLink link = EdgeFunctionThermostat.linkFrom(
        <Object?, Object?>{
          'linked': true,
          'device': <Object?, Object?>{
            'label': 'Hallway',
            'ambientC': 20,
            'mode': 'DEHUMIDIFY',
            'availableModes': <Object?>['OFF', 'DEHUMIDIFY'],
            'hvac': 'DEFROSTING',
            'eco': 'OFF',
          },
        },
      );

      expect(link.state!.mode, ThermostatMode.unknown);
      expect(link.state!.hvac, HvacStatus.unknown);
      expect(link.state!.availableModes, <ThermostatMode>{
        ThermostatMode.off,
      }, reason: 'an unknown mode is not offered as a button');
    });

    test('a device that did not say how warm it is is a failure', () {
      expect(
        () => EdgeFunctionThermostat.linkFrom(<Object?, Object?>{
          'linked': true,
          'device': <Object?, Object?>{'label': 'Hallway'},
        }),
        throwsA(isA<ThermostatException>()),
      );
    });
  });

  group('what goes out on the wire', () {
    test('each command carries only what it needs', () {
      expect(
        EdgeFunctionThermostat.wireFor(const SetHeat(20)),
        <String, Object?>{'kind': 'setHeat', 'heatC': 20.0},
      );
      expect(
        EdgeFunctionThermostat.wireFor(const SetRange(heatC: 20, coolC: 24)),
        <String, Object?>{'kind': 'setRange', 'heatC': 20.0, 'coolC': 24.0},
      );
      expect(
        EdgeFunctionThermostat.wireFor(const SetMode(ThermostatMode.heatCool)),
        <String, Object?>{'kind': 'setMode', 'mode': 'HEATCOOL'},
      );
      expect(
        EdgeFunctionThermostat.wireFor(const SetEco(on: true)),
        <String, Object?>{'kind': 'setEco', 'on': true},
      );
    });

    test('and the fan timer goes out in seconds, the way the trait wants', () {
      expect(
        EdgeFunctionThermostat.wireFor(
          const SetFanTimer(on: true, duration: Duration(minutes: 15)),
        ),
        <String, Object?>{
          'kind': 'setFanTimer',
          'on': true,
          'duration': '900s',
        },
      );
      expect(
        EdgeFunctionThermostat.wireFor(const SetFanTimer(on: false)),
        <String, Object?>{'kind': 'setFanTimer', 'on': false},
        reason: 'turning it off carries no length',
      );
    });
  });
}
