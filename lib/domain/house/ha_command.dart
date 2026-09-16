/// What Hearth may ask a device to do, and what it may claim afterwards
/// (`docs/HOME_ASSISTANT_SPEC.md` §6.2).
///
/// Pure Dart, like the rest of `lib/domain/` — no Flutter, no sockets, no
/// Home Assistant client. This layer decides and describes; something else
/// sends. Everything here can therefore be tested without a Raspberry Pi on
/// the other end of it.
///
/// Two failures shape the whole file, because both of them look fine in a
/// demo and only hurt somebody later.
///
/// **A command that reaches the wrong thing.** A service call with no
/// `entity_id`, or with an `area_id`, or with `entity_id: all`, turns off every
/// light in the house from a tap on one card. So a command cannot exist
/// without exactly one [EntityId], the payload is assembled in here rather
/// than at the call site, and the only thing this file describes is a *service
/// call*. Writing `/api/states` would also make the card change — it writes
/// Hearth's belief about the state into Home Assistant without touching the
/// hardware, which is the same lie with better manners.
///
/// **An app that says "done" when nothing happened.** Home Assistant accepting
/// a service call means it took the request; the message to the bulb can still
/// go nowhere. So acceptance is a phase of its own, confirmation comes from an
/// observed state event, and a deadline that passes with no event ends at
/// "Could not confirm". A tick nobody has earned teaches somebody to trust a
/// control that does not work, which is worse than admitting the doubt.
library;

import 'package:meta/meta.dart';

import 'entity_id.dart';
import 'entity_state.dart';
import 'light_capability.dart';

/// The timings and limits the rules below are written against.
abstract final class HaCommandPolicy {
  /// How long a slider's newest value waits before it is sent.
  ///
  /// A dragged slider produces dozens of values a second and every one of them
  /// would be a service call to a radio with a much smaller budget. Only the
  /// last one is an intention; the rest are the finger moving.
  static const Duration sliderDebounce = Duration(milliseconds: 250);

  /// How long a sent command has to show up in the device's own state before
  /// Hearth stops claiming anything.
  ///
  /// Long enough for a mains plug and a mesh hop, short enough that nobody
  /// stands there watching a spinner deciding the app is broken.
  static const Duration confirmationDeadline = Duration(seconds: 5);

  /// Brightness is asked for in percent, which is what the slider shows.
  ///
  /// Zero is not the bottom of the range: `brightness_pct: 0` is a way of
  /// spelling "off", and an off command should say so rather than arrive
  /// disguised as a dim one.
  static const int minBrightnessPercent = 1;
  static const int maxBrightnessPercent = 100;

  /// Home Assistant reports `brightness` on 0–255 while the command is sent in
  /// percent, so a round trip never lands exactly. A bulb that rounds is still
  /// obeying, and three steps of 255 are well under one step of the slider.
  static const int brightnessMatchTolerance = 3;

  /// Mireds and degrees both come back rounded by the bulb's own firmware.
  static const int colorTempMatchTolerance = 2;
  static const double colorMatchTolerance = 2;
}

/// One service call, with its target already fixed.
///
/// [payload] is built here and nowhere else. The transport gets a map that
/// already names one entity and has no seam for an area, a device, a list, or
/// the `all` that Home Assistant still honours.
@immutable
final class HaServiceCall {
  const HaServiceCall({
    required this.domain,
    required this.service,
    required this.target,
    this.data = const <String, Object?>{},
  });

  /// The service domain — `switch` or `light`.
  final String domain;

  /// `turn_on` or `turn_off`. For a light, `turn_on` also carries brightness
  /// and colour: Home Assistant has no separate service for them.
  final String service;

  /// The one entity this acts on.
  final EntityId target;

  /// Everything except the target.
  final Map<String, Object?> data;

  /// What goes on the wire.
  ///
  /// `entity_id` is a single string on purpose. A list of one is the same
  /// request today and an invitation to append to it tomorrow.
  Map<String, Object?> get payload => <String, Object?>{
    'entity_id': target.value,
    ...data,
  };

  @override
  bool operator ==(Object other) =>
      other is HaServiceCall &&
      other.domain == domain &&
      other.service == service &&
      other.target == target &&
      _sameData(other.data);

  bool _sameData(Map<String, Object?> other) =>
      other.length == data.length &&
      data.entries.every(
        (MapEntry<String, Object?> e) =>
            other.containsKey(e.key) && _sameValue(other[e.key], e.value),
      );

  static bool _sameValue(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  @override
  int get hashCode => Object.hash(domain, service, target, data.length);

  @override
  String toString() => '$domain.$service $payload';
}

/// Something to ask one device to do.
///
/// Sealed, so every place that handles commands has to have an answer for each
/// one, and a sixth command is a compile error rather than a silent gap.
///
/// The constructors are private: the only way to obtain one is
/// [CommandTarget], which will not build a command the device cannot carry
/// out. A brightness command for an on/off bulb is not a request that gets
/// refused later — it is a value that cannot be spoken.
@immutable
sealed class HaCommand {
  const HaCommand._(this.target);

  /// The one entity this acts on. There is no constructor without it and no
  /// setter for it, so a command can never be widened after it is built.
  final EntityId target;

  /// The call that would carry this out.
  HaServiceCall get call;

  /// Whether the device, as last observed, already looks like this.
  ///
  /// The point of asking is §6.2's rule that a command already matching the
  /// observed state must not wait for a change event: nothing is going to
  /// change, so no event is coming, and a spinner would run to the deadline
  /// and then disown a bulb that is doing exactly what was asked.
  bool isSatisfiedBy(EntityState observed);

  /// Whether rapid repeats of this should be held back and thinned out.
  ///
  /// True for the three continuous controls, false for a tap. A tap is one
  /// intention and delaying it a quarter of a second reads as lag; a drag is
  /// hundreds of intermediate values nobody meant.
  bool get isCoalescable => false;

  /// The percentage this sets, for a slider that has to render an intention
  /// before it is confirmed. Null for every other command.
  int? get intendedBrightnessPercent => null;
}

/// A plug or an ordinary switch, on or off.
final class SwitchPower extends HaCommand {
  const SwitchPower._(super.target, {required this.on}) : super._();

  final bool on;

  @override
  HaServiceCall get call => HaServiceCall(
    domain: 'switch',
    service: on ? 'turn_on' : 'turn_off',
    target: target,
  );

  @override
  bool isSatisfiedBy(EntityState observed) => observed.value == _word(on);
}

/// A bulb, on or off.
final class LightPower extends HaCommand {
  const LightPower._(super.target, {required this.on}) : super._();

  final bool on;

  @override
  HaServiceCall get call => HaServiceCall(
    domain: 'light',
    service: on ? 'turn_on' : 'turn_off',
    target: target,
  );

  @override
  bool isSatisfiedBy(EntityState observed) => observed.value == _word(on);
}

/// How bright, in percent.
final class SetBrightness extends HaCommand {
  const SetBrightness._(super.target, this.percent) : super._();

  final int percent;

  @override
  HaServiceCall get call => HaServiceCall(
    domain: 'light',
    service: 'turn_on',
    target: target,
    data: <String, Object?>{'brightness_pct': percent},
  );

  @override
  bool get isCoalescable => true;

  @override
  int? get intendedBrightnessPercent => percent;

  @override
  bool isSatisfiedBy(EntityState observed) {
    if (observed.value != 'on') return false;
    final num? reported = _asNum(observed.attributes['brightness']);
    if (reported == null) return false;
    final int wanted = (percent * 255 / 100).round();
    return (reported - wanted).abs() <=
        HaCommandPolicy.brightnessMatchTolerance;
  }
}

/// Warm to cool white, in mireds — the same unit as
/// [LightCapability.minMireds], so a slider's ends and its value never need
/// converting between two scales on the way to the bulb.
final class SetColorTemperature extends HaCommand {
  const SetColorTemperature._(super.target, this.mireds) : super._();

  final int mireds;

  @override
  HaServiceCall get call => HaServiceCall(
    domain: 'light',
    service: 'turn_on',
    target: target,
    data: <String, Object?>{'color_temp': mireds},
  );

  @override
  bool get isCoalescable => true;

  @override
  bool isSatisfiedBy(EntityState observed) {
    if (observed.value != 'on') return false;
    final num? reported = _asNum(observed.attributes['color_temp']);
    if (reported == null) return false;
    return (reported - mireds).abs() <= HaCommandPolicy.colorTempMatchTolerance;
  }
}

/// A colour, as hue and saturation.
final class SetColor extends HaCommand {
  const SetColor._(super.target, {required this.hue, required this.saturation})
    : super._();

  /// Degrees around the wheel, 0–360.
  final double hue;

  /// Percent, 0–100.
  final double saturation;

  @override
  HaServiceCall get call => HaServiceCall(
    domain: 'light',
    service: 'turn_on',
    target: target,
    data: <String, Object?>{
      'hs_color': <double>[hue, saturation],
    },
  );

  @override
  bool get isCoalescable => true;

  @override
  bool isSatisfiedBy(EntityState observed) {
    if (observed.value != 'on') return false;
    final Object? reported = observed.attributes['hs_color'];
    if (reported is! List || reported.length != 2) return false;
    final num? h = _asNum(reported[0]);
    final num? s = _asNum(reported[1]);
    if (h == null || s == null) return false;
    // Hue is a circle: 359° and 1° are two degrees apart, not 358.
    final double apart = (h - hue).abs() % 360;
    final double hueGap = apart > 180 ? 360 - apart : apart;
    return hueGap <= HaCommandPolicy.colorMatchTolerance &&
        (s - saturation).abs() <= HaCommandPolicy.colorMatchTolerance;
  }
}

String _word(bool on) => on ? 'on' : 'off';

num? _asNum(Object? value) => value is num ? value : null;

/// A command that was built, or the sentence explaining why it was not.
///
/// Both halves are needed by the same screen: the command is what a tap sends,
/// and the reason is what a greyed-out control says when somebody presses it
/// anyway. A control that does nothing is indistinguishable from an app that
/// is broken.
@immutable
sealed class PreparedCommand {
  const PreparedCommand();

  /// The command, or null when this is a refusal.
  HaCommand? get commandOrNull;

  /// Why not, or null when there is a command.
  String? get refusal;
}

final class CommandReady extends PreparedCommand {
  const CommandReady(this.command);

  final HaCommand command;

  @override
  HaCommand? get commandOrNull => command;

  @override
  String? get refusal => null;
}

final class CommandRefused extends PreparedCommand {
  const CommandRefused(this.reason);

  /// A sentence, not an error code: it is shown to a person.
  final String reason;

  @override
  HaCommand? get commandOrNull => null;

  @override
  String? get refusal => reason;
}

/// One entity Hearth may command, and everything that decides which commands
/// are legal for it.
///
/// This is the only mint for [HaCommand], and it is built from what the device
/// *currently* claims — its domain, its `supported_color_modes`, whether Home
/// Assistant can reach it, and whether this account is allowed to act on it.
/// So a command in flight is always one that was legal when it was made, and
/// the greying-out on screen and the validation before the call cannot drift
/// apart: they are the same method.
@immutable
final class CommandTarget {
  const CommandTarget({
    required this.id,
    this.light,
    this.availability = Availability.known,
    this.permitted = true,
  });

  final EntityId id;

  /// What this bulb can do. Null when the entity is not a light — and a light
  /// whose attributes have not arrived is [LightCapability.onOffOnly], which
  /// is a claim about the bulb rather than an absence.
  final LightCapability? light;

  /// Whether Home Assistant can currently reach the thing. A control on an
  /// unreachable device can only fail, and §9 requires that a stale control
  /// cannot enqueue an operation.
  final Availability availability;

  /// Whether this account is allowed to act on this entity. §9 requires a
  /// permission denial on one entity to cost that entity and nothing else.
  final bool permitted;

  /// On or off, by whichever service this entity's domain answers to.
  ///
  /// The domain decides, never the name: `switch.front_door_light` is a switch
  /// somebody named after a light, and `light.turn_on` would not reach it.
  PreparedCommand power({required bool on}) {
    final String? blocked = _blocked();
    if (blocked != null) return CommandRefused(blocked);

    return switch (id.domain) {
      HaDomain.switch_ => CommandReady(SwitchPower._(id, on: on)),
      HaDomain.light => CommandReady(LightPower._(id, on: on)),
      _ => CommandRefused('Hearth cannot switch a ${id.domainName}.'),
    };
  }

  /// How bright, in percent.
  PreparedCommand brightness(int percent) {
    final String? blocked = _blockedLight(
      (LightCapability c) => c.canDim,
      'This bulb only turns on and off.',
    );
    if (blocked != null) return CommandRefused(blocked);

    if (percent < HaCommandPolicy.minBrightnessPercent ||
        percent > HaCommandPolicy.maxBrightnessPercent) {
      return const CommandRefused(
        'Brightness goes from ${HaCommandPolicy.minBrightnessPercent}% to '
        '${HaCommandPolicy.maxBrightnessPercent}%.',
      );
    }
    return CommandReady(SetBrightness._(id, percent));
  }

  /// Warm to cool white, in mireds.
  PreparedCommand colorTemperature(int mireds) {
    final String? blocked = _blockedLight(
      (LightCapability c) => c.canSetTemperature,
      'This bulb does not change its white.',
    );
    if (blocked != null) return CommandRefused(blocked);

    // canSetTemperature has already established that both ends exist and are
    // the right way round, which is what makes reading them here safe.
    final LightCapability capability = light!;
    if (mireds < capability.minMireds! || mireds > capability.maxMireds!) {
      return CommandRefused(
        'This bulb only goes from ${capability.minMireds} to '
        '${capability.maxMireds} mireds.',
      );
    }
    return CommandReady(SetColorTemperature._(id, mireds));
  }

  /// A colour, as hue and saturation.
  ///
  /// Refused on a tunable-white bulb even though that bulb has something
  /// called a colour control elsewhere: `color_temp` and `hs` are separate
  /// claims, and Home Assistant's colour modes are not a ladder where the
  /// higher one implies the lower.
  PreparedCommand color({required double hue, required double saturation}) {
    final String? blocked = _blockedLight(
      (LightCapability c) => c.canSetColor,
      'This bulb is white only.',
    );
    if (blocked != null) return CommandRefused(blocked);

    if (hue < 0 || hue > 360) {
      return const CommandRefused(
        'A hue is a number of degrees from 0 to 360.',
      );
    }
    if (saturation < 0 || saturation > 100) {
      return const CommandRefused('Saturation goes from 0% to 100%.');
    }
    return CommandReady(SetColor._(id, hue: hue, saturation: saturation));
  }

  /// The reasons every command shares, in the order a person meets them: a
  /// device that cannot be reached, then one that is not theirs to change.
  String? _blocked() {
    if (availability == Availability.unavailable) {
      return 'Hearth cannot reach this device right now.';
    }
    if (!permitted) {
      return 'This Home Assistant account is not allowed to change this.';
    }
    return null;
  }

  /// The same, plus the two questions only a light has to answer.
  String? _blockedLight(
    bool Function(LightCapability) supports,
    String otherwise,
  ) {
    final String? blocked = _blocked();
    if (blocked != null) return blocked;

    final LightCapability? capability = light;
    if (id.domain != HaDomain.light || capability == null) {
      return 'Hearth can only do that to a light.';
    }
    return supports(capability) ? null : otherwise;
  }

  @override
  bool operator ==(Object other) =>
      other is CommandTarget &&
      other.id == id &&
      other.light == light &&
      other.availability == availability &&
      other.permitted == permitted;

  @override
  int get hashCode => Object.hash(id, light, availability, permitted);
}

/// Where a command has got to.
///
/// The three live phases are one story on screen — the control is busy — and
/// are kept apart because only this file knows that "Home Assistant said yes"
/// is not the end of it.
enum CommandPhase {
  /// Waiting out the debounce window. Not sent, and still replaceable by a
  /// newer value of the same slider.
  coalescing('Working…'),

  /// Handed to the transport. No answer yet.
  inFlight('Working…'),

  /// Home Assistant accepted the service call. That is a statement about Home
  /// Assistant, not about the bulb.
  accepted('Working…'),

  /// The device's own state now says what was asked for. The only phase that
  /// earns a tick.
  confirmed('Done'),

  /// The deadline passed with no matching state. The command may well have
  /// worked; Hearth has no evidence either way and says so.
  unconfirmed('Could not confirm'),

  /// The call was refused, or the connection failed outright.
  failed('Did not go through');

  const CommandPhase(this.label);

  /// What the screen calls it.
  final String label;

  /// Whether this command is still somebody's current, unresolved intention.
  bool get isLive => this == coalescing || this == inFlight || this == accepted;

  /// Whether the screen may claim the device changed.
  ///
  /// Exactly one phase says yes, and it is the one backed by the device's own
  /// account of itself.
  bool get isSuccess => this == confirmed;
}

/// One intention, and how it ended.
///
/// **This type is why replay cannot happen.** There is no public constructor:
/// the only mint is [CommandLane.request], which needs a command, the current
/// observed state, and a `now` — in other words a person doing something, at a
/// moment. There is deliberately no `toJson`/`fromJson` either, so an intent
/// cannot be written to the sync outbox, to preferences, or to anything else
/// that survives a restart (§6.2 forbids exactly that). Nothing that comes
/// back after a gap — a reconnect, an endpoint switch, a new session — has an
/// intent to resend, because an intent is not a thing that can be
/// reconstituted. And [_at] refuses to move a resolved intent back into a live
/// phase, so a resolved command cannot be revived either. A delayed replay
/// could undo what the other person in the house did in the meantime.
@immutable
final class PendingIntent {
  const PendingIntent._({
    required this.command,
    required this.sequence,
    required this.requestedAt,
    required this.readyAt,
    required this.alreadyMatched,
    required this.phase,
    this.sentAt,
    this.failure,
  });

  final HaCommand command;

  /// Which intention this is, counting up per entity and never reused.
  ///
  /// It is what an answer has to name in order to resolve this command. An
  /// answer from an old socket, or one that a newer request has overtaken,
  /// carries an older sequence and is dropped — otherwise a stale success
  /// would confirm an intention formed after it.
  final int sequence;

  /// When the person asked. Anything Home Assistant knew before this moment is
  /// evidence about the world before the tap.
  final DateTime requestedAt;

  /// The earliest this may be sent — [requestedAt] plus the debounce window
  /// for a slider, and [requestedAt] itself for a tap.
  final DateTime readyAt;

  /// Whether the device already looked like this when it was asked for.
  ///
  /// Kept from the moment of the request, because that is the only moment the
  /// question is fair: a state event arriving later is either the confirmation
  /// itself or news about something else.
  final bool alreadyMatched;

  final CommandPhase phase;

  /// When it went to the transport. The confirmation deadline runs from here
  /// rather than from [requestedAt] — a command held behind another one has
  /// not had its chance yet.
  final DateTime? sentAt;

  /// What went wrong, for [CommandPhase.failed].
  final String? failure;

  /// What the screen says about this command.
  String get label => failure ?? phase.label;

  PendingIntent _at(CommandPhase next, {DateTime? sentAt, String? failure}) {
    // A resolved intent is history. Without this, a late answer arriving after
    // the deadline could put a command back in flight, which is a replay with
    // extra steps.
    if (!phase.isLive) return this;
    return PendingIntent._(
      command: command,
      sequence: sequence,
      requestedAt: requestedAt,
      readyAt: readyAt,
      alreadyMatched: alreadyMatched,
      phase: next,
      sentAt: sentAt ?? this.sentAt,
      failure: failure ?? this.failure,
    );
  }
}

/// The command policy for one entity: at most one command in flight, the
/// newest intention winning, and nothing outliving a connection.
///
/// Immutable and pure — every method returns the next lane. It models *when*
/// something may be sent and *what* may then be claimed; it holds no timer and
/// no socket. A caller asks [dueAt] whenever its own clock ticks.
///
/// Serialising per entity is not tidiness. Two overlapping `light.turn_on`
/// calls to one bulb arrive in whatever order the mesh decides, and the one
/// that lands last wins — which may be the one the person asked for first.
@immutable
final class CommandLane {
  const CommandLane._({this.sent, this.waiting, this.issued = 0});

  /// A lane with nothing in it.
  const CommandLane.idle() : sent = null, waiting = null, issued = 0;

  /// The command handed to the transport, live or resolved. A resolved one is
  /// kept so the screen can say how it ended.
  final PendingIntent? sent;

  /// The newest intention, not yet sent — either still inside its debounce
  /// window or waiting for [sent] to resolve.
  final PendingIntent? waiting;

  /// How many intentions this entity has had. Never reset, including across a
  /// connection loss: a sequence that restarts is how a stale answer gets
  /// matched to a new intent.
  final int issued;

  /// The intention the screen should be showing — the newest one there is.
  PendingIntent? get intent => waiting ?? sent;

  /// What the person has asked for and not yet got, if anything.
  ///
  /// This is the whole of "pending intent is separate from observed state":
  /// the intention is a layer of its own that the screen draws over the
  /// device's reading, and there is deliberately no method here that folds one
  /// into the other. Merging them is precisely how a state event from before
  /// the tap ends up overwriting what the person just asked for — the slider
  /// jumps back under their finger.
  HaCommand? get liveIntent {
    final PendingIntent? current = intent;
    return current != null && current.phase.isLive ? current.command : null;
  }

  /// Whether a control should read as busy.
  bool get isBusy => liveIntent != null;

  /// Somebody asked for something.
  ///
  /// Any waiting intention is discarded: that is the coalescing rule, and it
  /// is the same rule as newest-wins. A value the finger passed through on the
  /// way is not an intention, and sending it would be sending something nobody
  /// asked for.
  ///
  /// [observed] is the device's current reading, and is used once, here, to
  /// decide whether this command has anything to wait for at all.
  CommandLane request(
    HaCommand command, {
    required DateTime now,
    required EntityState observed,
  }) => CommandLane._(
    sent: sent,
    waiting: PendingIntent._(
      command: command,
      sequence: issued + 1,
      requestedAt: now,
      readyAt: command.isCoalescable
          ? now.add(HaCommandPolicy.sliderDebounce)
          : now,
      alreadyMatched: command.isSatisfiedBy(observed),
      phase: CommandPhase.coalescing,
    ),
    issued: issued + 1,
  );

  /// What the transport should send at [now], or null if nothing should go
  /// yet. Asking changes nothing; [markSent] does.
  PendingIntent? dueAt(DateTime now) {
    final PendingIntent? next = waiting;
    if (next == null) return null;
    // One at a time per entity.
    if (sent != null && sent!.phase.isLive) return null;
    // Still collecting slider movement.
    if (now.isBefore(next.readyAt)) return null;
    return next;
  }

  /// The waiting command has gone to the transport.
  CommandLane markSent(DateTime now) {
    final PendingIntent? next = waiting;
    if (next == null) return this;
    return CommandLane._(
      sent: next._at(CommandPhase.inFlight, sentAt: now),
      waiting: null,
      issued: issued,
    );
  }

  /// Home Assistant accepted the call.
  ///
  /// Acceptance alone resolves nothing — except for a command that already
  /// matched the state when it was made, which has no change event coming and
  /// would otherwise spin until the deadline and then disown itself.
  ///
  /// [sequence] must be the one that was sent. An answer naming an older
  /// intention is an answer to a command that has been superseded, and letting
  /// it through would confirm the wrong thing.
  CommandLane markAccepted({required int sequence}) {
    final PendingIntent? current = sent;
    if (current == null || current.sequence != sequence) return this;
    return CommandLane._(
      sent: current._at(
        current.alreadyMatched ? CommandPhase.confirmed : CommandPhase.accepted,
      ),
      waiting: waiting,
      issued: issued,
    );
  }

  /// The call was refused, or the transport could not deliver it.
  ///
  /// A refusal is the one honest failure: Home Assistant said no, so nothing
  /// happened. It does not become a retry — see [PendingIntent].
  CommandLane markFailed({required int sequence, required String reason}) {
    final PendingIntent? current = sent;
    if (current == null || current.sequence != sequence) return this;
    return CommandLane._(
      sent: current._at(CommandPhase.failed, failure: reason),
      waiting: waiting,
      issued: issued,
    );
  }

  /// A state event arrived.
  ///
  /// It confirms the command in flight only if it is *newer* than the request
  /// and says what was asked for. An older event cannot confirm — it describes
  /// the world before the tap — and it cannot refute either: a command is
  /// never failed by a mismatch, only by running out of time. That asymmetry
  /// is what stops a late event from overwriting a newer intention.
  CommandLane observe(EntityState observed) {
    final PendingIntent? current = sent;
    if (current == null || !current.phase.isLive) return this;

    final DateTime? at = observed.lastUpdated;
    // An event with no clock on it cannot be placed against the request.
    // Falling back to arrival time would make a late event look current,
    // which is the exact confusion being guarded against.
    if (at == null) return this;
    if (at.isBefore(current.requestedAt)) return this;
    if (!current.command.isSatisfiedBy(observed)) return this;

    return CommandLane._(
      sent: current._at(CommandPhase.confirmed),
      waiting: waiting,
      issued: issued,
    );
  }

  /// Time passed.
  ///
  /// Past the deadline with no confirming event, the honest answer is "Could
  /// not confirm" — never a tick, and never a retry. The command may have
  /// worked; showing the latest state and letting the person decide to press
  /// again is the only move that cannot undo somebody else's.
  CommandLane tick(DateTime now) {
    final PendingIntent? current = sent;
    if (current == null || !current.phase.isLive) return this;
    final DateTime? from = current.sentAt;
    if (from == null) return this;
    if (now.difference(from) < HaCommandPolicy.confirmationDeadline) {
      return this;
    }
    return CommandLane._(
      sent: current._at(CommandPhase.unconfirmed),
      waiting: waiting,
      issued: issued,
    );
  }

  /// The connection went away — dropped, reconnected, switched between the
  /// local and the remote endpoint, or the session restarted.
  ///
  /// Anything in flight becomes unconfirmed, because delivery is now genuinely
  /// unknown. Anything still waiting is **dropped**: it was never sent, and
  /// there is no path in this class that could send it afterwards. That is the
  /// no-replay rule as a shape rather than a promise — the lane that comes
  /// back has nothing to send, so nothing can be sent.
  CommandLane connectionLost() => CommandLane._(
    sent: sent != null && sent!.phase.isLive
        ? sent!._at(CommandPhase.unconfirmed)
        : sent,
    waiting: null,
    issued: issued,
  );

  /// The person has seen how it ended; stop saying it.
  ///
  /// [issued] survives, so the next intention gets a number that no answer to
  /// the last one can name.
  CommandLane cleared() => CommandLane._(issued: issued);
}
