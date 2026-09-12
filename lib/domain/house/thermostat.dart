/// What a thermostat is, and what it will refuse (spec §11).
///
/// Pure Dart, like the rest of `lib/domain/` — no Flutter, no network, no
/// Google. Everything here is about the physics and the rules, so the rules
/// can be tested without a house on the other end of them.
///
/// The Smart Device Management API is stricter than it looks: a setpoint is
/// rejected while Eco is on, rejected while the mode is off, and rejected
/// unless the mode is the one that setpoint belongs to. A phone that discovers
/// those rules from a 400 has already moved the dial on screen and has to move
/// it back. So they live here, in front of the request, and the screen greys
/// out what the thermostat would not have accepted anyway.
library;

import 'package:meta/meta.dart';

/// How the thermostat is being asked to run.
///
/// `unknown` rather than an exception on an unrecognised string: a firmware
/// update that adds a mode should cost one greyed-out button, not a blank
/// screen. The same reasoning applies to [HvacStatus] and [EcoMode].
enum ThermostatMode {
  off('OFF', 'Off'),
  heat('HEAT', 'Heat'),
  cool('COOL', 'Cool'),
  heatCool('HEATCOOL', 'Heat · Cool'),
  unknown('', 'Unknown');

  const ThermostatMode(this.sdm, this.label);

  /// The value the API uses.
  final String sdm;

  /// What the screen calls it.
  final String label;

  static ThermostatMode fromSdm(String? value) => values.firstWhere(
    (ThermostatMode m) => m.sdm == value && m != unknown,
    orElse: () => unknown,
  );
}

/// What the system is doing right now, which is not the same as what it was
/// asked to do — a thermostat set to Heat is usually not heating.
enum HvacStatus {
  off('OFF', 'Idle'),
  heating('HEATING', 'Heating'),
  cooling('COOLING', 'Cooling'),
  unknown('', 'Unknown');

  const HvacStatus(this.sdm, this.label);

  final String sdm;
  final String label;

  static HvacStatus fromSdm(String? value) => values.firstWhere(
    (HvacStatus s) => s.sdm == value && s != unknown,
    orElse: () => unknown,
  );
}

/// Eco is a mode of its own, running to setpoints the API will not let anyone
/// change. It can be turned on and off and nothing else.
enum EcoMode {
  off('OFF'),
  manualEco('MANUAL_ECO'),
  unknown('');

  const EcoMode(this.sdm);

  final String sdm;

  bool get isOn => this == manualEco;

  static EcoMode fromSdm(String? value) => values.firstWhere(
    (EcoMode e) => e.sdm == value && e != unknown,
    orElse: () => unknown,
  );
}

/// The fan, on a thermostat wired for one.
///
/// A null [ThermostatState.fan] means the device does not report the trait at
/// all — no fan wire — which is a different thing from a fan that is off. The
/// screen draws nothing rather than a control that could only ever fail.
@immutable
class FanState {
  const FanState({required this.isOn, this.until});

  final bool isOn;

  /// When the timer runs out. Null while the fan is off.
  final DateTime? until;

  @override
  bool operator ==(Object other) =>
      other is FanState && other.isOn == isOn && other.until == until;

  @override
  int get hashCode => Object.hash(isOn, until);
}

/// The limits, in the units the API and the person each use.
abstract final class ThermostatLimits {
  /// Nest's own range. A request outside it is refused rather than clamped
  /// silently — a dial that stops moving says more than one that lies.
  static const double minC = 9;
  static const double maxC = 32;

  /// Heat and cool cannot be closer than this in HEATCOOL, or the system
  /// would fight itself. Nest's own dial enforces three degrees Fahrenheit.
  static const double minRangeF = 3;

  /// The fan timer's range, from the Fan trait.
  static const Duration minFan = Duration(seconds: 1);
  static const Duration maxFan = Duration(hours: 12);
}

/// Celsius in, Fahrenheit out.
///
/// The API speaks Celsius only, whatever the thermostat displays, so Celsius
/// is what is stored and sent. Brendan reads Fahrenheit, so the screen steps
/// in whole degrees Fahrenheit and converts back on the way out. Rounding to
/// the nearest whole degree on the way in makes that round trip stable: 72 °F
/// sends 22.222…, comes back as 22.22, and reads 72 again.
abstract final class Temp {
  static double cToF(double c) => c * 9 / 5 + 32;

  static double fToC(double f) => (f - 32) * 5 / 9;

  /// What the screen shows.
  static int displayF(double c) => cToF(c).round();

  /// One press of − or +, in Celsius, clamped to what the device accepts.
  ///
  /// Stepping in Fahrenheit rather than by a Celsius increment, because the
  /// number moving on screen is the Fahrenheit one and a step that sometimes
  /// fails to change it reads as a broken button.
  static double stepF(double c, int degrees) =>
      clampC(fToC((displayF(c) + degrees).toDouble()));

  static double clampC(double c) =>
      c.clamp(ThermostatLimits.minC, ThermostatLimits.maxC).toDouble();

  static bool isWithinRange(double c) =>
      c >= ThermostatLimits.minC && c <= ThermostatLimits.maxC;
}

/// Something to ask the thermostat to do.
///
/// Sealed, so [ThermostatState.refuse] has to have an answer for each one and
/// adding a seventh command is a compile error everywhere it matters rather
/// than a silent gap in the rules.
@immutable
sealed class ThermostatCommand {
  const ThermostatCommand();
}

final class SetHeat extends ThermostatCommand {
  const SetHeat(this.heatC);

  final double heatC;
}

final class SetCool extends ThermostatCommand {
  const SetCool(this.coolC);

  final double coolC;
}

final class SetRange extends ThermostatCommand {
  const SetRange({required this.heatC, required this.coolC});

  final double heatC;
  final double coolC;
}

final class SetMode extends ThermostatCommand {
  const SetMode(this.mode);

  final ThermostatMode mode;
}

final class SetEco extends ThermostatCommand {
  const SetEco({required this.on});

  final bool on;
}

final class SetFanTimer extends ThermostatCommand {
  const SetFanTimer({required this.on, this.duration});

  final bool on;

  /// How long to run. Ignored when turning the fan off.
  final Duration? duration;
}

/// What the thermostat says it is, right now.
///
/// Every nullable field is nullable because *the device may not report it*,
/// not because it might be missing from a response. A thermostat with no fan
/// wire has no Fan trait; a model with no humidity sensor reports no humidity.
/// The screen draws what is here and nothing else, so it is a picture of this
/// thermostat rather than of the API.
@immutable
class ThermostatState {
  const ThermostatState({
    required this.label,
    required this.ambientC,
    required this.mode,
    required this.availableModes,
    required this.hvac,
    required this.eco,
    this.humidityPercent,
    this.heatC,
    this.coolC,
    this.fan,
  });

  /// What the Nest app calls it — "Hallway", usually. Shown so a house with
  /// two thermostats one day does not have two identical screens.
  final String label;

  final double ambientC;

  /// Null on a model with no humidity sensor.
  final double? humidityPercent;

  final ThermostatMode mode;

  /// The modes this device offers. A heat-only system has no COOL, and
  /// offering it would be offering a button that returns an error.
  final Set<ThermostatMode> availableModes;

  final HvacStatus hvac;

  /// The target while heating. Null in COOL and OFF.
  final double? heatC;

  /// The target while cooling. Null in HEAT and OFF.
  final double? coolC;

  final EcoMode eco;

  /// Null when the device reports no fan at all.
  final FanState? fan;

  bool get hasFan => fan != null;

  /// Whether the temperature is currently anybody's to set.
  ///
  /// Eco owns the setpoints while it is on, and the API rejects every attempt
  /// to change them; a thermostat that is off has no target to change.
  bool get setpointsAreYours => !eco.isOn && mode != ThermostatMode.off;

  /// Why this command would be refused, or null if it would go through.
  ///
  /// A sentence rather than an error code, because it is shown to a person:
  /// every one of these is a reason a control is greyed out or a press did
  /// nothing, and "Eco is on" is the whole explanation somebody needs.
  String? refuse(ThermostatCommand command) {
    switch (command) {
      case SetHeat(:final double heatC):
        return _refuseSetpoint(heatC, <ThermostatMode>{
          ThermostatMode.heat,
        }, 'heat');
      case SetCool(:final double coolC):
        return _refuseSetpoint(coolC, <ThermostatMode>{
          ThermostatMode.cool,
        }, 'cool');
      case SetRange(:final double heatC, :final double coolC):
        final String? one =
            _refuseSetpoint(heatC, <ThermostatMode>{
              ThermostatMode.heatCool,
            }, 'range') ??
            _refuseSetpoint(coolC, <ThermostatMode>{
              ThermostatMode.heatCool,
            }, 'range');
        if (one != null) return one;
        if (Temp.cToF(coolC) - Temp.cToF(heatC) < ThermostatLimits.minRangeF) {
          return 'Heat and cool have to be at least '
              '${ThermostatLimits.minRangeF.round()}° apart.';
        }
        return null;
      case SetMode(:final ThermostatMode mode):
        if (mode == ThermostatMode.unknown) {
          return 'That is not a mode this thermostat has.';
        }
        if (!availableModes.contains(mode)) {
          return '$label does not offer ${mode.label}.';
        }
        return null;
      case SetEco():
        // The one control Eco does not lock, by definition — it is the way
        // back out of it.
        return null;
      case SetFanTimer(:final bool on, :final Duration? duration):
        if (!hasFan) return '$label has no fan to run.';
        if (!on) return null;
        if (duration == null) return 'A fan timer needs a length.';
        if (duration < ThermostatLimits.minFan ||
            duration > ThermostatLimits.maxFan) {
          return 'The fan can run for up to '
              '${ThermostatLimits.maxFan.inHours} hours.';
        }
        return null;
    }
  }

  /// The rules every setpoint shares, in the order a person would meet them.
  String? _refuseSetpoint(double c, Set<ThermostatMode> modes, String which) {
    if (eco.isOn) {
      return 'Eco is holding the temperature. Turn Eco off to change it.';
    }
    if (mode == ThermostatMode.off) {
      return 'The thermostat is off.';
    }
    if (!modes.contains(mode)) {
      if (which == 'range') return 'A range needs Heat · Cool.';
      // The API splits the three setpoint commands by mode, and Heat · Cool
      // is the one that takes both numbers at once. A SetHeat sent there is
      // a 400, so it is refused here instead — one fewer call spent against
      // a five-a-minute ceiling, and a sentence instead of an error.
      if (mode == ThermostatMode.heatCool) {
        return 'The thermostat is set to Heat · Cool, which takes both '
            'targets at once.';
      }
      return 'The thermostat is set to ${mode.label}, '
          'so there is no $which target to change.';
    }
    if (!Temp.isWithinRange(c)) {
      return 'That is outside what the thermostat accepts — '
          '${Temp.displayF(ThermostatLimits.minC)}° to '
          '${Temp.displayF(ThermostatLimits.maxC)}°.';
    }
    return null;
  }

  /// One press of +, as the command this thermostat would accept.
  ///
  /// The screen knows "warmer"; it should not also have to know that warmer
  /// means [SetHeat] in Heat, [SetRange] in Heat · Cool, and nothing at all
  /// while Eco is holding the temperature. That is three API rules leaking
  /// into a button.
  ///
  /// Null when there is nothing legal to send — Eco, off, or already at the
  /// end of the range. A null is what greys the button out.
  ///
  /// [heat] picks which of the two targets moves, and is meaningless outside
  /// Heat · Cool, where there is only one.
  ThermostatCommand? warmer(int degrees, {bool heat = true}) =>
      _nudge(degrees, heat: heat);

  /// One press of −. See [warmer].
  ThermostatCommand? cooler(int degrees, {bool heat = true}) =>
      _nudge(-degrees, heat: heat);

  ThermostatCommand? _nudge(int degrees, {required bool heat}) {
    if (!setpointsAreYours) return null;

    switch (mode) {
      case ThermostatMode.heat:
        final double? moved = _moved(heatC, degrees);
        return moved == null ? null : SetHeat(moved);
      case ThermostatMode.cool:
        final double? moved = _moved(coolC, degrees);
        return moved == null ? null : SetCool(moved);
      case ThermostatMode.heatCool:
        final double? from = heat ? heatC : coolC;
        final double? other = heat ? coolC : heatC;
        final double? moved = _moved(from, degrees);
        if (moved == null || other == null) return null;
        // Pushed, not jammed. A control that stops three degrees early
        // reads as broken, and the Nest's own dial pushes the other handle
        // along — so the deadband is kept by moving the pair.
        return heat
            ? SetRange(heatC: moved, coolC: _atLeastAbove(moved, other))
            : SetRange(heatC: _atLeastBelow(moved, other), coolC: moved);
      case ThermostatMode.off:
      case ThermostatMode.unknown:
        return null;
    }
  }

  /// The setpoint one press away, or null if the press would change nothing —
  /// which is what the ends of the range look like from here.
  static double? _moved(double? from, int degrees) {
    if (from == null) return null;
    final double next = Temp.stepF(from, degrees);
    return next == from ? null : next;
  }

  /// [other], pushed up if [moved] has come too close beneath it.
  static double _atLeastAbove(double moved, double other) {
    final double floor = Temp.fToC(
      Temp.displayF(moved) + ThermostatLimits.minRangeF,
    );
    return other >= floor ? other : Temp.clampC(floor);
  }

  /// [other], pushed down if [moved] has come too close above it.
  static double _atLeastBelow(double moved, double other) {
    final double ceiling = Temp.fToC(
      Temp.displayF(moved) - ThermostatLimits.minRangeF,
    );
    return other <= ceiling ? other : Temp.clampC(ceiling);
  }

  /// The same state with whatever was just asked for folded in.
  ///
  /// Not only the setpoints: a mode, Eco and the fan all have controls that
  /// show their own value, and a switch that springs back the instant it is
  /// flipped reads as broken — it then sits wrong until the next reading, up
  /// to a minute later. Optimism with a short shelf life, like
  /// [withSetpoints]: the thermostat's own account replaces this.
  ThermostatState copyWith({
    ThermostatMode? mode,
    HvacStatus? hvac,
    EcoMode? eco,
    FanState? fan,
    double? heatC,
    double? coolC,
  }) => ThermostatState(
    label: label,
    ambientC: ambientC,
    humidityPercent: humidityPercent,
    mode: mode ?? this.mode,
    availableModes: availableModes,
    hvac: hvac ?? this.hvac,
    heatC: heatC ?? this.heatC,
    coolC: coolC ?? this.coolC,
    eco: eco ?? this.eco,
    // Never conjured: a thermostat with no fan trait has no fan, and a fan
    // control appearing because somebody pressed something would be the
    // screen inventing hardware.
    fan: this.fan == null ? null : (fan ?? this.fan),
  );

  /// The same state with one setpoint moved, for showing a press immediately
  /// while the command is in flight.
  ///
  /// Optimism with a short shelf life: whatever the device reports back
  /// replaces this, and a refusal puts the old number straight back. The
  /// screen never holds a number the thermostat has not agreed to for longer
  /// than one round trip.
  ThermostatState withSetpoints({double? heatC, double? coolC}) =>
      ThermostatState(
        label: label,
        ambientC: ambientC,
        humidityPercent: humidityPercent,
        mode: mode,
        availableModes: availableModes,
        hvac: hvac,
        heatC: heatC ?? this.heatC,
        coolC: coolC ?? this.coolC,
        eco: eco,
        fan: fan,
      );

  @override
  bool operator ==(Object other) =>
      other is ThermostatState &&
      other.label == label &&
      other.ambientC == ambientC &&
      other.humidityPercent == humidityPercent &&
      other.mode == mode &&
      other.hvac == hvac &&
      other.heatC == heatC &&
      other.coolC == coolC &&
      other.eco == eco &&
      other.fan == fan &&
      _sameModes(other.availableModes);

  bool _sameModes(Set<ThermostatMode> other) =>
      other.length == availableModes.length &&
      other.every(availableModes.contains);

  @override
  int get hashCode => Object.hash(
    label,
    ambientC,
    humidityPercent,
    mode,
    hvac,
    heatC,
    coolC,
    eco,
    fan,
    Object.hashAllUnordered(availableModes),
  );
}
