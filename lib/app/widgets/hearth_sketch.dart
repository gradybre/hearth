import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/recipes/sketch_icon.dart';
import '../theme/hearth_theme.dart';
import 'sketch_style.dart';

/// A line drawing, wherever the app wants one.
///
/// Hearth's sketches are SVG that the whitelist in [SketchIcon] has agreed
/// to — a stroke-only subset of paths and primitives — and this draws one at
/// any size in a colour the theme supplies. The markup's own colours are
/// discarded: §6.1 gives the app one warm neutral and one accent and ships
/// light and dark from day one, so a drawing with colours baked into it
/// would be wrong in one of them.
///
/// Decorative, and marked as such. Every sketch in Hearth sits beside words
/// that already carry the meaning, and a screen reader announcing "sketch of
/// a pot" in front of "Nutrition" reads the decoration twice and the room
/// once (spec §6.3).
///
/// This is `RecipeIcon`'s drawing half, lifted out of it. The marks the app
/// draws of itself belong to no feature, so the widget that draws them
/// cannot live in one.
class HearthSketch extends StatelessWidget {
  const HearthSketch({
    required this.svg,
    required this.size,
    this.color,
    super.key,
  });

  /// The markup, or null for nothing to draw.
  final String? svg;

  final double size;

  /// Defaults to the body text colour: a sketch beside a title is structure,
  /// not an action, and the single accent belongs to things you can press.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final SketchIcon? icon = SketchIcon.cached(svg);
    if (icon == null) return const SizedBox.shrink();

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        // The theme is read only when the caller has not named a colour, so
        // a sketch can be drawn outside Hearth's own theme — a test, a
        // preview — without reaching for an extension that is not there.
        child: CustomPaint(
          painter: SketchPainter(
            icon: icon,
            color: color ?? context.colors.textSecondary,
            // The craft is the painter's, and how much of it to spend is a
            // question about size: see [SketchStyle].
            style: SketchStyle.forSize(size),
          ),
        ),
      ),
    );
  }

  /// Whether [svg] is something this would actually draw.
  static bool canDraw(String? svg) => SketchIcon.cached(svg) != null;
}

/// Paints a validated sketch, and only ever a validated one.
///
/// Public because two widgets draw the same sketches — the app's own
/// marks and a recipe's — and a second copy of the viewBox arithmetic is
/// a second place for it to drift.
class SketchPainter extends CustomPainter {
  const SketchPainter({
    required this.icon,
    required this.color,
    this.style = SketchStyle.plain,
  });

  final SketchIcon icon;
  final Color color;

  /// How much craft to draw with. Plain by default, so a caller that has
  /// not thought about it gets what the painter has always done.
  final SketchStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    // Fit the viewBox the way `preserveAspectRatio="xMidYMid meet"` would, so
    // a sketch drawn on a non-square canvas is centred rather than stretched.
    final double scale = math.min(
      size.width / icon.width,
      size.height / icon.height,
    );
    if (!scale.isFinite || scale <= 0) return;

    canvas.save();
    canvas.translate(
      (size.width - icon.width * scale) / 2,
      (size.height - icon.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-icon.minX, -icon.minY);

    int index = 0;
    for (final SketchShape shape in icon.shapes) {
      final Path path = _pathFor(shape);
      if (!shape.transform.isIdentity) {
        path.transform(_matrix(shape.transform));
      }

      if (shape.filled) {
        // The wash: a fraction of the ink, feathered rather than cut, so a
        // shaded region reads as shadow instead of as a second shape. One
        // colour at full strength everywhere would turn a sketch into a
        // silhouette.
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: color.a * style.washAlpha)
            ..maskFilter = style.hatch
                ? const MaskFilter.blur(BlurStyle.normal, 1.6)
                : null,
        );
        if (style.hatch) _hatch(canvas, path);
      }
      if (style.brokenInk) {
        _brokenInk(canvas, path, shape.strokeWidth, index);
        index++;
        continue;
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth
          // Round throughout: this is a doodle in a notebook margin, not a
          // technical drawing, and mitred corners read as neither.
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
      index++;
    }

    canvas.restore();
  }

  /// Shades a region with lines instead of a flat tone.
  ///
  /// This is the reference art's signature, and the one thing a language
  /// model cannot be asked for: twenty evenly spaced parallel lines are
  /// twenty chances to be slightly wrong. The markup says *this region is
  /// shaded* by filling it; the spacing and the angle are the house's.
  void _hatch(Canvas canvas, Path region) {
    final Rect bounds = region.getBounds();
    if (bounds.isEmpty) return;
    canvas.save();
    canvas.clipPath(region);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: color.a * 0.5);
    // Forty-five degrees, drawn across the whole bounding box and clipped
    // back: starting at the shape's own edge would leave the first and last
    // lines short in a way the eye reads as a mistake.
    final double span = bounds.width + bounds.height;
    for (
      double x = bounds.left - bounds.height;
      x < bounds.right;
      x += style.hatchSpacing
    ) {
      canvas.drawLine(
        Offset(x, bounds.bottom),
        Offset(x + span, bounds.bottom - span),
        paint,
      );
    }
    canvas.restore();
  }

  /// Draws a stroke whose ink wanders, the way a pen on rough paper does.
  ///
  /// Walked in short segments with the alpha modulated along the length.
  /// Seeded by the shape's position in the drawing, never random: an icon
  /// that shimmered on every repaint would be worse than one drawn flat.
  void _brokenInk(Canvas canvas, Path path, double width, int seed) {
    for (final ui.PathMetric metric in path.computeMetrics()) {
      if (metric.length <= 0) continue;
      final int steps = math.max(6, (metric.length / 1.6).round());
      for (int i = 0; i < steps; i++) {
        final ui.Tangent? a = metric.getTangentForOffset(
          metric.length * i / steps,
        );
        final ui.Tangent? b = metric.getTangentForOffset(
          metric.length * (i + 1) / steps,
        );
        if (a == null || b == null) continue;
        canvas.drawLine(
          a.position,
          b.position,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(
              alpha: color.a * SketchStyle.inkAt((i + 0.5) / steps, seed),
            ),
        );
      }
    }
  }

  static Path _pathFor(SketchShape shape) {
    final Path path = Path();
    switch (shape) {
      case SketchPath(:final List<SketchCommand> commands):
        for (final SketchCommand command in commands) {
          switch (command) {
            case SketchMoveTo(:final double x, :final double y):
              path.moveTo(x, y);
            case SketchLineTo(:final double x, :final double y):
              path.lineTo(x, y);
            case SketchCubicTo(
              :final double x1,
              :final double y1,
              :final double x2,
              :final double y2,
              :final double x,
              :final double y,
            ):
              path.cubicTo(x1, y1, x2, y2, x, y);
            case SketchQuadraticTo(
              :final double x1,
              :final double y1,
              :final double x,
              :final double y,
            ):
              path.quadraticBezierTo(x1, y1, x, y);
            case SketchArcTo(
              :final double rx,
              :final double ry,
              :final double rotation,
              :final bool largeArc,
              :final bool clockwise,
              :final double x,
              :final double y,
            ):
              // Flutter's arc takes SVG's own parameters, so the elliptical
              // arc needs no conversion to cubics here.
              path.arcToPoint(
                Offset(x, y),
                radius: Radius.elliptical(rx, ry),
                rotation: rotation,
                largeArc: largeArc,
                clockwise: clockwise,
              );
            case SketchClose():
              path.close();
          }
        }
      case SketchCircle(:final double cx, :final double cy, :final double r):
        path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case SketchEllipse(
        :final double cx,
        :final double cy,
        :final double rx,
        :final double ry,
      ):
        path.addOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      case SketchLine(
        :final double x1,
        :final double y1,
        :final double x2,
        :final double y2,
      ):
        path
          ..moveTo(x1, y1)
          ..lineTo(x2, y2);
      case SketchPolyline(:final List<SketchPoint> points, :final bool closed):
        path.moveTo(points.first.x, points.first.y);
        for (final SketchPoint point in points.skip(1)) {
          path.lineTo(point.x, point.y);
        }
        if (closed) path.close();
      case SketchRect(
        :final double x,
        :final double y,
        :final double width,
        :final double height,
        :final double rx,
        :final double ry,
      ):
        final Rect rect = Rect.fromLTWH(x, y, width, height);
        if (rx > 0 || ry > 0) {
          path.addRRect(RRect.fromRectXY(rect, rx, ry > 0 ? ry : rx));
        } else {
          path.addRect(rect);
        }
    }
    return path;
  }

  /// The 2-D affine as the 4×4 matrix `Path.transform` wants, column-major.
  static Float64List _matrix(SketchTransform t) =>
      Float64List.fromList(<double>[
        t.a, t.b, 0, 0, //
        t.c, t.d, 0, 0, //
        0, 0, 1, 0, //
        t.e, t.f, 0, 1, //
      ]);

  @override
  bool shouldRepaint(SketchPainter old) =>
      old.icon != icon || old.color != color || old.style != style;
}
