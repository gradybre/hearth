import 'package:hearth/domain/house/thermostat.dart';
import 'package:test/test.dart';

ThermostatState aThermostat({
  String label = 'Hallway',
  double ambientC = 21,
  double? humidityPercent = 44,
  ThermostatMode mode = ThermostatMode.heat,
  Set<ThermostatMode>? availableModes,
  HvacStatus hvac = HvacStatus.off,
  double? heatC = 20,
  double? coolC,
  EcoMode eco = EcoMode.off,
  FanState? fan,
}) => ThermostatState(
  label: label,
  ambientC: ambientC,
  humidityPercent: humidityPercent,
  mode: mode,
  availableModes:
      availableModes ??
      <ThermostatMode>{
        ThermostatMode.off,
        ThermostatMode.heat,
        ThermostatMode.cool,
        ThermostatMode.heatCool,
      },
  hvac: hvac,
  heatC: heatC,
  coolC: coolC,
  eco: eco,
  fan: fan,
);

void main() {
  group('reading what the API says', () {
    test('every mode the API names has a value here', () {
      expect(ThermostatMode.fromSdm('HEAT'), ThermostatMode.heat);
      expect(ThermostatMode.fromSdm('HEATCOOL'), ThermostatMode.heatCool);
      expect(HvacStatus.fromSdm('COOLING'), HvacStatus.cooling);
      expect(EcoMode.fromSdm('MANUAL_ECO'), EcoMode.manualEco);
      expect(EcoMode.manualEco.isOn, isTrue);
      expect(EcoMode.off.isOn, isFalse);
    });

    test('and a word nobody has seen before is unknown, not a crash', () {
      // A firmware update that adds a mode should cost one greyed-out button.
      // Throwing here would blank the whole screen instead.
      expect(ThermostatMode.fromSdm('DEHUMIDIFY'), ThermostatMode.unknown);
      expect(ThermostatMode.fromSdm(null), ThermostatMode.unknown);
      expect(HvacStatus.fromSdm('DEFROSTING'), HvacStatus.unknown);
      expect(EcoMode.fromSdm(''), EcoMode.unknown);
    });
  });

  group('Celsius in, Fahrenheit out', () {
    test('the two scales meet where they should', () {
      expect(Temp.cToF(0), 32);
      expect(Temp.cToF(100), 212);
      expect(Temp.fToC(32), 0);
      expect(Temp.fToC(-40), closeTo(-40, 0.0001));
    });

    test('a whole degree Fahrenheit survives the round trip', () {
      // The API is Celsius only and the screen is Fahrenheit, so every press
      // makes that round trip. 72 sends 22.222…, comes back 22.22, and has to
      // still read 72 — otherwise the number drifts by a degree every few
      // presses and the dial slowly disagrees with the thermostat.
      for (int f = 50; f <= 90; f++) {
        expect(
          Temp.displayF(Temp.fToC(f.toDouble())),
          f,
          reason: '$f°F did not survive the trip through Celsius',
        );
      }
    });

    test('a press moves the number on screen by exactly one', () {
      final double from = Temp.fToC(70);
      expect(Temp.displayF(Temp.stepF(from, 1)), 71);
      expect(Temp.displayF(Temp.stepF(from, -1)), 69);
    });

    test('and stops at the ends rather than running past them', () {
      expect(Temp.stepF(ThermostatLimits.maxC, 1), ThermostatLimits.maxC);
      expect(Temp.stepF(ThermostatLimits.minC, -1), ThermostatLimits.minC);
      expect(Temp.isWithinRange(ThermostatLimits.minC), isTrue);
      expect(Temp.isWithinRange(ThermostatLimits.minC - 0.1), isFalse);
      expect(Temp.isWithinRange(ThermostatLimits.maxC + 0.1), isFalse);
    });
  });

  group('what the thermostat will not do (before anybody asks it)', () {
    // Every one of these is a 400 from the API if it goes out. Catching them
    // here is what lets the screen grey a control out instead of moving the
    // dial and putting it back.

    test('Eco holds the temperature, and says so', () {
      final ThermostatState eco = aThermostat(eco: EcoMode.manualEco);

      expect(eco.setpointsAreYours, isFalse);
      expect(
        eco.refuse(SetHeat(Temp.fToC(70))),
        'Eco is holding the temperature. Turn Eco off to change it.',
      );
      expect(
        eco.refuse(SetCool(Temp.fToC(76))),
        'Eco is holding the temperature. Turn Eco off to change it.',
      );
    });

    test('but turning Eco back off is always allowed', () {
      // It is the way out. Refusing it would be a room nobody can leave.
      final ThermostatState eco = aThermostat(eco: EcoMode.manualEco);
      expect(eco.refuse(const SetEco(on: false)), isNull);
    });

    test('a thermostat that is off has no target to change', () {
      final ThermostatState off = aThermostat(
        mode: ThermostatMode.off,
        heatC: null,
      );
      expect(off.setpointsAreYours, isFalse);
      expect(off.refuse(SetHeat(Temp.fToC(70))), 'The thermostat is off.');
    });

    test('a cool target in Heat is refused, and the message says which', () {
      final ThermostatState heating = aThermostat(mode: ThermostatMode.heat);
      expect(
        heating.refuse(SetCool(Temp.fToC(76))),
        'The thermostat is set to Heat, so there is no cool target to change.',
      );
      expect(heating.refuse(SetHeat(Temp.fToC(70))), isNull);
    });

    test('and a range needs the mode that has two targets', () {
      final ThermostatState heating = aThermostat(mode: ThermostatMode.heat);
      expect(
        heating.refuse(SetRange(heatC: Temp.fToC(68), coolC: Temp.fToC(76))),
        'A range needs Heat · Cool.',
      );
    });

    test('Heat · Cool takes a range, and only a range', () {
      // The API splits these three commands by mode: SetHeat is for HEAT,
      // SetCool for COOL, SetRange for HEATCOOL. Sending SetHeat while the
      // thermostat is in Heat · Cool is a 400, which is exactly the kind of
      // thing this class exists to catch before it costs a call.
      final ThermostatState both = aThermostat(
        mode: ThermostatMode.heatCool,
        heatC: Temp.fToC(68),
        coolC: Temp.fToC(76),
      );

      expect(
        both.refuse(SetHeat(Temp.fToC(70))),
        'The thermostat is set to Heat · Cool, which takes both targets '
        'at once.',
      );
      expect(
        both.refuse(SetCool(Temp.fToC(74))),
        'The thermostat is set to Heat · Cool, which takes both targets '
        'at once.',
      );
      expect(
        both.refuse(SetRange(heatC: Temp.fToC(70), coolC: Temp.fToC(74))),
        isNull,
      );
    });

    test('and Heat takes a heat target, not a range', () {
      final ThermostatState heating = aThermostat(mode: ThermostatMode.heat);
      expect(heating.refuse(SetHeat(Temp.fToC(70))), isNull);
      expect(
        heating.refuse(SetRange(heatC: Temp.fToC(68), coolC: Temp.fToC(76))),
        'A range needs Heat · Cool.',
      );
    });

    test('a range narrower than the deadband would make the system fight '
        'itself', () {
      final ThermostatState both = aThermostat(
        mode: ThermostatMode.heatCool,
        heatC: Temp.fToC(68),
        coolC: Temp.fToC(76),
      );

      expect(
        both.refuse(SetRange(heatC: Temp.fToC(70), coolC: Temp.fToC(73))),
        isNull,
        reason: 'three degrees apart is the minimum, and is allowed',
      );
      expect(
        both.refuse(SetRange(heatC: Temp.fToC(70), coolC: Temp.fToC(72))),
        contains('at least 3° apart'),
      );
      expect(
        both.refuse(SetRange(heatC: Temp.fToC(76), coolC: Temp.fToC(68))),
        contains('at least 3° apart'),
        reason: 'inverted is the same fault, further along',
      );
    });

    test('a target outside the thermostat\'s own range is refused in the '
        'units the screen speaks', () {
      final ThermostatState heating = aThermostat();
      final String? refusal = heating.refuse(const SetHeat(40));
      expect(refusal, contains('48°'));
      expect(refusal, contains('90°'));
    });

    test('a mode this system does not have is not offered', () {
      // A heat-only system. Offering Cool would be offering an error.
      final ThermostatState heatOnly = aThermostat(
        availableModes: <ThermostatMode>{
          ThermostatMode.off,
          ThermostatMode.heat,
        },
      );
      expect(
        heatOnly.refuse(const SetMode(ThermostatMode.cool)),
        'Hallway does not offer Cool.',
      );
      expect(heatOnly.refuse(const SetMode(ThermostatMode.heat)), isNull);
      expect(
        heatOnly.refuse(const SetMode(ThermostatMode.unknown)),
        'That is not a mode this thermostat has.',
      );
    });

    test('a fan the thermostat does not have cannot be run', () {
      // No fan wire means no Fan trait at all, which is a different thing
      // from a fan that is off.
      final ThermostatState noFan = aThermostat();
      expect(noFan.hasFan, isFalse);
      expect(
        noFan.refuse(
          const SetFanTimer(on: true, duration: Duration(minutes: 15)),
        ),
        'Hallway has no fan to run.',
      );

      final ThermostatState withFan = aThermostat(
        fan: const FanState(isOn: false),
      );
      expect(withFan.hasFan, isTrue);
      expect(
        withFan.refuse(
          const SetFanTimer(on: true, duration: Duration(minutes: 15)),
        ),
        isNull,
      );
    });

    test('and it runs for somewhere between a second and twelve hours', () {
      final ThermostatState withFan = aThermostat(
        fan: const FanState(isOn: false),
      );
      expect(
        withFan.refuse(const SetFanTimer(on: true)),
        'A fan timer needs a length.',
      );
      expect(
        withFan.refuse(
          const SetFanTimer(on: true, duration: Duration(hours: 13)),
        ),
        contains('up to 12 hours'),
      );
      expect(
        withFan.refuse(
          const SetFanTimer(on: true, duration: Duration(hours: 12)),
        ),
        isNull,
      );
      expect(
        withFan.refuse(const SetFanTimer(on: false)),
        isNull,
        reason: 'turning it off needs no length',
      );
    });

    test('the ordinary case goes through', () {
      final ThermostatState ok = aThermostat();
      expect(ok.setpointsAreYours, isTrue);
      expect(ok.refuse(SetHeat(Temp.fToC(71))), isNull);
    });
  });

  group('a press of minus or plus becomes the right command', () {
    // The screen knows "warmer"; it should not also have to know that warmer
    // means SetHeat in Heat, SetRange in Heat · Cool, and nothing at all when
    // Eco is holding the temperature. That is three API rules leaking into a
    // button.

    test('in Heat it moves the heat target', () {
      final ThermostatState heating = aThermostat(
        mode: ThermostatMode.heat,
        heatC: Temp.fToC(68),
      );
      final ThermostatCommand? up = heating.warmer(1);
      expect(up, isA<SetHeat>());
      expect(Temp.displayF((up! as SetHeat).heatC), 69);
    });

    test('in Cool it moves the cool target', () {
      final ThermostatState cooling = aThermostat(
        mode: ThermostatMode.cool,
        heatC: null,
        coolC: Temp.fToC(76),
      );
      final ThermostatCommand? down = cooling.cooler(1);
      expect(down, isA<SetCool>());
      expect(Temp.displayF((down! as SetCool).coolC), 75);
    });

    test('in Heat · Cool it sends both, moving the one asked for', () {
      final ThermostatState both = aThermostat(
        mode: ThermostatMode.heatCool,
        heatC: Temp.fToC(68),
        coolC: Temp.fToC(76),
      );
      final SetRange up = both.warmer(1, heat: true)! as SetRange;
      expect(Temp.displayF(up.heatC), 69);
      expect(Temp.displayF(up.coolC), 76);

      final SetRange down = both.cooler(1, heat: false)! as SetRange;
      expect(Temp.displayF(down.heatC), 68);
      expect(Temp.displayF(down.coolC), 75);
    });

    test('and pushes the other target rather than jamming at the deadband', () {
      // A control that stops moving three degrees early reads as broken. The
      // Nest's own dial pushes, so this does too.
      final ThermostatState both = aThermostat(
        mode: ThermostatMode.heatCool,
        heatC: Temp.fToC(71),
        coolC: Temp.fToC(74),
      );

      final SetRange pushed = both.warmer(1, heat: true)! as SetRange;
      expect(Temp.displayF(pushed.heatC), 72);
      expect(
        Temp.displayF(pushed.coolC),
        75,
        reason: 'cool was pushed up to keep three degrees between them',
      );
      expect(both.refuse(pushed), isNull, reason: 'and it is a legal range');
    });

    test('and refuses to move at all when the thermostat would refuse', () {
      expect(aThermostat(eco: EcoMode.manualEco).warmer(1), isNull);
      expect(aThermostat(mode: ThermostatMode.off).warmer(1), isNull);
    });

    test('and stops at the top rather than sending something out of range', () {
      final ThermostatState hot = aThermostat(
        mode: ThermostatMode.heat,
        heatC: ThermostatLimits.maxC,
      );
      expect(hot.warmer(1), isNull, reason: 'there is nowhere further to go');
    });
  });

  group('showing a press before the thermostat has agreed to it', () {
    test('one setpoint moves and nothing else does', () {
      final ThermostatState before = aThermostat(
        mode: ThermostatMode.heatCool,
        heatC: Temp.fToC(68),
        coolC: Temp.fToC(76),
      );
      final ThermostatState after = before.withSetpoints(heatC: Temp.fToC(70));

      expect(Temp.displayF(after.heatC!), 70);
      expect(Temp.displayF(after.coolC!), 76);
      expect(after.ambientC, before.ambientC);
      expect(after.mode, before.mode);
      expect(after.eco, before.eco);
      expect(after.label, before.label);
    });

    test('and the old value is recoverable, because nothing was mutated', () {
      // Which is what puts the number back when the command is refused.
      final ThermostatState before = aThermostat(heatC: Temp.fToC(68));
      before.withSetpoints(heatC: Temp.fToC(75));
      expect(Temp.displayF(before.heatC!), 68);
    });
  });

  group('two readings of the same thermostat are the same value', () {
    test('so a rebuild with identical state is not a change', () {
      expect(aThermostat(), aThermostat());
      expect(aThermostat().hashCode, aThermostat().hashCode);
    });

    test('and a different reading is not', () {
      expect(aThermostat(ambientC: 21), isNot(aThermostat(ambientC: 22)));
      expect(
        aThermostat(),
        isNot(
          aThermostat(availableModes: <ThermostatMode>{ThermostatMode.heat}),
        ),
      );
      expect(
        aThermostat(fan: const FanState(isOn: true)),
        isNot(aThermostat(fan: const FanState(isOn: false))),
      );
    });
  });
}
