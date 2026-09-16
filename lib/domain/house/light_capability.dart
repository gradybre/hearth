/// What a particular bulb can actually do
/// (`docs/HOME_ASSISTANT_SPEC.md` §3, §6.2).
///
/// Pure Dart. The rule: **respect `supported_color_modes`.** No colour control
/// on an on/off-only bulb, no brightness slider on something that has never
/// claimed to dim. A control that can only ever fail is worse than no control,
/// because the person tapping it has no way to know that.
///
/// Home Assistant's colour modes are also mutually exclusive in a way that is
/// easy to get wrong: a bulb reporting `onoff` reports *only* that, and a bulb
/// reporting `brightness` cannot take a colour. The modes are not a ladder
/// where the top one implies the rest — `color_temp` does not imply `hs`, and
/// several bulbs support one without the other.
library;

import 'package:meta/meta.dart';

/// A Home Assistant light colour mode.
///
/// Only the ones Hearth draws. Anything else — the several colour spaces that
/// differ in ways no household UI should expose — is [unknown], which
/// contributes no control rather than a guessed one.
enum LightColorMode {
  /// The bulb can only be on or off.
  onOff('onoff'),

  /// Dimmable, with no colour.
  brightness('brightness'),

  /// Warm to cool white, in mireds.
  colorTemp('color_temp'),

  /// Hue and saturation.
  hs('hs'),

  /// A mode Hearth does not draw a control for.
  unknown('');

  const LightColorMode(this.wire);

  final String wire;

  static LightColorMode parse(String? value) => values.firstWhere(
    (LightColorMode m) => m.wire == value && m != unknown,
    orElse: () => unknown,
  );
}

/// What this bulb supports, read from its attributes and nothing else.
@immutable
class LightCapability {
  const LightCapability({required this.modes, this.minMireds, this.maxMireds});

  /// Nothing claimed. The honest default for a light whose attributes have
  /// not arrived: on/off only, which is the one thing every light can do.
  static const LightCapability onOffOnly = LightCapability(
    modes: <LightColorMode>{LightColorMode.onOff},
  );

  /// Read from `supported_color_modes`, which Home Assistant reports as a
  /// list of strings.
  ///
  /// A missing or malformed list is [onOffOnly] rather than an exception:
  /// §9 requires discovery to survive malformed metadata, and a bulb that can
  /// at least be switched is more use than a row that failed to build.
  factory LightCapability.fromAttributes(Map<String, Object?> attributes) {
    final Object? raw = attributes['supported_color_modes'];
    if (raw is! List) return onOffOnly;

    final Set<LightColorMode> modes = <LightColorMode>{
      for (final Object? entry in raw)
        if (entry is String) LightColorMode.parse(entry),
    }..remove(LightColorMode.unknown);

    if (modes.isEmpty) return onOffOnly;

    return LightCapability(
      modes: modes,
      minMireds: _asInt(attributes['min_mireds']),
      maxMireds: _asInt(attributes['max_mireds']),
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final double v => v.round(),
    _ => null,
  };

  /// Every mode the bulb claims. Never empty — see [onOffOnly].
  final Set<LightColorMode> modes;

  /// The warm end and the cool end, where the bulb says.
  ///
  /// Null when it does not. A slider with invented ends would send values the
  /// bulb refuses, so the control is not drawn without both (§3: "respect
  /// supported_color_modes, ranges, and current API conventions").
  final int? minMireds;
  final int? maxMireds;

  /// Whether a brightness control should exist.
  ///
  /// True for any mode that carries brightness — which is every mode except
  /// `onoff`. A colour bulb dims; that is not a separate claim it has to make.
  bool get canDim => modes.any((LightColorMode m) => m != LightColorMode.onOff);

  /// Whether a warm/cool control should exist, *and* has ends to draw between.
  bool get canSetTemperature =>
      modes.contains(LightColorMode.colorTemp) &&
      minMireds != null &&
      maxMireds != null &&
      minMireds! < maxMireds!;

  /// Whether a colour control should exist.
  bool get canSetColor => modes.contains(LightColorMode.hs);

  @override
  bool operator ==(Object other) =>
      other is LightCapability &&
      other.minMireds == minMireds &&
      other.maxMireds == maxMireds &&
      other.modes.length == modes.length &&
      other.modes.containsAll(modes);

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(modes), minMireds, maxMireds);
}
