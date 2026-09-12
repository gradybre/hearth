// Google's Smart Device Management vocabulary, kept on this side of the wire.
//
// Every function here is pure: traits in, Hearth's shape out; a Hearth command
// in, Google's body out. That is the whole point of them being a file of their
// own — the translation is the part with rules in it, and a pure function is
// the part that can be tested without a thermostat, a network, or a household.
//
// It is also why the app never sees an SDM trait name. A rename at Google is a
// redeploy of this file rather than an App Store release, which is the same
// argument `usda-lookup` makes about FDC's response shape.

export const SDM = 'https://smartdevicemanagement.googleapis.com/v1';

const THERMOSTAT = 'sdm.devices.types.THERMOSTAT';

/// What one thermostat says it is, in the shape the app reads.
export interface Snapshot {
  label: string;
  ambientC: number;
  humidityPercent: number | null;
  mode: string;
  availableModes: string[];
  hvac: string;
  heatC: number | null;
  coolC: number | null;
  eco: string;
  /// Absent — not false — when the device reports no Fan trait at all. A
  /// thermostat with no fan wire is a different thing from a fan that is off,
  /// and the screen draws nothing rather than a control that could only fail.
  fan?: { on: boolean; until: string | null };
}

/// The thermostats in a `devices.list` response.
///
/// Filtered by type rather than by trait: a household with a Nest camera gets
/// the camera back in the same list, and a doorbell has no setpoint to read.
export function thermostatsIn(body: unknown): Array<{
  name: string;
  label: string;
}> {
  const devices = asArray(asRecord(body)?.devices);
  const out: Array<{ name: string; label: string }> = [];
  for (const device of devices) {
    const record = asRecord(device);
    if (!record || record.type !== THERMOSTAT) continue;
    const name = asString(record.name);
    if (!name) continue;
    out.push({ name, label: labelOf(record) });
  }
  return out;
}

/// One device's traits as a [Snapshot], or null if it is unreadable.
///
/// Null rather than a throw, and null rather than a snapshot full of zeros: a
/// thermostat that did not say how warm it is has told us nothing worth
/// drawing, and a screen reading 0° would be a lie rather than a gap.
export function snapshotOf(device: unknown): Snapshot | null {
  const record = asRecord(device);
  const traits = asRecord(record?.traits);
  if (!traits) return null;

  const ambient = asNumber(
    asRecord(traits['sdm.devices.traits.Temperature'])
      ?.ambientTemperatureCelsius,
  );
  if (ambient === null) return null;

  const modeTrait = asRecord(traits['sdm.devices.traits.ThermostatMode']);
  const ecoTrait = asRecord(traits['sdm.devices.traits.ThermostatEco']);
  const setpoint = asRecord(
    traits['sdm.devices.traits.ThermostatTemperatureSetpoint'],
  );
  const fanTrait = asRecord(traits['sdm.devices.traits.Fan']);

  return {
    label: labelOf(record ?? {}),
    ambientC: ambient,
    humidityPercent: asNumber(
      asRecord(traits['sdm.devices.traits.Humidity'])?.ambientHumidityPercent,
    ),
    mode: asString(modeTrait?.mode) ?? '',
    availableModes: asArray(modeTrait?.availableModes)
      .map((m) => asString(m))
      .filter((m): m is string => m !== null),
    hvac: asString(
      asRecord(traits['sdm.devices.traits.ThermostatHvac'])?.status,
    ) ?? '',
    // Absent in the modes that have no such target: a thermostat in HEAT
    // reports no cool setpoint, and inventing one would put a number on screen
    // that nothing is holding to.
    heatC: asNumber(setpoint?.heatCelsius),
    coolC: asNumber(setpoint?.coolCelsius),
    eco: asString(ecoTrait?.mode) ?? 'OFF',
    ...(fanTrait
      ? {
        fan: {
          on: asString(fanTrait.timerMode) === 'ON',
          until: asString(fanTrait.timerTimeout),
        },
      }
      : {}),
  };
}

/// One of Hearth's commands as the body `executeCommand` expects.
///
/// Returns null for anything this build does not recognise, which the caller
/// answers as a 400 rather than forwarding a guess to Google.
export function commandBody(
  command: unknown,
): { command: string; params: Record<string, unknown> } | null {
  const c = asRecord(command);
  if (!c) return null;

  const prefix = 'sdm.devices.commands';
  switch (c.kind) {
    case 'setHeat': {
      const heatC = asNumber(c.heatC);
      if (heatC === null) return null;
      return {
        command: `${prefix}.ThermostatTemperatureSetpoint.SetHeat`,
        params: { heatCelsius: heatC },
      };
    }
    case 'setCool': {
      const coolC = asNumber(c.coolC);
      if (coolC === null) return null;
      return {
        command: `${prefix}.ThermostatTemperatureSetpoint.SetCool`,
        params: { coolCelsius: coolC },
      };
    }
    case 'setRange': {
      // Both numbers, always. SetRange is the only setpoint command HEATCOOL
      // accepts, and it does not take one half of a range.
      const heatC = asNumber(c.heatC);
      const coolC = asNumber(c.coolC);
      if (heatC === null || coolC === null) return null;
      return {
        command: `${prefix}.ThermostatTemperatureSetpoint.SetRange`,
        params: { heatCelsius: heatC, coolCelsius: coolC },
      };
    }
    case 'setMode': {
      const mode = asString(c.mode);
      if (!mode || !['OFF', 'HEAT', 'COOL', 'HEATCOOL'].includes(mode)) {
        return null;
      }
      return {
        command: `${prefix}.ThermostatMode.SetMode`,
        params: { mode },
      };
    }
    case 'setEco': {
      // Eco has its own SetMode on its own trait, and only two values.
      return {
        command: `${prefix}.ThermostatEco.SetMode`,
        params: { mode: c.on === true ? 'MANUAL_ECO' : 'OFF' },
      };
    }
    case 'setFanTimer': {
      const on = c.on === true;
      if (!on) {
        return {
          command: `${prefix}.Fan.SetTimer`,
          params: { timerMode: 'OFF' },
        };
      }
      // Google wants a duration string — "900s" — not a number of seconds.
      const duration = asString(c.duration);
      if (!duration || !/^[0-9]+s$/.test(duration)) return null;
      const seconds = Number(duration.slice(0, -1));
      if (seconds < 1 || seconds > 43200) return null;
      return {
        command: `${prefix}.Fan.SetTimer`,
        params: { timerMode: 'ON', duration },
      };
    }
    default:
      return null;
  }
}

/// What the Nest app calls the device, falling back to something sayable.
function labelOf(device: Record<string, unknown>): string {
  const traits = asRecord(device.traits);
  const custom = asString(
    asRecord(traits?.['sdm.devices.traits.Info'])?.customName,
  );
  if (custom) return custom;

  // No custom name, so Google offers the room it is assigned to instead.
  const parents = asArray(device.parentRelations);
  for (const parent of parents) {
    const name = asString(asRecord(parent)?.displayName);
    if (name) return name;
  }
  return 'Thermostat';
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}
