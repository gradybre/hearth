import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/recipes/sketch_icon.dart';
import 'recipe_icon_controller.dart';

/// A recipe's little hand-drawn sketch, wherever it is shown (spec §5.2).
///
/// Renders nothing at all when there is no icon, or when the markup does not
/// survive [SketchIcon.parse]. A placeholder box on every recipe would make an
/// undrawn library look broken rather than simply undrawn — the same choice
/// [RecipePhoto] makes.
///
/// Decorative, and marked as such. The recipe's name is what carries the
/// meaning; a screen reader announcing "sketch of a bowl" in front of
/// "Chicken noodle soup" would be reading the decoration twice and the recipe
/// once (spec §6.3).
///
/// The drawing takes its colour here rather than from the markup. §6.1 gives
/// the app one warm neutral and one accent and ships light and dark from day
/// one; an icon with baked-in colours would be wrong in one of them, so every
/// colour the model wrote is discarded and this supplies one.
class RecipeIcon extends StatelessWidget {
  const RecipeIcon({
    required this.svg,
    required this.size,
    this.color,
    super.key,
  });

  /// The stored markup, or null for a recipe that has no icon.
  final String? svg;

  final double size;

  /// Defaults to the body text colour: a sketch beside a title is structure,
  /// not an action, and the single accent belongs to things you can press.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final SketchIcon? icon = _cached(svg);
    if (icon == null) return const SizedBox.shrink();

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        // The theme is read only when the caller has not named a colour, so a
        // sketch can be drawn outside Hearth's own theme — a test, a preview —
        // without reaching for an extension that is not there.
        child: CustomPaint(
          painter: _SketchPainter(
            icon: icon,
            color: color ?? context.colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Whether [svg] is something this would actually draw.
  ///
  /// For callers deciding on layout before they build — a library row leaves
  /// no gap where an icon was never going to appear.
  static bool canDraw(String? svg) => _cached(svg) != null;

  /// Parses at most [_cacheLimit] distinct icons, keeping the result.
  ///
  /// A library row rebuilds on every scroll frame, every favourite toggle and
  /// every macro recalculation, and re-tokenising a document each time to
  /// draw the same muffin would be work nobody asked for. Keyed by the markup
  /// itself, so an icon that changes is a different key and no invalidation
  /// is needed.
  static final Map<String, SketchIcon?> _cache = <String, SketchIcon?>{};
  static const int _cacheLimit = 200;

  static SketchIcon? _cached(String? svg) {
    if (svg == null || svg.isEmpty) return null;
    if (_cache.containsKey(svg)) return _cache[svg];
    // Oldest out first. A household with more than two hundred recipes on
    // screen at once does not exist, so this is a leak guard rather than an
    // eviction policy worth tuning.
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    return _cache[svg] = SketchIcon.parse(svg);
  }
}

/// Paints a validated sketch, and only ever a validated one.
class _SketchPainter extends CustomPainter {
  const _SketchPainter({required this.icon, required this.color});

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
  bool shouldRepaint(_SketchPainter old) =>
      old.icon != icon || old.color != color;
}

/// The editor's icon control: see the sketch, redraw it, or be rid of it
/// (spec §5.2).
///
/// This control is the reason writing an icon without a review screen is
/// defensible at all (see [RecipeIconController]). The rule behind rule 4 is
/// that the user stays in charge of what lands in their library; for a
/// decorative, reversible drawing, staying in charge means being able to
/// throw it away and ask for another — which is exactly this.
class RecipeIconField extends ConsumerStatefulWidget {
  const RecipeIconField({
    required this.recipeId,
    required this.svg,
    required this.onCleared,
    super.key,
  });

  /// Null until the recipe has been saved once — an icon needs something to
  /// belong to, the same way a photo does.
  final String? recipeId;

  final String? svg;

  /// Told when the icon goes, so the form stops carrying it into the next
  /// save. Without this the editor's own draft would put it straight back.
  final VoidCallback onCleared;

  @override
  ConsumerState<RecipeIconField> createState() => _RecipeIconFieldState();
}

class _RecipeIconFieldState extends ConsumerState<RecipeIconField> {
  bool _drawing = false;

  Future<void> _redraw() async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null || _drawing) return;

    setState(() => _drawing = true);
    try {
      await ref
          .read(recipeIconControllerProvider)
          .drawFor(recipeId: recipeId, title: _title());
    } finally {
      if (mounted) setState(() => _drawing = false);
    }
  }

  /// The title as saved, which is what the icon is drawn from.
  ///
  /// Read back from the store rather than from the form: an unsaved rename is
  /// not what the recipe is called yet, and drawing from it would leave an
  /// icon that matches nothing anybody can see.
  String _title() =>
      ref.read(recipeByIdProvider(widget.recipeId!)).value?.title ?? '';

  Future<void> _remove() async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null) return;
    await ref.read(recipeIconControllerProvider).clear(recipeId);
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String? recipeId = widget.recipeId;
    if (recipeId == null ||
        !ref.watch(recipeIconControllerProvider).isAvailable) {
      return const SizedBox.shrink();
    }

    // The stored icon, not the one the form opened with: a background drawing
    // that landed while the editor was open should show.
    final String? svg =
        ref.watch(recipeByIdProvider(recipeId)).value?.iconSvg ?? widget.svg;
    final bool hasIcon = RecipeIcon.canDraw(svg);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasIcon) ...<Widget>[
          RecipeIcon(svg: svg, size: 48),
          const SizedBox(width: HearthSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                hasIcon
                    ? 'Hearth sketched this from the title.'
                    : 'Hearth sketches a little icon from the title when you '
                          'save.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: HearthSpacing.sm),
              Wrap(
                spacing: HearthSpacing.sm,
                runSpacing: HearthSpacing.sm,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _drawing ? null : _redraw,
                    icon: const Icon(Icons.gesture, size: 18),
                    label: Text(hasIcon ? 'Draw another' : 'Draw one now'),
                  ),
                  if (hasIcon)
                    TextButton.icon(
                      onPressed: _drawing ? null : _remove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove icon'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
