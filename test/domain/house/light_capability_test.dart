import 'package:hearth/domain/house/light_capability.dart';
import 'package:test/test.dart';

/// A control that can only ever fail is worse than no control
/// (`docs/HOME_ASSISTANT_SPEC.md` §3).
void main() {
  LightCapability of(
    List<Object?>? modes, {
    Object? minMireds,
    Object? maxMireds,
  }) => LightCapability.fromAttributes(<String, Object?>{
    'supported_color_modes': ?modes,
    'min_mireds': ?minMireds,
    'max_mireds': ?maxMireds,
  });

  group('an on/off bulb gets a switch and nothing else', () {
    test('no dimming, no warmth, no colour', () {
      final LightCapability bulb = of(<String>['onoff']);
      expect(bulb.canDim, isFalse);
      expect(bulb.canSetTemperature, isFalse);
      expect(bulb.canSetColor, isFalse);
    });
  });

  group('a dimmable bulb gets a brightness slider', () {
    test('but still no colour', () {
      final LightCapability bulb = of(<String>['brightness']);
      expect(bulb.canDim, isTrue);
      expect(bulb.canSetColor, isFalse);
      expect(bulb.canSetTemperature, isFalse);
    });
  });

  group('the modes are not a ladder', () {
    test('warm-to-cool does not imply colour', () {
      // Several real bulbs do one and not the other, and offering a colour
      // wheel on a tunable-white bulb is a control that can only fail.
      final LightCapability bulb = of(
        <String>['color_temp'],
        minMireds: 153,
        maxMireds: 500,
      );
      expect(bulb.canSetTemperature, isTrue);
      expect(bulb.canSetColor, isFalse);
    });

    test('and colour does not imply warm-to-cool', () {
      final LightCapability bulb = of(<String>['hs']);
      expect(bulb.canSetColor, isTrue);
      expect(bulb.canSetTemperature, isFalse);
    });

    test('though either one dims', () {
      // Brightness rides along with every mode except onoff. A colour bulb
      // does not have to claim `brightness` separately.
      expect(of(<String>['hs']).canDim, isTrue);
      expect(of(<String>['color_temp']).canDim, isTrue);
    });
  });

  group('a range with no ends is not a range', () {
    test('warm-to-cool needs both ends before it is drawn', () {
      // Inventing the ends would send values the bulb refuses.
      expect(of(<String>['color_temp']).canSetTemperature, isFalse);
      expect(
        of(<String>['color_temp'], minMireds: 153).canSetTemperature,
        isFalse,
      );
      expect(
        of(<String>['color_temp'], maxMireds: 500).canSetTemperature,
        isFalse,
      );
    });

    test('and ends the wrong way round are not a range either', () {
      expect(
        of(
          <String>['color_temp'],
          minMireds: 500,
          maxMireds: 153,
        ).canSetTemperature,
        isFalse,
      );
    });

    test('but a whole-number range sent as a double still is one', () {
      final LightCapability bulb = of(
        <String>['color_temp'],
        minMireds: 153.0,
        maxMireds: 500.0,
      );
      expect(bulb.canSetTemperature, isTrue);
      expect(bulb.minMireds, 153);
    });
  });

  group('and malformed metadata costs a control, never the screen', () {
    test('no attribute at all is on/off', () {
      expect(of(null).modes, LightCapability.onOffOnly.modes);
      expect(of(null).canDim, isFalse);
    });

    test('so is a list of things that are not modes', () {
      // §9 requires discovery to survive this. A bulb that can at least be
      // switched is more use than a row that failed to build.
      expect(of(<Object?>[1, true, null]).canDim, isFalse);
      expect(of(<Object?>[]).canDim, isFalse);
    });

    test('and an unrecognised mode contributes no control of its own', () {
      // A colour space Hearth does not draw. The bulb is still switchable.
      final LightCapability bulb = of(<String>['xy']);
      expect(bulb.canSetColor, isFalse);
      expect(bulb.canDim, isFalse);
    });

    test('but a good mode beside a bad one still counts', () {
      final LightCapability bulb = of(<Object?>['hs', 'rgbww', 42]);
      expect(bulb.canSetColor, isTrue);
    });
  });
}
