/// A recipe's little hand-drawn icon, and the gate everything must pass to
/// become one (spec §5.2, §6.1).
///
/// The markup is written by a language model and is therefore **untrusted
/// input that renders in the app**. Nothing here trusts it: the document is
/// tokenised by hand, every element and every attribute is checked against a
/// whitelist, and anything outside it fails the whole icon rather than being
/// stripped and rendered anyway. Silent stripping is how a sanitiser becomes a
/// bypass — it invites you to guess which half of a hostile document was the
/// dangerous half. A rejected answer means *no icon*, never a broken one.
///
/// Pure Dart on purpose. This is the cheapest test surface in the app
/// (spec §9.1), and the hostile shapes worth testing — a `<script>`, an
/// `xlink:href`, an embedded `data:` URI — are all strings.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A 2-D affine, as an SVG `transform` list flattens to.
///
/// Row-major `[a c e; b d f]`, the same order SVG's own `matrix()` states it
/// in, so a parsed `matrix(a b c d e f)` needs no rearranging.
@immutable
class SketchTransform {
  const SketchTransform(this.a, this.b, this.c, this.d, this.e, this.f);

  static const SketchTransform identity = SketchTransform(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  /// This transform followed by [inner] — the composition a nested `<g>`
  /// means, outer first.
  SketchTransform then(SketchTransform inner) => SketchTransform(
    a * inner.a + c * inner.b,
    b * inner.a + d * inner.b,
    a * inner.c + c * inner.d,
    b * inner.c + d * inner.d,
    a * inner.e + c * inner.f + e,
    b * inner.e + d * inner.f + f,
  );

  @override
  bool operator ==(Object other) =>
      other is SketchTransform &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.e == e &&
      other.f == f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);
}

/// One step of a `<path>`, resolved to absolute coordinates.
///
/// Relative commands, `H`/`V` shorthands and the smooth `S`/`T` reflections
/// are all worked out here rather than left for the renderer. A painter that
/// had to track a current point would be a second place for the maths to be
/// wrong, and it is not the place that can be unit-tested cheaply.
@immutable
sealed class SketchCommand {
  const SketchCommand();
}

@immutable
class SketchMoveTo extends SketchCommand {
  const SketchMoveTo(this.x, this.y);
  final double x;
  final double y;
}

@immutable
class SketchLineTo extends SketchCommand {
  const SketchLineTo(this.x, this.y);
  final double x;
  final double y;
}

@immutable
class SketchCubicTo extends SketchCommand {
  const SketchCubicTo(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;
}

@immutable
class SketchQuadraticTo extends SketchCommand {
  const SketchQuadraticTo(this.x1, this.y1, this.x, this.y);
  final double x1;
  final double y1;
  final double x;
  final double y;
}

@immutable
class SketchArcTo extends SketchCommand {
  const SketchArcTo({
    required this.rx,
    required this.ry,
    required this.rotation,
    required this.largeArc,
    required this.clockwise,
    required this.x,
    required this.y,
  });

  final double rx;
  final double ry;

  /// Degrees, as SVG states it.
  final double rotation;
  final bool largeArc;
  final bool clockwise;
  final double x;
  final double y;
}

@immutable
class SketchClose extends SketchCommand {
  const SketchClose();
}

/// A point in the icon's own coordinate space.
@immutable
class SketchPoint {
  const SketchPoint(this.x, this.y);
  final double x;
  final double y;
}

/// One drawable thing, with the paint it inherited.
@immutable
sealed class SketchShape {
  const SketchShape({
    required this.filled,
    required this.strokeWidth,
    required this.transform,
  });

  /// Whether the shape's interior is painted.
  ///
  /// A boolean and not a colour, deliberately. §6.1 gives the app one accent
  /// and a warm neutral, and it ships light and dark from day one — an icon
  /// carrying baked-in colours would be wrong in one of the two. Every colour
  /// the model writes is discarded here; the renderer supplies one from the
  /// theme.
  final bool filled;

  /// Relative line weight, in the icon's own units. Clamped on the way in, so
  /// no shape can paint a bar across the whole tile.
  final double strokeWidth;

  final SketchTransform transform;
}

@immutable
class SketchPath extends SketchShape {
  const SketchPath({
    required this.commands,
    required super.filled,
    required super.strokeWidth,
    required super.transform,
  });

  final List<SketchCommand> commands;
}

@immutable
class SketchCircle extends SketchShape {
  const SketchCircle({
    required this.cx,
    required this.cy,
    required this.r,
    required super.filled,
    required super.strokeWidth,
    required super.transform,
  });

  final double cx;
  final double cy;
  final double r;
}

@immutable
class SketchEllipse extends SketchShape {
  const SketchEllipse({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required super.filled,
    required super.strokeWidth,
    required super.transform,
  });

  final double cx;
  final double cy;
  final double rx;
  final double ry;
}

@immutable
class SketchLine extends SketchShape {
  const SketchLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required super.strokeWidth,
    required super.transform,
  }) : super(filled: false);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// `<polyline>` and `<polygon>`, which differ only by [closed].
@immutable
class SketchPolyline extends SketchShape {
  const SketchPolyline({
    required this.points,
    required this.closed,
    required super.filled,
    required super.strokeWidth,
    required super.transform,
  });

  final List<SketchPoint> points;
  final bool closed;
}

@immutable
class SketchRect extends SketchShape {
  const SketchRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rx,
    required this.ry,
    required super.filled,
    required super.strokeWidth,
    required super.transform,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rx;
  final double ry;
}

/// A validated sketch: a viewport and the shapes inside it.
@immutable
class SketchIcon {
  const SketchIcon({
    required this.markup,
    required this.minX,
    required this.minY,
    required this.width,
    required this.height,
    required this.shapes,
  });

  /// What a stored icon may weigh.
  ///
  /// A sketch of a muffin is a few hundred bytes of path data. Forty
  /// kilobytes of it is a traced photograph or a runaway answer — not an
  /// icon — and this column is read on every row of the recipe library, so
  /// the cap is small on purpose. The database carries the same number as a
  /// check constraint, because a limit the client alone enforces is a limit
  /// the next client forgets.
  static const int maxMarkupLength = 4096;

  /// Enough for a detailed sketch, far short of a traced photograph.
  static const int maxShapes = 200;
  static const int maxCommands = 2000;

  /// How deeply `<g>` may nest before this stops believing the document.
  static const int maxDepth = 8;

  /// Line weights outside this are not sketches: a hairline vanishes and a
  /// fat one paints a block.
  static const double minStrokeWidth = 0.1;
  static const double maxStrokeWidth = 8;

  /// The markup exactly as it was validated, which is what gets stored.
  final String markup;

  final double minX;
  final double minY;
  final double width;
  final double height;
  final List<SketchShape> shapes;

  /// Parses [markup], or answers null if it is not something safe to draw.
  ///
  /// Null covers every failure with one answer on purpose: a caller that
  /// could tell "malformed" from "hostile" would be tempted to render the
  /// malformed one.
  static SketchIcon? parse(String? markup) {
    if (markup == null) return null;
    final String source = markup.trim();
    if (source.isEmpty || source.length > maxMarkupLength) return null;
    if (_looksHostile(source)) return null;

    try {
      return _Parser(source).run();
    } on _Rejected {
      return null;
    }
  }

  /// Whether [markup] would survive [parse]. The gate before storing.
  static bool isValid(String? markup) => parse(markup) != null;

  /// Shapes worth painting before anything is tokenised.
  ///
  /// Every one of these is caught again by the element and attribute
  /// whitelists below — this is the belt to their braces, and it is here
  /// because a whitelist is only as good as the tokeniser feeding it, and the
  /// tokeniser is the part most likely to be subtly wrong.
  static bool _looksHostile(String source) {
    final String lower = source.toLowerCase();
    for (final String needle in const <String>[
      '<script',
      '<foreignobject',
      '<image',
      '<use',
      '<style',
      '<text',
      '<animate',
      '<set',
      '<iframe',
      'href',
      'xlink',
      'javascript:',
      'data:',
      'url(',
      'entity',
      'doctype',
      'cdata',
      '<!',
      '<?',
      '&#',
    ]) {
      if (lower.contains(needle)) return true;
    }
    // onclick, onload, onmouseover — any attribute the browser or a renderer
    // would treat as code.
    return RegExp(r'\son[a-z]+\s*=').hasMatch(lower);
  }
}

/// Thrown internally the moment anything is off; [SketchIcon.parse] turns it
/// into a null.
class _Rejected implements Exception {
  const _Rejected();
}

const Set<String> _shapeElements = <String>{
  'path',
  'circle',
  'ellipse',
  'line',
  'polyline',
  'polygon',
  'rect',
};

/// Presentation attributes any element may carry.
///
/// The colour ones are *allowed and then ignored* rather than banned: a model
/// asked for a line drawing will write `stroke="currentColor"` out of habit,
/// and refusing the whole icon over a word we were going to throw away would
/// be theatre.
const Set<String> _commonAttributes = <String>{
  'fill',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'stroke-dasharray',
  'stroke-opacity',
  'fill-opacity',
  'fill-rule',
  'clip-rule',
  'opacity',
  'transform',
};

const Map<String, Set<String>> _elementAttributes = <String, Set<String>>{
  'svg': <String>{'xmlns', 'viewbox', 'width', 'height', 'version'},
  'g': <String>{},
  'path': <String>{'d'},
  'circle': <String>{'cx', 'cy', 'r'},
  'ellipse': <String>{'cx', 'cy', 'rx', 'ry'},
  'line': <String>{'x1', 'y1', 'x2', 'y2'},
  'polyline': <String>{'points'},
  'polygon': <String>{'points'},
  'rect': <String>{'x', 'y', 'width', 'height', 'rx', 'ry'},
};

/// The paint an element inherits from its ancestors.
@immutable
class _Inherited {
  const _Inherited({
    required this.filled,
    required this.strokeWidth,
    required this.transform,
  });

  final bool filled;
  final double strokeWidth;
  final SketchTransform transform;
}

/// A deliberately small XML reader.
///
/// Small is the feature. `<!` and `<?` are refused outright before this runs,
/// so there are no doctypes, entities, CDATA sections or processing
/// instructions to get wrong — only elements, quoted attributes, and
/// whitespace. Anything this cannot account for is rejected rather than
/// skipped.
class _Parser {
  _Parser(this.source);

  final String source;
  int _i = 0;

  final List<SketchShape> _shapes = <SketchShape>[];
  int _commands = 0;

  SketchIcon run() {
    final _Element root = _nextElement();
    if (root.name != 'svg' || root.selfClosing) throw const _Rejected();

    final List<double> box = _numbers(root.attribute('viewbox') ?? '');
    if (box.length != 4) throw const _Rejected();
    final double width = box[2];
    final double height = box[3];
    if (!(width > 0) || !(height > 0)) throw const _Rejected();

    _children(
      'svg',
      _inherit(
        root,
        const _Inherited(
          // SVG's own initial fill is black; a sketch is a line drawing, so
          // this starts unfilled and a shape has to ask. The alternative
          // turns every unfilled path into a solid blob.
          filled: false,
          strokeWidth: 1,
          transform: SketchTransform.identity,
        ),
      ),
      depth: 1,
    );

    _skipWhitespace();
    if (_i != source.length) throw const _Rejected();
    if (_shapes.isEmpty) throw const _Rejected();

    return SketchIcon(
      markup: source,
      minX: box[0],
      minY: box[1],
      width: width,
      height: height,
      shapes: List<SketchShape>.unmodifiable(_shapes),
    );
  }

  /// Reads elements until [parent]'s closing tag.
  void _children(String parent, _Inherited inherited, {required int depth}) {
    if (depth > SketchIcon.maxDepth) throw const _Rejected();

    while (true) {
      _skipWhitespace();
      if (_i >= source.length) throw const _Rejected();
      if (source.startsWith('</', _i)) {
        _expectClose(parent);
        return;
      }

      final _Element element = _nextElement();
      final _Inherited own = _inherit(element, inherited);

      if (element.name == 'g') {
        if (!element.selfClosing) _children('g', own, depth: depth + 1);
        continue;
      }
      if (!_shapeElements.contains(element.name)) throw const _Rejected();
      if (!element.selfClosing) _expectClose(element.name);

      _emit(element, own);
      if (_shapes.length > SketchIcon.maxShapes) throw const _Rejected();
    }
  }

  void _emit(_Element element, _Inherited own) {
    switch (element.name) {
      case 'path':
        final List<SketchCommand> commands = _PathData(
          element.attribute('d') ?? '',
        ).parse();
        _commands += commands.length;
        if (commands.isEmpty || _commands > SketchIcon.maxCommands) {
          throw const _Rejected();
        }
        _shapes.add(
          SketchPath(
            commands: commands,
            filled: own.filled,
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      case 'circle':
        final double r = _length(element, 'r');
        if (!(r > 0)) throw const _Rejected();
        _shapes.add(
          SketchCircle(
            cx: _length(element, 'cx'),
            cy: _length(element, 'cy'),
            r: r,
            filled: own.filled,
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      case 'ellipse':
        final double rx = _length(element, 'rx');
        final double ry = _length(element, 'ry');
        if (!(rx > 0) || !(ry > 0)) throw const _Rejected();
        _shapes.add(
          SketchEllipse(
            cx: _length(element, 'cx'),
            cy: _length(element, 'cy'),
            rx: rx,
            ry: ry,
            filled: own.filled,
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      case 'line':
        _shapes.add(
          SketchLine(
            x1: _length(element, 'x1'),
            y1: _length(element, 'y1'),
            x2: _length(element, 'x2'),
            y2: _length(element, 'y2'),
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      case 'polyline' || 'polygon':
        final List<double> raw = _numbers(element.attribute('points') ?? '');
        if (raw.length < 4 || raw.length.isOdd) throw const _Rejected();
        _shapes.add(
          SketchPolyline(
            points: <SketchPoint>[
              for (int i = 0; i + 1 < raw.length; i += 2)
                SketchPoint(raw[i], raw[i + 1]),
            ],
            closed: element.name == 'polygon',
            filled: own.filled,
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      case 'rect':
        final double width = _length(element, 'width');
        final double height = _length(element, 'height');
        if (!(width > 0) || !(height > 0)) throw const _Rejected();
        final double rx = _length(element, 'rx');
        final double ry = _length(element, 'ry');
        _shapes.add(
          SketchRect(
            x: _length(element, 'x'),
            y: _length(element, 'y'),
            width: width,
            height: height,
            // One radius given means both, as SVG says.
            rx: rx > 0 ? rx : ry,
            ry: ry > 0 ? ry : rx,
            filled: own.filled,
            strokeWidth: own.strokeWidth,
            transform: own.transform,
          ),
        );
      default:
        throw const _Rejected();
    }
  }

  /// [element]'s paint, falling back to what it inherited.
  _Inherited _inherit(_Element element, _Inherited parent) {
    final String? fill = element.attribute('fill');
    final String? strokeWidth = element.attribute('stroke-width');
    final String? transform = element.attribute('transform');

    return _Inherited(
      // Any paint at all counts as filled; the actual colour is discarded.
      filled: fill == null
          ? parent.filled
          : fill.trim().toLowerCase() != 'none',
      strokeWidth: strokeWidth == null
          ? parent.strokeWidth
          : (double.tryParse(strokeWidth.trim()) ?? parent.strokeWidth).clamp(
              SketchIcon.minStrokeWidth,
              SketchIcon.maxStrokeWidth,
            ),
      transform: transform == null
          ? parent.transform
          : parent.transform.then(_transform(transform)),
    );
  }

  double _length(_Element element, String name) {
    final String? raw = element.attribute(name);
    if (raw == null) return 0;
    final double? value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite) throw const _Rejected();
    return value;
  }

  static final RegExp _transformCall = RegExp(r'([a-zA-Z]+)\s*\(([^()]*)\)');

  /// `translate(2 3) rotate(45)` as one affine.
  ///
  /// Only the four functions a drawing actually needs. `skewX`/`skewY` are
  /// absent because nothing sane draws a muffin with them, and every function
  /// supported is one more thing that has to be right.
  static SketchTransform _transform(String raw) {
    SketchTransform result = SketchTransform.identity;
    int consumed = 0;

    for (final RegExpMatch match in _transformCall.allMatches(raw)) {
      // Anything between the calls that is not whitespace or a comma means
      // this is not a transform list we understand.
      final String between = raw.substring(consumed, match.start);
      if (between.trim().replaceAll(',', '').isNotEmpty) {
        throw const _Rejected();
      }
      consumed = match.end;

      final List<double> a = _numbers(match.group(2) ?? '');
      result = result.then(switch (match.group(1)) {
        'translate' when a.length == 1 => SketchTransform(1, 0, 0, 1, a[0], 0),
        'translate' when a.length == 2 => SketchTransform(
          1,
          0,
          0,
          1,
          a[0],
          a[1],
        ),
        'scale' when a.length == 1 => SketchTransform(a[0], 0, 0, a[0], 0, 0),
        'scale' when a.length == 2 => SketchTransform(a[0], 0, 0, a[1], 0, 0),
        'rotate' when a.length == 1 || a.length == 3 => _rotate(a),
        'matrix' when a.length == 6 => SketchTransform(
          a[0],
          a[1],
          a[2],
          a[3],
          a[4],
          a[5],
        ),
        _ => throw const _Rejected(),
      });
    }

    if (raw.substring(consumed).trim().isNotEmpty) throw const _Rejected();
    return result;
  }

  static SketchTransform _rotate(List<double> a) {
    final double radians = a[0] * math.pi / 180;
    final double cos = math.cos(radians);
    final double sin = math.sin(radians);
    final SketchTransform rotation = SketchTransform(cos, sin, -sin, cos, 0, 0);
    if (a.length == 1) return rotation;
    // rotate(angle cx cy) is translate(cx cy) rotate(angle) translate(-cx -cy).
    return SketchTransform(
      1,
      0,
      0,
      1,
      a[1],
      a[2],
    ).then(rotation).then(SketchTransform(1, 0, 0, 1, -a[1], -a[2]));
  }

  // ── Tokenising ────────────────────────────────────────────────────────────

  void _skipWhitespace() {
    while (_i < source.length && _isWhitespace(source.codeUnitAt(_i))) {
      _i++;
    }
  }

  void _expectClose(String name) {
    _skipWhitespace();
    final String expected = '</$name>';
    if (!source.startsWith(expected, _i)) throw const _Rejected();
    _i += expected.length;
  }

  _Element _nextElement() {
    _skipWhitespace();
    if (_i >= source.length || source.codeUnitAt(_i) != _lt) {
      throw const _Rejected();
    }
    _i++;

    final int nameStart = _i;
    while (_i < source.length && _isNameChar(source.codeUnitAt(_i))) {
      _i++;
    }
    final String name = source.substring(nameStart, _i).toLowerCase();
    if (name.isEmpty) throw const _Rejected();

    final Set<String> allowed = _elementAttributes[name] ?? const <String>{};
    if (!_elementAttributes.containsKey(name)) throw const _Rejected();

    final Map<String, String> attributes = <String, String>{};
    while (true) {
      _skipWhitespace();
      if (_i >= source.length) throw const _Rejected();

      final int unit = source.codeUnitAt(_i);
      if (unit == _gt) {
        _i++;
        return _Element(name, attributes, selfClosing: false);
      }
      if (unit == _slash) {
        _i++;
        if (_i >= source.length || source.codeUnitAt(_i) != _gt) {
          throw const _Rejected();
        }
        _i++;
        return _Element(name, attributes, selfClosing: true);
      }

      final int attrStart = _i;
      while (_i < source.length && _isNameChar(source.codeUnitAt(_i))) {
        _i++;
      }
      final String attribute = source.substring(attrStart, _i).toLowerCase();
      if (attribute.isEmpty) throw const _Rejected();
      if (!allowed.contains(attribute) &&
          !_commonAttributes.contains(attribute)) {
        throw const _Rejected();
      }

      _skipWhitespace();
      if (_i >= source.length || source.codeUnitAt(_i) != _equals) {
        throw const _Rejected();
      }
      _i++;
      _skipWhitespace();

      // Quoted or nothing. An unquoted value is where a tokeniser and a
      // browser most easily disagree about where an attribute ends.
      if (_i >= source.length) throw const _Rejected();
      final int quote = source.codeUnitAt(_i);
      if (quote != _doubleQuote && quote != _singleQuote) {
        throw const _Rejected();
      }
      _i++;
      final int valueStart = _i;
      while (_i < source.length && source.codeUnitAt(_i) != quote) {
        if (source.codeUnitAt(_i) == _lt) throw const _Rejected();
        _i++;
      }
      if (_i >= source.length) throw const _Rejected();
      attributes[attribute] = source.substring(valueStart, _i);
      _i++;
    }
  }

  static const int _lt = 0x3c;
  static const int _gt = 0x3e;
  static const int _slash = 0x2f;
  static const int _equals = 0x3d;
  static const int _doubleQuote = 0x22;
  static const int _singleQuote = 0x27;

  static bool _isWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

  static bool _isNameChar(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || // a-z
      (unit >= 0x41 && unit <= 0x5a) || // A-Z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x2d; // '-'
}

@immutable
class _Element {
  const _Element(this.name, this._attributes, {required this.selfClosing});

  final String name;
  final Map<String, String> _attributes;
  final bool selfClosing;

  String? attribute(String name) => _attributes[name];
}

/// Every number in a whitespace/comma separated list.
///
/// Refuses the whole list on anything that is not a number, so a `points`
/// attribute carrying a word does not quietly become half a polygon.
List<double> _numbers(String raw) {
  final List<double> out = <double>[];
  for (final String piece in raw.split(RegExp(r'[\s,]+'))) {
    if (piece.isEmpty) continue;
    final double? value = double.tryParse(piece);
    if (value == null || !value.isFinite) throw const _Rejected();
    out.add(value);
  }
  return out;
}

/// The `d` attribute's own little grammar.
///
/// Written out rather than regexed because SVG path data is not as tidy as it
/// looks: `1.5.5` is two numbers, arc flags may run together with what
/// follows them (`a1 1 0 011 1`), and a command letter repeats implicitly for
/// every extra set of arguments.
class _PathData {
  _PathData(this._d);

  final String _d;
  int _i = 0;

  double _x = 0;
  double _y = 0;
  double _startX = 0;
  double _startY = 0;

  /// The reflection sources for the smooth `S` and `T` commands.
  double? _lastCubicX;
  double? _lastCubicY;
  double? _lastQuadX;
  double? _lastQuadY;

  List<SketchCommand> parse() {
    final List<SketchCommand> out = <SketchCommand>[];
    String? command;

    while (true) {
      _skip();
      if (_i >= _d.length) break;

      final String character = _d[_i];
      if (_isCommand(character)) {
        command = character;
        _i++;
      } else if (command == null) {
        throw const _Rejected();
      } else if (command == 'M') {
        // A repeated M is an implicit L, as the specification says.
        command = 'L';
      } else if (command == 'm') {
        command = 'l';
      } else if (command == 'Z' || command == 'z') {
        throw const _Rejected();
      }

      // The first command has to place the pen.
      if (out.isEmpty && command != 'M' && command != 'm') {
        throw const _Rejected();
      }
      out.addAll(_arguments(command));
      if (out.length > SketchIcon.maxCommands) throw const _Rejected();
    }
    return out;
  }

  List<SketchCommand> _arguments(String command) {
    final bool relative = command.toLowerCase() == command;
    final double ox = relative ? _x : 0;
    final double oy = relative ? _y : 0;

    switch (command.toUpperCase()) {
      case 'M':
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = _startX = x;
        _y = _startY = y;
        _clearReflections();
        return <SketchCommand>[SketchMoveTo(x, y)];
      case 'L':
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = x;
        _y = y;
        _clearReflections();
        return <SketchCommand>[SketchLineTo(x, y)];
      case 'H':
        final double x = _number() + ox;
        _x = x;
        _clearReflections();
        return <SketchCommand>[SketchLineTo(x, _y)];
      case 'V':
        final double y = _number() + oy;
        _y = y;
        _clearReflections();
        return <SketchCommand>[SketchLineTo(_x, y)];
      case 'C':
        final double x1 = _number() + ox;
        final double y1 = _number() + oy;
        final double x2 = _number() + ox;
        final double y2 = _number() + oy;
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = x;
        _y = y;
        _clearReflections();
        _lastCubicX = x2;
        _lastCubicY = y2;
        return <SketchCommand>[SketchCubicTo(x1, y1, x2, y2, x, y)];
      case 'S':
        final double x1 = 2 * _x - (_lastCubicX ?? _x);
        final double y1 = 2 * _y - (_lastCubicY ?? _y);
        final double x2 = _number() + ox;
        final double y2 = _number() + oy;
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = x;
        _y = y;
        _clearReflections();
        _lastCubicX = x2;
        _lastCubicY = y2;
        return <SketchCommand>[SketchCubicTo(x1, y1, x2, y2, x, y)];
      case 'Q':
        final double x1 = _number() + ox;
        final double y1 = _number() + oy;
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = x;
        _y = y;
        _clearReflections();
        _lastQuadX = x1;
        _lastQuadY = y1;
        return <SketchCommand>[SketchQuadraticTo(x1, y1, x, y)];
      case 'T':
        final double x1 = 2 * _x - (_lastQuadX ?? _x);
        final double y1 = 2 * _y - (_lastQuadY ?? _y);
        final double x = _number() + ox;
        final double y = _number() + oy;
        _x = x;
        _y = y;
        _clearReflections();
        _lastQuadX = x1;
        _lastQuadY = y1;
        return <SketchCommand>[SketchQuadraticTo(x1, y1, x, y)];
      case 'A':
        final double rx = _number();
        final double ry = _number();
        final double rotation = _number();
        final bool largeArc = _flag();
        final bool clockwise = _flag();
        final double x = _number() + ox;
        final double y = _number() + oy;
        _clearReflections();
        // A zero radius is a straight line, which is what SVG says it draws
        // and what Flutter's arc would choke on.
        if (rx == 0 || ry == 0) {
          _x = x;
          _y = y;
          return <SketchCommand>[SketchLineTo(x, y)];
        }
        _x = x;
        _y = y;
        return <SketchCommand>[
          SketchArcTo(
            rx: rx.abs(),
            ry: ry.abs(),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: clockwise,
            x: x,
            y: y,
          ),
        ];
      case 'Z':
        _x = _startX;
        _y = _startY;
        _clearReflections();
        return const <SketchCommand>[SketchClose()];
      default:
        throw const _Rejected();
    }
  }

  void _clearReflections() {
    _lastCubicX = null;
    _lastCubicY = null;
    _lastQuadX = null;
    _lastQuadY = null;
  }

  static bool _isCommand(String character) =>
      'MmLlHhVvCcSsQqTtAaZz'.contains(character);

  void _skip() {
    while (_i < _d.length &&
        (_d[_i] == ' ' || _d[_i] == ',' || _isWs(_d[_i]))) {
      _i++;
    }
  }

  static bool _isWs(String c) => c == '\n' || c == '\r' || c == '\t';

  /// One arc flag: a bare `0` or `1`, which may run straight into the next
  /// number.
  bool _flag() {
    _skip();
    if (_i >= _d.length) throw const _Rejected();
    final String character = _d[_i];
    if (character != '0' && character != '1') throw const _Rejected();
    _i++;
    return character == '1';
  }

  double _number() {
    _skip();
    final int start = _i;
    if (_i < _d.length && (_d[_i] == '-' || _d[_i] == '+')) _i++;

    bool seenDot = false;
    bool seenDigit = false;
    while (_i < _d.length) {
      final String c = _d[_i];
      if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        seenDigit = true;
        _i++;
      } else if (c == '.' && !seenDot) {
        // A second dot starts the *next* number: "1.5.5" is 1.5 then .5.
        seenDot = true;
        _i++;
      } else if ((c == 'e' || c == 'E') && seenDigit) {
        final int mark = _i;
        _i++;
        if (_i < _d.length && (_d[_i] == '-' || _d[_i] == '+')) _i++;
        if (_i >= _d.length || !_isDigit(_d[_i])) {
          _i = mark;
          break;
        }
        while (_i < _d.length && _isDigit(_d[_i])) {
          _i++;
        }
        break;
      } else {
        break;
      }
    }

    if (!seenDigit) throw const _Rejected();
    final double? value = double.tryParse(_d.substring(start, _i));
    if (value == null || !value.isFinite) throw const _Rejected();
    return value;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}
