import { assertEquals } from 'jsr:@std/assert@1';
import { commandBody, snapshotOf, thermostatsIn } from './sdm.ts';

/// Google's shape into Hearth's, and Hearth's commands into Google's.
///
/// The fixtures below are hand-built from the trait reference rather than
/// captured from a device, and that is the honest limit of these tests: they
/// prove the translation is what this file believes Google sends, not that
/// Google sends it. Only linking a real thermostat settles the second half.

function device(traits: Record<string, unknown>): unknown {
  return {
    name: 'enterprises/p-1/devices/d-1',
    type: 'sdm.devices.types.THERMOSTAT',
    traits: {
      'sdm.devices.traits.Info': { customName: 'Hallway' },
      ...traits,
    },
  };
}

const heating = device({
  'sdm.devices.traits.Temperature': { ambientTemperatureCelsius: 21.4 },
  'sdm.devices.traits.Humidity': { ambientHumidityPercent: 43 },
  'sdm.devices.traits.ThermostatMode': {
    mode: 'HEAT',
    availableModes: ['OFF', 'HEAT', 'COOL', 'HEATCOOL'],
  },
  'sdm.devices.traits.ThermostatHvac': { status: 'HEATING' },
  'sdm.devices.traits.ThermostatEco': { mode: 'OFF' },
  'sdm.devices.traits.ThermostatTemperatureSetpoint': { heatCelsius: 20 },
});

Deno.test('a thermostat reads as a snapshot', () => {
  const snapshot = snapshotOf(heating)!;
  assertEquals(snapshot.label, 'Hallway');
  assertEquals(snapshot.ambientC, 21.4);
  assertEquals(snapshot.humidityPercent, 43);
  assertEquals(snapshot.mode, 'HEAT');
  assertEquals(snapshot.hvac, 'HEATING');
  assertEquals(snapshot.heatC, 20);
  assertEquals(snapshot.coolC, null);
  assertEquals(snapshot.eco, 'OFF');
});

Deno.test('a device with no fan wire reports no fan at all', () => {
  // Absent, not false. The screen draws nothing rather than a control that
  // could only ever fail.
  assertEquals('fan' in snapshotOf(heating)!, false);

  const withFan = snapshotOf(device({
    ...(heating as { traits: Record<string, unknown> }).traits,
    'sdm.devices.traits.Fan': {
      timerMode: 'ON',
      timerTimeout: '2026-09-13T15:40:00Z',
    },
  }))!;
  assertEquals(withFan.fan, {
    on: true,
    until: '2026-09-13T15:40:00Z',
  });
});

Deno.test('a model with no humidity sensor reports none', () => {
  const traits = {
    ...(heating as { traits: Record<string, unknown> }).traits,
  };
  delete traits['sdm.devices.traits.Humidity'];
  assertEquals(snapshotOf(device(traits))!.humidityPercent, null);
});

Deno.test('a heat-only system offers only the modes it has', () => {
  const snapshot = snapshotOf(device({
    ...(heating as { traits: Record<string, unknown> }).traits,
    'sdm.devices.traits.ThermostatMode': {
      mode: 'HEAT',
      availableModes: ['OFF', 'HEAT'],
    },
  }))!;
  assertEquals(snapshot.availableModes, ['OFF', 'HEAT']);
});

Deno.test('a device that did not say how warm it is reads as nothing', () => {
  // Null rather than a snapshot of zeros: 0° on screen would be a lie, where
  // a gap is only a gap.
  assertEquals(snapshotOf(device({})), null);
  assertEquals(snapshotOf(null), null);
  assertEquals(snapshotOf({ traits: 'nonsense' }), null);
});

Deno.test('the label falls back to the room, then to a plain word', () => {
  assertEquals(
    snapshotOf({
      name: 'enterprises/p-1/devices/d-1',
      parentRelations: [{ displayName: 'Landing' }],
      traits: {
        'sdm.devices.traits.Temperature': { ambientTemperatureCelsius: 19 },
      },
    })!.label,
    'Landing',
  );
  assertEquals(
    snapshotOf({
      traits: {
        'sdm.devices.traits.Temperature': { ambientTemperatureCelsius: 19 },
      },
    })!.label,
    'Thermostat',
  );
});

Deno.test('a camera in the same list is not a thermostat', () => {
  const list = thermostatsIn({
    devices: [
      { name: 'enterprises/p-1/devices/cam', type: 'sdm.devices.types.CAMERA' },
      heating,
    ],
  });
  assertEquals(list.length, 1);
  assertEquals(list[0].name, 'enterprises/p-1/devices/d-1');
  assertEquals(list[0].label, 'Hallway');
});

Deno.test('an empty or unreadable device list is empty, not an error', () => {
  assertEquals(thermostatsIn({}), []);
  assertEquals(thermostatsIn(null), []);
  assertEquals(thermostatsIn({ devices: 'nope' }), []);
});

Deno.test('each command becomes the body Google expects', () => {
  const prefix = 'sdm.devices.commands';

  assertEquals(commandBody({ kind: 'setHeat', heatC: 20 }), {
    command: `${prefix}.ThermostatTemperatureSetpoint.SetHeat`,
    params: { heatCelsius: 20 },
  });
  assertEquals(commandBody({ kind: 'setCool', coolC: 24 }), {
    command: `${prefix}.ThermostatTemperatureSetpoint.SetCool`,
    params: { coolCelsius: 24 },
  });
  assertEquals(commandBody({ kind: 'setRange', heatC: 20, coolC: 24 }), {
    command: `${prefix}.ThermostatTemperatureSetpoint.SetRange`,
    params: { heatCelsius: 20, coolCelsius: 24 },
  });
  assertEquals(commandBody({ kind: 'setMode', mode: 'HEATCOOL' }), {
    command: `${prefix}.ThermostatMode.SetMode`,
    params: { mode: 'HEATCOOL' },
  });
  assertEquals(commandBody({ kind: 'setEco', on: true }), {
    command: `${prefix}.ThermostatEco.SetMode`,
    params: { mode: 'MANUAL_ECO' },
  });
  assertEquals(commandBody({ kind: 'setEco', on: false }), {
    command: `${prefix}.ThermostatEco.SetMode`,
    params: { mode: 'OFF' },
  });
});

Deno.test('a range carries both numbers, never one', () => {
  // SetRange is the only setpoint command HEATCOOL accepts, and half a range
  // is not a range. Sending one would move the other setpoint to nothing.
  assertEquals(commandBody({ kind: 'setRange', heatC: 20 }), null);
  assertEquals(commandBody({ kind: 'setRange', coolC: 24 }), null);
});

Deno.test('the fan timer goes out in the duration shape Google insists on', () => {
  assertEquals(
    commandBody({ kind: 'setFanTimer', on: true, duration: '900s' }),
    {
      command: 'sdm.devices.commands.Fan.SetTimer',
      params: { timerMode: 'ON', duration: '900s' },
    },
  );
  assertEquals(commandBody({ kind: 'setFanTimer', on: false }), {
    command: 'sdm.devices.commands.Fan.SetTimer',
    params: { timerMode: 'OFF' },
  });
});

Deno.test('and a fan timer outside what the trait allows is refused here', () => {
  // Refused rather than forwarded: a 400 from Google costs a call against a
  // five-a-minute ceiling and tells the user nothing.
  assertEquals(commandBody({ kind: 'setFanTimer', on: true }), null);
  assertEquals(
    commandBody({ kind: 'setFanTimer', on: true, duration: '900' }),
    null,
  );
  assertEquals(
    commandBody({ kind: 'setFanTimer', on: true, duration: '43201s' }),
    null,
  );
  assertEquals(
    commandBody({ kind: 'setFanTimer', on: true, duration: '0s' }),
    null,
  );
});

Deno.test('anything this build does not recognise is refused, not guessed', () => {
  assertEquals(commandBody({ kind: 'setMode', mode: 'DEHUMIDIFY' }), null);
  assertEquals(commandBody({ kind: 'launchRocket' }), null);
  assertEquals(commandBody({ kind: 'setHeat' }), null);
  assertEquals(commandBody({ kind: 'setHeat', heatC: 'warm' }), null);
  assertEquals(commandBody(null), null);
});
