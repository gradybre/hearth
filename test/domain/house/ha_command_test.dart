import 'package:hearth/domain/house/entity_id.dart';
import 'package:hearth/domain/house/entity_state.dart';
import 'package:hearth/domain/house/ha_command.dart';
import 'package:hearth/domain/house/light_capability.dart';
import 'package:test/test.dart';

/// Commands: what may be sent, and what may be claimed afterwards
/// (`docs/HOME_ASSISTANT_SPEC.md` §6.2).
///
/// The two failures worth most of this file are the ones that look fine in a
/// demo: a command that reaches something other than the thing that was
/// tapped, and an app that says "done" when nothing happened.
void main() {
  final EntityId plugId = EntityId.tryParse('switch.kettle')!;
  final EntityId bulbId = EntityId.tryParse('light.kitchen')!;
  final EntityId doorId = EntityId.tryParse('binary_sensor.front_door')!;

  const LightCapability onOffBulb = LightCapability.onOffOnly;
  const LightCapability dimmableBulb = LightCapability(
    modes: <LightColorMode>{LightColorMode.brightness},
  );
  const LightCapability tunableWhiteBulb = LightCapability(
    modes: <LightColorMode>{LightColorMode.colorTemp},
    minMireds: 153,
    maxMireds: 500,
  );
  const LightCapability colourBulb = LightCapability(
    modes: <LightColorMode>{LightColorMode.hs, LightColorMode.colorTemp},
    minMireds: 153,
    maxMireds: 500,
  );

  CommandTarget plug({
    Availability availability = Availability.known,
    bool permitted = true,
  }) => CommandTarget(
    id: plugId,
    availability: availability,
    permitted: permitted,
  );

  CommandTarget bulb(LightCapability capability) =>
      CommandTarget(id: bulbId, light: capability);

  DateTime at(int second) => DateTime.utc(2026, 9, 16, 19, 0, second);

  EntityState reading(
    String raw, {
    Map<String, Object?> attributes = const <String, Object?>{},
    DateTime? updatedAt,
  }) => EntityState(
    availability: Availability.known,
    freshness: Freshness.live,
    raw: raw,
    attributes: attributes,
    lastUpdated: updatedAt,
  );

  /// The state of something Hearth has never heard from, which is what the
  /// lane is holding the first time anybody presses anything.
  const EntityState nothingKnown = EntityState.neverRead();

  HaCommand built(PreparedCommand prepared) {
    final HaCommand? command = prepared.commandOrNull;
    expect(command, isNotNull, reason: prepared.refusal);
    return command!;
  }

  group('a command reaches one thing and nothing else', () {
    test('the payload names exactly the entity that was tapped', () {
      final HaServiceCall call = built(plug().power(on: true)).call;

      expect(call.payload['entity_id'], 'switch.kettle');
      expect(
        call.payload['entity_id'],
        isA<String>(),
        reason:
            'a list of one is the same request today and an invitation '
            'to append to it tomorrow',
      );
      expect(call.payload.keys, <String>['entity_id']);
    });

    test('and never an area, a device, a label, or "all"', () {
      // The empty target: one tap turning off every light in the house.
      final List<HaServiceCall> calls = <HaServiceCall>[
        built(plug().power(on: false)).call,
        built(bulb(colourBulb).power(on: true)).call,
        built(bulb(colourBulb).brightness(60)).call,
        built(bulb(colourBulb).colorTemperature(300)).call,
        built(bulb(colourBulb).color(hue: 30, saturation: 80)).call,
      ];

      for (final HaServiceCall call in calls) {
        expect(call.payload.containsKey('area_id'), isFalse);
        expect(call.payload.containsKey('device_id'), isFalse);
        expect(call.payload.containsKey('label_id'), isFalse);
        expect(call.payload.containsKey('target'), isFalse);
        expect(call.payload['entity_id'], isNot('all'));
        expect(call.payload['entity_id'], call.target.value);
      }
    });

    test('and there is no id for a bare domain to be built from', () {
      // `switch.` is every switch in the house. It never parses, so no target
      // and therefore no command can be made from it — the guard is upstream
      // of this file and this is the line that depends on it.
      expect(EntityId.tryParse('switch.'), isNull);
    });

    test('by calling the service, never by writing the state', () {
      // Writing `/api/states` makes the card change and leaves the kettle
      // cold: it records Hearth's belief instead of touching the hardware.
      final HaServiceCall call = built(plug().power(on: true)).call;

      expect(call.domain, 'switch');
      expect(call.service, 'turn_on');
      expect(built(plug().power(on: false)).call.service, 'turn_off');
    });

    test('through the service its own domain answers to', () {
      // `switch.front_door_light` is a switch somebody named after a light,
      // and `light.turn_on` would not reach it.
      expect(built(plug().power(on: true)).call.domain, 'switch');
      expect(built(bulb(onOffBulb).power(on: true)).call.domain, 'light');
    });

    test('and a light takes its brightness and colour on turn_on', () {
      expect(
        built(bulb(dimmableBulb).brightness(40)).call.payload,
        <String, Object?>{'entity_id': 'light.kitchen', 'brightness_pct': 40},
      );
      expect(
        built(bulb(tunableWhiteBulb).colorTemperature(370)).call.payload,
        <String, Object?>{'entity_id': 'light.kitchen', 'color_temp': 370},
      );
      expect(
        built(bulb(colourBulb).color(hue: 210, saturation: 55)).call.payload,
        <String, Object?>{
          'entity_id': 'light.kitchen',
          'hs_color': <double>[210, 55],
        },
      );
    });
  });

  group('a command the device cannot carry out cannot be built', () {
    test('no brightness for a bulb that only turns on and off', () {
      final PreparedCommand prepared = bulb(onOffBulb).brightness(50);

      expect(prepared.commandOrNull, isNull);
      expect(prepared.refusal, 'This bulb only turns on and off.');
    });

    test('no colour for a tunable-white bulb', () {
      // color_temp and hs are separate claims; the modes are not a ladder.
      final PreparedCommand prepared = bulb(tunableWhiteBulb)
          .color(hue: 30, saturation: 80);

      expect(prepared.commandOrNull, isNull);
      expect(prepared.refusal, 'This bulb is white only.');
    });

    test('no white adjustment for a bulb that only dims', () {
      expect(bulb(dimmableBulb).colorTemperature(300).refusal, isNotNull);
    });

    test('and a dimmable bulb still dims when it is asked properly', () {
      expect(bulb(dimmableBulb).brightness(1).commandOrNull, isNotNull);
      expect(bulb(dimmableBulb).brightness(100).commandOrNull, isNotNull);
    });

    test('nothing but on and off for a plug', () {
      expect(
        plug().brightness(50).refusal,
        'Hearth can only do that to a light.',
      );
      expect(plug().power(on: true).commandOrNull, isNotNull);
    });

    test('and nothing at all for something that is only a reading', () {
      final CommandTarget door = CommandTarget(id: doorId);

      expect(
        door.power(on: true).refusal,
        'Hearth cannot switch a binary_sensor.',
      );
    });

    test('nothing outside the range the bulb published', () {
      expect(bulb(tunableWhiteBulb).colorTemperature(152).refusal, isNotNull);
      expect(bulb(tunableWhiteBulb).colorTemperature(501).refusal, isNotNull);
      expect(bulb(tunableWhiteBulb).colorTemperature(153).refusal, isNull);
      expect(bulb(tunableWhiteBulb).colorTemperature(500).refusal, isNull);
    });

    test('and no brightness of zero, which is a way of spelling off', () {
      expect(bulb(dimmableBulb).brightness(0).refusal, isNotNull);
      expect(bulb(dimmableBulb).brightness(101).refusal, isNotNull);
    });

    test('and no hue or saturation off the wheel', () {
      expect(
        bulb(colourBulb).color(hue: -1, saturation: 50).refusal,
        isNotNull,
      );
      expect(
        bulb(colourBulb).color(hue: 361, saturation: 50).refusal,
        isNotNull,
      );
      expect(
        bulb(colourBulb).color(hue: 10, saturation: 101).refusal,
        isNotNull,
      );
    });

    test('nothing for a device Home Assistant cannot reach', () {
      final PreparedCommand prepared = plug(
        availability: Availability.unavailable,
      ).power(on: true);

      expect(prepared.commandOrNull, isNull);
      expect(prepared.refusal, 'Hearth cannot reach this device right now.');
    });

    test('but a device that has simply not said anything yet is fair game', () {
      // Unknown is not unavailable: a bulb whose state has never arrived can
      // still be switched on.
      expect(
        plug(availability: Availability.unknown).power(on: true).commandOrNull,
        isNotNull,
      );
    });

    test('and nothing this account is not allowed to touch', () {
      expect(plug(permitted: false).power(on: true).refusal, isNotNull);
    });
  });

  group('pending intent is a layer of its own', () {
    test('the intention stands from the moment it is asked for', () {
      final CommandLane lane = const CommandLane.idle().request(
        built(bulb(dimmableBulb).brightness(80)),
        now: at(0),
        observed: reading(
          'on',
          attributes: <String, Object?>{'brightness': 51},
          updatedAt: at(-1),
        ),
      );

      expect(lane.isBusy, isTrue);
      expect(lane.liveIntent?.intendedBrightnessPercent, 80);
    });

    test('and a state event from before the tap cannot take it away', () {
      // The subtle one. The event says 20%, and it is true — it was true
      // before the finger moved. Letting it resolve the command would put the
      // slider back under the user's thumb.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(80)),
            now: at(10),
            observed: reading(
              'on',
              attributes: <String, Object?>{'brightness': 51},
              updatedAt: at(9),
            ),
          )
          .markSent(at(10))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 51},
              updatedAt: at(9),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.inFlight);
      expect(lane.liveIntent?.intendedBrightnessPercent, 80);
    });

    test('and a stale event that happens to match cannot confirm it', () {
      // The one that costs somebody a lie. The bulb was at 80% this morning;
      // somebody turned it down to 20%; the tap asks for 80% again. An event
      // generated before the tap — reporting the old 80% — arrives after it.
      // Read as confirmation, the app says "Done" for a command nothing has
      // acted on yet, and the tick is indistinguishable from a real one.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(80)),
            now: at(10),
            observed: reading(
              'on',
              attributes: <String, Object?>{'brightness': 51},
              updatedAt: at(9),
            ),
          )
          .markSent(at(10))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 204},
              updatedAt: at(5),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.inFlight);
      expect(lane.intent!.phase.isSuccess, isFalse);
      expect(lane.liveIntent?.intendedBrightnessPercent, 80);
    });

    test('though the same reading, dated after the tap, does confirm it', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(80)),
            now: at(10),
            observed: reading(
              'on',
              attributes: <String, Object?>{'brightness': 51},
              updatedAt: at(9),
            ),
          )
          .markSent(at(10))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 204},
              updatedAt: at(11),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.confirmed);
    });

    test('and neither can one that simply disagrees', () {
      // A mismatch is not evidence of failure — the event may have been in
      // flight already. Only the deadline ends a command.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(80)),
            now: at(10),
            observed: nothingKnown,
          )
          .markSent(at(10))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 10},
              updatedAt: at(11),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.inFlight);
      expect(lane.intent!.phase.isSuccess, isFalse);
    });

    test('and an event with no clock on it cannot confirm anything', () {
      // Arrival time would make a late event look current, which is the whole
      // confusion this guards against.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(10),
            observed: reading('off', updatedAt: at(9)),
          )
          .markSent(at(10))
          .observe(reading('on'));

      expect(lane.intent!.phase, CommandPhase.inFlight);
    });

    test('and the newest intention is the one on screen', () {
      // While 40% is still out on the wire the finger has moved to 70%. The
      // slider belongs to the person, so it shows what they last asked for,
      // not what the app is still busy with.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(40)),
            now: at(0),
            observed: nothingKnown,
          )
          .markSent(at(0))
          .request(
            built(bulb(dimmableBulb).brightness(70)),
            now: at(1),
            observed: nothingKnown,
          );

      expect(lane.liveIntent?.intendedBrightnessPercent, 70);
      expect(lane.intent!.sequence, 2);
    });

    test('an answer to a superseded command resolves nothing', () {
      // An old socket, or an answer overtaken by a newer request. Matching it
      // to the current intent would confirm something nobody asked for.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .markAccepted(sequence: 99);

      expect(lane.intent!.phase, CommandPhase.inFlight);
      expect(lane.intent!.sequence, 1);
    });
  });

  group('slider updates are thinned out and taken one at a time', () {
    test('a tap goes at once', () {
      final CommandLane lane = const CommandLane.idle().request(
        built(plug().power(on: true)),
        now: at(0),
        observed: reading('off', updatedAt: at(0)),
      );

      expect(lane.dueAt(at(0)), isNotNull);
    });

    test('a slider waits out its window', () {
      final CommandLane lane = const CommandLane.idle().request(
        built(bulb(dimmableBulb).brightness(40)),
        now: at(0),
        observed: nothingKnown,
      );

      expect(lane.dueAt(at(0)), isNull);
      expect(lane.dueAt(at(0).add(HaCommandPolicy.sliderDebounce)), isNotNull);
    });

    test('and only the value the finger stopped on is ever sent', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(40)),
            now: at(0),
            observed: nothingKnown,
          )
          .request(
            built(bulb(dimmableBulb).brightness(55)),
            now: at(0),
            observed: nothingKnown,
          )
          .request(
            built(bulb(dimmableBulb).brightness(70)),
            now: at(0),
            observed: nothingKnown,
          );

      final PendingIntent? due = lane.dueAt(
        at(0).add(HaCommandPolicy.sliderDebounce),
      );
      expect(due!.command.intendedBrightnessPercent, 70);
      expect(
        due.sequence,
        3,
        reason: 'the two the finger passed through were never intentions',
      );
    });

    test('and nothing else goes while one is still out', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(40)),
            now: at(0),
            observed: nothingKnown,
          )
          .markSent(at(1))
          .request(
            built(bulb(dimmableBulb).brightness(70)),
            now: at(1),
            observed: nothingKnown,
          );

      // Two overlapping turn_on calls land in whatever order the mesh decides.
      expect(lane.dueAt(at(5)), isNull);

      final CommandLane after = lane.markFailed(
        sequence: 1,
        reason: 'Home Assistant said no.',
      );
      expect(after.dueAt(at(5))!.command.intendedBrightnessPercent, 70);
    });
  });

  group('acceptance is not proof', () {
    CommandLane sentPlugOn() => const CommandLane.idle()
        .request(
          built(plug().power(on: true)),
          now: at(0),
          observed: reading('off', updatedAt: at(0)),
        )
        .markSent(at(0));

    test('Home Assistant taking the call is not the kettle switching on', () {
      final CommandLane lane = sentPlugOn().markAccepted(sequence: 1);

      expect(lane.intent!.phase, CommandPhase.accepted);
      expect(
        lane.intent!.phase.isSuccess,
        isFalse,
        reason: 'the radio message to the plug can still go nowhere',
      );
      expect(lane.intent!.label, 'Working…');
      expect(lane.isBusy, isTrue);
    });

    test('the device saying so is', () {
      final CommandLane lane = sentPlugOn()
          .markAccepted(sequence: 1)
          .observe(reading('on', updatedAt: at(1)));

      expect(lane.intent!.phase, CommandPhase.confirmed);
      expect(lane.intent!.phase.isSuccess, isTrue);
      expect(lane.intent!.label, 'Done');
      expect(lane.isBusy, isFalse);
    });

    test('and silence past the deadline is "Could not confirm"', () {
      final CommandLane lane = sentPlugOn().markAccepted(sequence: 1);

      expect(
        lane
            .tick(at(0).add(HaCommandPolicy.confirmationDeadline - _tick))
            .intent!
            .phase,
        CommandPhase.accepted,
      );

      final CommandLane expired = lane.tick(
        at(0).add(HaCommandPolicy.confirmationDeadline),
      );
      expect(expired.intent!.phase, CommandPhase.unconfirmed);
      expect(expired.intent!.phase.isSuccess, isFalse);
      expect(expired.intent!.label, 'Could not confirm');
    });

    test('a refusal says so plainly', () {
      final CommandLane lane = sentPlugOn().markFailed(
        sequence: 1,
        reason: 'Home Assistant refused that.',
      );

      expect(lane.intent!.phase, CommandPhase.failed);
      expect(lane.intent!.phase.isSuccess, isFalse);
      expect(lane.intent!.label, 'Home Assistant refused that.');
    });

    test('and the deadline runs from the send, not from the tap', () {
      // A command held behind another one has not had its chance yet.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(10))
          .tick(at(12));

      expect(lane.intent!.phase, CommandPhase.inFlight);
    });

    test('a brightness confirmation allows for a bulb that rounds', () {
      // 60% of 255 is 153, and the bulb reporting 152 is obeying.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(60)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 152},
              updatedAt: at(1),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.confirmed);
    });

    test('but not for a bulb that landed somewhere else entirely', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(60)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{'brightness': 20},
              updatedAt: at(1),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.inFlight);
    });

    test('and a colour confirmation knows hue is a circle', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(colourBulb).color(hue: 359, saturation: 80)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .observe(
            reading(
              'on',
              attributes: <String, Object?>{
                'hs_color': <double>[1, 80],
              },
              updatedAt: at(1),
            ),
          );

      expect(lane.intent!.phase, CommandPhase.confirmed);
    });
  });

  group('a command that changes nothing does not wait for a change', () {
    test('switching on something already on finishes on acceptance', () {
      // No state event is coming, because nothing is going to change. Waiting
      // would spin to the deadline and then disown a plug that is doing
      // exactly what was asked.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('on', updatedAt: at(0)),
          )
          .markSent(at(0))
          .markAccepted(sequence: 1);

      expect(lane.intent!.phase, CommandPhase.confirmed);
      expect(lane.tick(at(60)).intent!.phase, CommandPhase.confirmed);
    });

    test(
      'and that shortcut is not available to a command that does change',
      () {
        final CommandLane lane = const CommandLane.idle()
            .request(
              built(plug().power(on: true)),
              now: at(0),
              observed: reading('off', updatedAt: at(0)),
            )
            .markSent(at(0))
            .markAccepted(sequence: 1);

        expect(lane.intent!.phase, CommandPhase.accepted);
      },
    );

    test('and an unread device is never assumed to match', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: nothingKnown,
          )
          .markSent(at(0))
          .markAccepted(sequence: 1);

      expect(lane.intent!.phase, CommandPhase.accepted);
    });
  });

  group('nothing is ever replayed', () {
    test('a waiting command does not survive the connection', () {
      // It was never sent, and there is no path that could send it later.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(bulb(dimmableBulb).brightness(70)),
            now: at(0),
            observed: nothingKnown,
          )
          .connectionLost();

      expect(lane.waiting, isNull);
      expect(lane.dueAt(at(0)), isNull);
      expect(
        lane.dueAt(at(3600)),
        isNull,
        reason: 'no amount of waiting turns a dropped intention into a send',
      );
    });

    test('and one in flight ends honestly rather than being retried', () {
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .connectionLost();

      expect(lane.intent!.phase, CommandPhase.unconfirmed);
      expect(lane.intent!.label, 'Could not confirm');
      expect(lane.dueAt(at(3600)), isNull);
    });

    test('a finished command cannot be brought back to life', () {
      // An answer that turns up after the deadline — the ambiguous timeout.
      // Accepting it would be a replay with extra steps.
      final CommandLane expired = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .tick(at(0).add(HaCommandPolicy.confirmationDeadline));

      expect(expired.intent!.phase, CommandPhase.unconfirmed);
      expect(
        expired.markAccepted(sequence: 1).intent!.phase,
        CommandPhase.unconfirmed,
      );
      expect(
        expired.observe(reading('on', updatedAt: at(30))).intent!.phase,
        CommandPhase.unconfirmed,
        reason: 'a late event is news about the house, not a resurrection',
      );
    });

    test('and the numbering never starts again', () {
      // A repeated sequence is how an answer to a dead command resolves a
      // live one.
      final CommandLane lane = const CommandLane.idle()
          .request(
            built(plug().power(on: true)),
            now: at(0),
            observed: reading('off', updatedAt: at(0)),
          )
          .markSent(at(0))
          .connectionLost()
          .cleared();

      expect(lane.intent, isNull);

      final CommandLane next = lane.request(
        built(plug().power(on: true)),
        now: at(30),
        observed: reading('off', updatedAt: at(29)),
      );
      expect(next.intent!.sequence, 2);
    });

    test('and a session that starts again has nothing to send', () {
      // §6.2 forbids device commands in the sync outbox, and the guarantee is
      // structural: there is no public constructor and no serialisation for a
      // PendingIntent, so the only way to obtain one is for somebody to ask
      // for it now. A restarted session therefore begins here, with nothing
      // to resend and no way to build something to resend.
      const CommandLane afterRestart = CommandLane.idle();

      expect(afterRestart.intent, isNull);
      expect(afterRestart.dueAt(at(0)), isNull);
      expect(afterRestart.markSent(at(0)).sent, isNull);
      expect(afterRestart.markAccepted(sequence: 1).intent, isNull);
    });
  });
}

/// One millisecond before the deadline, to prove the boundary is where it says.
const Duration _tick = Duration(milliseconds: 1);
