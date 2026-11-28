import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How much craft a sketch is drawn with, which depends on how big it is
/// (spec §6.1, §6.3).
///
/// The reference illustrations the November 2026 templates were built from
/// are engravings: a heavy outline against fine interior lines, hatching for
/// shadow, and ink that catches and misses as it would on rough paper. None
/// of that is in the markup — a language model placing forty consistent
/// strokes is a model failing silently — so the painter supplies it and the
/// markup stays eight plain shapes.
///
/// **It is all off at thumbnail size, and that is the point.** Rendered at
/// forty points, hatching is a grey smudge and broken ink is a dotted line;
/// both make a drawing *harder* to read in exchange for character nobody can
/// see. The threshold is where a drawing stops being an icon and starts
/// being a picture.
@immutable
class SketchStyle {
  const SketchStyle({
    required this.hatch,
    required this.brokenInk,
    required this.washAlpha,
    required this.hatchSpacing,
  });

  /// A drawing small enough to be read rather than looked at.
  ///
  /// Below this every embellishment is off. Hearth draws recipe icons at 36
  /// to 48 and its own marks at 44 to 150, so the plain path is the common
  /// one and the ornamented path is for a hero.
  static const double plainBelow = 72;

  /// Nothing but the strokes, as the painter has always drawn them.
  static const SketchStyle plain = SketchStyle(
    hatch: false,
    brokenInk: false,
    washAlpha: 0.16,
    hatchSpacing: 0,
  );

  /// Everything, for a drawing with room to show it.
  static const SketchStyle engraved = SketchStyle(
    hatch: true,
    brokenInk: true,
    // Lighter than the flat wash, because hatching is doing the shading now
    // and two kinds of shadow on one shape is a smudge.
    washAlpha: 0.1,
    hatchSpacing: 2.6,
  );

  /// Whether a filled region is shaded with lines rather than a flat wash.
  final bool hatch;

  /// Whether a stroke's alpha wanders along its length, the way ink does.
  final bool brokenInk;

  /// How strongly a filled region is washed, as a fraction of the ink.
  final double washAlpha;

  /// The gap between hatch lines, in the drawing's own units.
  final double hatchSpacing;

  /// What a drawing of [size] points should be drawn with.
  ///
  /// One number in, so a caller cannot ask for hatching on a thumbnail by
  /// accident — and so the decision is a pure function with a test rather
  /// than a condition buried in a paint method.
  static SketchStyle forSize(double size) =>
      size >= plainBelow ? engraved : plain;

  /// How far along a stroke the ink is thin, at [t] from 0 to 1.
  ///
  /// Low-frequency and seeded by the shape, never random: a drawing that
  /// shimmered on every repaint would be worse than one drawn flat. Two
  /// waves at unrelated frequencies, so the pattern does not read as a
  /// regular pulse.
  ///
  /// Between [minInk] and full strength, never outside it: an alpha over
  /// one is a clamp in debug and a crash in release, and an alpha under
  /// half stops being a line and becomes a dotted one.
  static double inkAt(double t, int seed) {
    final double a = math.sin(t * 7.3 + seed * 0.7);
    final double b = math.sin(t * 17.1 + seed * 1.9);
    final double wave = (((a + b) / 2) + 1) / 2;
    return minInk + (1 - minInk) * wave;
  }

  /// The thinnest the ink gets.
  static const double minInk = 0.66;

  @override
  bool operator ==(Object other) =>
      other is SketchStyle &&
      other.hatch == hatch &&
      other.brokenInk == brokenInk &&
      other.washAlpha == washAlpha &&
      other.hatchSpacing == hatchSpacing;

  @override
  int get hashCode => Object.hash(hatch, brokenInk, washAlpha, hatchSpacing);
}
