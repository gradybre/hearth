import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/recipes/sketch_icon.dart';
import '../theme/hearth_theme.dart';

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
  const SketchPainter({required this.icon, required this.color});

  final SketchIcon icon;
  final Color color;

  /// A filled area is painted as a wash of the same colour rather than a
  /// solid block: one colour at full strength everywhere would turn a sketch
  /// into a silhouette.
  static const double _fillOpacity = 0.16;

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

    for (final SketchShape shape in icon.shapes) {
      final Path path = _pathFor(shape);
      if (!shape.transform.isIdentity) {
        path.transform(_matrix(shape.transform));
      }

      if (shape.filled) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: color.a * _fillOpacity),
        );
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
    }

    canvas.restore();
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
      old.icon != icon || old.color != color;
}
