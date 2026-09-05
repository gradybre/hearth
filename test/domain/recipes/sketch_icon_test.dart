import 'package:hearth/domain/recipes/sketch_icon.dart';
import 'package:test/test.dart';

/// A plausible sketch of a bowl of soup, of the shape the model is asked for.
const String bowl =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.5">'
    '<path d="M3 11h18c0 5-4 9-9 9s-9-4-9-9z"/>'
    '<path d="M8 7c0-1 1-1 1-2s-1-1-1-2"/>'
    '<circle cx="15" cy="5" r="1"/>'
    '</svg>';

void main() {
  group('what a sketch may be', () {
    test('an ordinary line drawing comes through with its shapes', () {
      final SketchIcon? icon = SketchIcon.parse(bowl);

      expect(icon, isNotNull);
      expect(icon!.width, 24);
      expect(icon.height, 24);
      expect(icon.shapes, hasLength(3));
      expect(icon.shapes.whereType<SketchPath>(), hasLength(2));
      expect(icon.shapes.whereType<SketchCircle>(), hasLength(1));
    });

    test('the markup is kept exactly, because that is what gets stored', () {
      expect(SketchIcon.parse('  $bowl  ')!.markup, bowl);
    });

    test('every drawing element on the whitelist is accepted', () {
      final SketchIcon? icon = SketchIcon.parse(
        '<svg viewBox="0 0 24 24">'
        '<g stroke-width="2">'
        '<path d="M1 1L2 2"/>'
        '<circle cx="4" cy="4" r="2"/>'
        '<ellipse cx="6" cy="6" rx="3" ry="2"/>'
        '<line x1="0" y1="0" x2="9" y2="9"/>'
        '<polyline points="1,1 2,2 3,1"/>'
        '<polygon points="1,1 2,2 3,1"/>'
        '<rect x="1" y="1" width="4" height="4" rx="1"/>'
        '</g>'
        '</svg>',
      );

      expect(icon, isNotNull);
      expect(icon!.shapes, hasLength(7));
      // The group's stroke width reaches every child, which is the whole
      // point of allowing <g> at all.
      expect(icon.shapes.every((SketchShape s) => s.strokeWidth == 2), isTrue);
    });

    test('a fill is remembered as filled-or-not, never as a colour', () {
      // §6.1 ships light and dark from day one; an icon that baked in its own
      // colours would be wrong in one of them.
      final SketchIcon icon = SketchIcon.parse(
        '<svg viewBox="0 0 10 10">'
        '<circle cx="5" cy="5" r="2" fill="#ff0000"/>'
        '<circle cx="5" cy="5" r="4" fill="none"/>'
        '</svg>',
      )!;

      expect(icon.shapes.first.filled, isTrue);
      expect(icon.shapes.last.filled, isFalse);
    });

    test('an unfilled path is the default, so nothing becomes a blob', () {
      expect(
        SketchIcon.parse('<svg viewBox="0 0 10 10"><path d="M1 1L9 9"/></svg>')!
            .shapes
            .first
            .filled,
        isFalse,
      );
    });
  });

  group('what a sketch may not be', () {
    // Each of these is a real thing a model or an attacker could put in an
    // SVG, and each renders somewhere. A rejected answer means no icon — never
    // a half-sanitised one.
    const Map<String, String> hostile = <String, String>{
      'a script element':
          '<svg viewBox="0 0 24 24"><script>alert(1)</script>'
          '<path d="M1 1L2 2"/></svg>',
      'a foreignObject':
          '<svg viewBox="0 0 24 24"><foreignObject width="10" height="10">'
          '<b>hi</b></foreignObject></svg>',
      'an embedded image':
          '<svg viewBox="0 0 24 24"><image href="http://x/y.png"/></svg>',
      'a use reference': '<svg viewBox="0 0 24 24"><use href="#other"/></svg>',
      'an xlink href':
          '<svg viewBox="0 0 24 24"><a xlink:href="http://x">'
          '<path d="M1 1L2 2"/></a></svg>',
      'an event handler':
          '<svg viewBox="0 0 24 24" onload="alert(1)">'
          '<path d="M1 1L2 2"/></svg>',
      'an event handler on a shape':
          '<svg viewBox="0 0 24 24"><path d="M1 1L2 2" onclick="x()"/></svg>',
      'a data URI in a fill':
          '<svg viewBox="0 0 24 24">'
          '<path d="M1 1L2 2" fill="url(data:image/png;base64,AAAA)"/></svg>',
      'a javascript URI':
          '<svg viewBox="0 0 24 24"><path d="M1 1" fill="javascript:x"/></svg>',
      'an entity declaration':
          '<!DOCTYPE svg [<!ENTITY x "boom">]>'
          '<svg viewBox="0 0 24 24"><path d="M1 1L2 2"/></svg>',
      'a CDATA section':
          '<svg viewBox="0 0 24 24"><![CDATA[<script>x</script>]]>'
          '<path d="M1 1L2 2"/></svg>',
      'a style element':
          '<svg viewBox="0 0 24 24"><style>*{fill:red}</style>'
          '<path d="M1 1L2 2"/></svg>',
      'text content':
          '<svg viewBox="0 0 24 24"><text x="1" y="1">soup</text></svg>',
      'an animation':
          '<svg viewBox="0 0 24 24"><path d="M1 1L2 2">'
          '<animate attributeName="d"/></path></svg>',
      'an iframe': '<svg viewBox="0 0 24 24"><iframe src="http://x"/></svg>',
    };

    hostile.forEach((String what, String markup) {
      test('$what is refused', () {
        expect(SketchIcon.parse(markup), isNull);
        expect(SketchIcon.isValid(markup), isFalse);
      });
    });

    test('an unknown element is refused rather than skipped', () {
      // Skipping what it does not understand is how a sanitiser becomes a
      // bypass: it invites a guess about which half was the dangerous half.
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 24 24"><marker id="m"/>'
          '<path d="M1 1L2 2"/></svg>',
        ),
        isNull,
      );
    });

    test('an unknown attribute is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 24 24"><path d="M1 1L2 2" filter="url(#f)"/>'
          '</svg>',
        ),
        isNull,
      );
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 24 24"><path d="M1 1L2 2" style="fill:red"/>'
          '</svg>',
        ),
        isNull,
      );
    });

    test('an unquoted attribute value is refused', () {
      // Where a hand-written tokeniser and a real renderer most easily
      // disagree about where an attribute ends.
      expect(
        SketchIcon.parse('<svg viewBox=0 0 24 24><path d="M1 1"/></svg>'),
        isNull,
      );
    });

    test('anything but an svg at the root is refused', () {
      expect(SketchIcon.parse('<html><body>hi</body></html>'), isNull);
      expect(SketchIcon.parse('not markup at all'), isNull);
      expect(SketchIcon.parse(''), isNull);
      expect(SketchIcon.parse(null), isNull);
    });

    test('trailing rubbish after the root element is refused', () {
      expect(SketchIcon.parse('$bowl<script>alert(1)</script>'), isNull);
      expect(SketchIcon.parse('$bowl junk'), isNull);
    });

    test('an unclosed element is refused', () {
      expect(
        SketchIcon.parse('<svg viewBox="0 0 24 24"><g><path d="M1 1L2 2"/>'),
        isNull,
      );
    });

    test('an svg with no shapes in it is not an icon', () {
      expect(SketchIcon.parse('<svg viewBox="0 0 24 24"></svg>'), isNull);
    });

    test('a missing or nonsense viewBox is refused', () {
      expect(SketchIcon.parse('<svg><path d="M1 1L2 2"/></svg>'), isNull);
      expect(
        SketchIcon.parse('<svg viewBox="0 0 0 0"><path d="M1 1"/></svg>'),
        isNull,
      );
      expect(
        SketchIcon.parse('<svg viewBox="0 0 wide 24"><path d="M1 1"/></svg>'),
        isNull,
      );
    });
  });

  group('size', () {
    test('a sketch larger than the cap is refused, not truncated', () {
      final StringBuffer buffer = StringBuffer('<svg viewBox="0 0 24 24">');
      while (buffer.length < SketchIcon.maxMarkupLength) {
        buffer.write('<path d="M1 1L2 2C3 3 4 4 5 5"/>');
      }
      buffer.write('</svg>');

      expect(buffer.length, greaterThan(SketchIcon.maxMarkupLength));
      expect(SketchIcon.parse(buffer.toString()), isNull);
    });

    test('the cap is small enough to sit in a column, not a bucket', () {
      expect(SketchIcon.maxMarkupLength, lessThanOrEqualTo(8 * 1024));
      expect(bowl.length, lessThan(SketchIcon.maxMarkupLength));
    });

    test('a stroke width is clamped rather than allowed to paint a block', () {
      final SketchIcon icon = SketchIcon.parse(
        '<svg viewBox="0 0 24 24">'
        '<path d="M1 1L2 2" stroke-width="900"/>'
        '<path d="M1 1L2 2" stroke-width="0.0001"/>'
        '</svg>',
      )!;

      expect(icon.shapes.first.strokeWidth, SketchIcon.maxStrokeWidth);
      expect(icon.shapes.last.strokeWidth, SketchIcon.minStrokeWidth);
    });

    test('nesting beyond the depth limit is refused', () {
      final String deep =
          '<svg viewBox="0 0 24 24">${'<g>' * 12}<path d="M1 1L2 2"/>'
          '${'</g>' * 12}</svg>';
      expect(SketchIcon.parse(deep), isNull);
    });
  });

  group('path data', () {
    List<SketchCommand> commandsOf(String d) =>
        (SketchIcon.parse('<svg viewBox="0 0 24 24"><path d="$d"/></svg>')!
                    .shapes
                    .single
                as SketchPath)
            .commands;

    test('relative commands are resolved to absolute ones', () {
      final List<SketchCommand> commands = commandsOf('m1 1l2 3');

      expect((commands[0] as SketchMoveTo).x, 1);
      expect((commands[1] as SketchLineTo).x, 3);
      expect((commands[1] as SketchLineTo).y, 4);
    });

    test('the H and V shorthands keep the other coordinate', () {
      final List<SketchCommand> commands = commandsOf('M2 3H8V9');

      expect((commands[1] as SketchLineTo).x, 8);
      expect((commands[1] as SketchLineTo).y, 3);
      expect((commands[2] as SketchLineTo).x, 8);
      expect((commands[2] as SketchLineTo).y, 9);
    });

    test('a repeated argument set repeats the command', () {
      expect(commandsOf('M0 0 L1 1 2 2 3 3'), hasLength(4));
    });

    test('a repeated moveto argument set becomes a lineto, as SVG says', () {
      final List<SketchCommand> commands = commandsOf('M0 0 1 1');

      expect(commands[0], isA<SketchMoveTo>());
      expect(commands[1], isA<SketchLineTo>());
    });

    test('a smooth curve reflects the previous control point', () {
      final List<SketchCommand> commands = commandsOf(
        'M0 0C1 1 2 2 3 3S5 5 6 6',
      );
      final SketchCubicTo smooth = commands[2] as SketchCubicTo;

      // Reflected through the end of the first curve: 2*3 - 2 = 4.
      expect(smooth.x1, 4);
      expect(smooth.y1, 4);
    });

    test('two numbers run together by a second dot are read as two', () {
      // "1.5.5" is 1.5 followed by .5 — a real quirk of the grammar, and one
      // a naive split on whitespace gets silently wrong.
      final List<SketchCommand> commands = commandsOf('M1.5.5L2 2');

      expect((commands.first as SketchMoveTo).x, 1.5);
      expect((commands.first as SketchMoveTo).y, 0.5);
    });

    test('arc flags may run into the number after them', () {
      final List<SketchCommand> commands = commandsOf('M0 0a5 5 0 011 1');
      final SketchArcTo arc = commands[1] as SketchArcTo;

      expect(arc.largeArc, isFalse);
      expect(arc.clockwise, isTrue);
      expect(arc.x, 1);
      expect(arc.y, 1);
    });

    test('an arc with a zero radius becomes the straight line SVG says', () {
      expect(commandsOf('M0 0A0 0 0 0 1 5 5')[1], isA<SketchLineTo>());
    });

    test('close returns the pen to the start of the subpath', () {
      final List<SketchCommand> commands = commandsOf('M2 2L8 8Zl1 1');

      expect(commands[2], isA<SketchClose>());
      expect((commands[3] as SketchLineTo).x, 3);
    });

    test('a path that does not start by placing the pen is refused', () {
      expect(
        SketchIcon.parse('<svg viewBox="0 0 9 9"><path d="L1 1"/></svg>'),
        isNull,
      );
    });

    test('a path with a letter that is not a command is refused', () {
      expect(
        SketchIcon.parse('<svg viewBox="0 0 9 9"><path d="M1 1 X9 9"/></svg>'),
        isNull,
      );
    });

    test('an empty path is refused rather than drawn as nothing', () {
      expect(
        SketchIcon.parse('<svg viewBox="0 0 9 9"><path d=""/></svg>'),
        isNull,
      );
    });
  });

  group('transforms', () {
    SketchTransform transformOf(String transform) => SketchIcon.parse(
      '<svg viewBox="0 0 24 24"><g transform="$transform">'
      '<path d="M1 1L2 2"/></g></svg>',
    )!.shapes.single.transform;

    test('translate and scale are read', () {
      expect(
        transformOf('translate(3 4)'),
        const SketchTransform(1, 0, 0, 1, 3, 4),
      );
      expect(transformOf('scale(2)'), const SketchTransform(2, 0, 0, 2, 0, 0));
    });

    test('nested groups compose outer-first', () {
      final SketchTransform transform = SketchIcon.parse(
        '<svg viewBox="0 0 24 24">'
        '<g transform="translate(10 0)"><g transform="scale(2)">'
        '<path d="M1 1L2 2"/></g></g></svg>',
      )!.shapes.single.transform;

      expect(transform, const SketchTransform(2, 0, 0, 2, 10, 0));
    });

    test('a transform function this does not understand is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 24 24"><g transform="skewX(20)">'
          '<path d="M1 1L2 2"/></g></svg>',
        ),
        isNull,
      );
    });

    test('rubbish between transform functions is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 24 24"><g transform="translate(1 1) oops">'
          '<path d="M1 1L2 2"/></g></svg>',
        ),
        isNull,
      );
    });
  });

  group('refusing cheaply', () {
    /// A transform value of nothing but letters, filling the 4 KB cap.
    ///
    /// It is refused either way. What matters is the cost of refusing it: an
    /// unanchored `([a-zA-Z]+)\s*\(…\)` swept with `allMatches` retries the
    /// greedy run from every start position, which is quadratic — 3,900
    /// letters measured at 283 ms on the machine this was written on, against
    /// 7 ms for 500.
    String lettersInATransform(int letters) =>
        '<svg viewBox="0 0 24 24"><g transform="${'a' * letters}">'
        '<path d="M1 1L2 2"/></g></svg>';

    test('a transform value of attacker size is refused in bounded time', () {
      // This is not a micro-optimisation. `SketchIcon.isValid` runs on every
      // recipe row of every pull, on the UI isolate, with no cache, and the
      // same parse runs inside `build()` for anything outside the widget's
      // cache — so a hundred such rows froze the app for about half a minute.
      final String hostile = lettersInATransform(3900);
      expect(hostile.length, lessThanOrEqualTo(SketchIcon.maxMarkupLength));

      const int rows = 50;
      final Stopwatch watch = Stopwatch()..start();
      for (int i = 0; i < rows; i++) {
        expect(SketchIcon.parse(hostile), isNull);
      }
      watch.stop();

      // Fifty rows took about fourteen seconds while the scan was quadratic
      // and take single-digit milliseconds now. One second sits far above the
      // noise of a loaded CI machine and far below anything quadratic.
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('the cost of refusing grows with the input, not with its square', () {
      // The bound above catches a regression that is slow everywhere. This
      // catches one that is merely quadratic, on a machine fast enough to
      // hide it: four times the input may cost a few times more, never
      // sixteen.
      int microsecondsFor(int letters) {
        final String document = lettersInATransform(letters);
        final Stopwatch watch = Stopwatch()..start();
        // Enough repetitions that each measurement is tens of milliseconds,
        // where a loaded machine's noise cannot swing the ratio.
        for (int i = 0; i < 500; i++) {
          SketchIcon.parse(document);
        }
        return watch.elapsedMicroseconds;
      }

      // Warm the parser up so the first measurement is not paying for JIT.
      microsecondsFor(200);
      final int small = microsecondsFor(500);
      final int large = microsecondsFor(2000);

      expect(large, lessThan(small * 8));
    });
  });

  group('numbers that are only finite one at a time', () {
    // Every value below parses as a finite double on its own. Composing them
    // does not, and a NaN or an infinity reaching Skia is Skia's decision to
    // make rather than this file's — the likely outcome is a blank icon, but
    // "validated" has to mean the geometry is drawable, not that each number
    // was individually well formed.
    test('a rotation whose cosine is not a number is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10">'
          '<circle cx="5" cy="5" r="2" transform="rotate(1e308)"/></svg>',
        ),
        isNull,
      );
    });

    test('two scales that multiply to infinity are refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="2" '
          'transform="scale(1e300) scale(1e300)"/></svg>',
        ),
        isNull,
      );
    });

    test('two matrices that multiply to infinity are refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="2" '
          'transform="matrix(1e300 0 0 1e300 0 0) '
          'matrix(1e300 0 0 1e300 0 0)"/></svg>',
        ),
        isNull,
      );
    });

    test('a rotation about a centre off in the far distance is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="2" '
          'transform="rotate(45 1e308 1e308)"/></svg>',
        ),
        isNull,
      );
    });

    test('a relative path step that overflows to infinity is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10">'
          '<path d="M1e308 1e308l1e308 1e308"/></svg>',
        ),
        isNull,
      );
    });

    test('a radius whose diameter is infinite is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10">'
          '<ellipse cx="5" cy="5" rx="1e308" ry="2"/></svg>',
        ),
        isNull,
      );
    });

    test('an ordinary drawing sits nowhere near the coordinate cap', () {
      // The cap is what makes "finite after composition" hold rather than be
      // checked in six places and missed in a seventh. It has to be far
      // enough away that no real sketch can trip on it.
      expect(SketchIcon.maxCoordinate, greaterThanOrEqualTo(1e5));
      expect(SketchIcon.parse(bowl), isNotNull);
    });
  });

  group('closing tags', () {
    // Element names are lowercased when they are opened, so the closing tag
    // has to be read the same way rather than matched as a literal string.
    // It failed closed, so it was never a hole — but an ordinary answer in
    // capitals yielded no icon at all, and the asymmetry is what a later edit
    // gets backwards.
    test('an element opened and closed in capitals is drawn', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><PATH d="M1 1L2 2"></PATH></svg>',
        ),
        isNotNull,
      );
    });

    test('the space XML allows before the bracket is drawn', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><path d="M1 1L2 2"></path ></svg>',
        ),
        isNotNull,
      );
    });

    test('a closing tag naming another element is still refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><path d="M1 1L2 2"></circle></svg>',
        ),
        isNull,
      );
    });

    test('a closing tag with an attribute on it is refused', () {
      expect(
        SketchIcon.parse(
          '<svg viewBox="0 0 10 10"><path d="M1 1L2 2"></path fill="red">'
          '</svg>',
        ),
        isNull,
      );
    });
  });

  group('reading an untrusted field', () {
    test('anything that is not a string is simply no icon', () {
      // This is the field the whole change calls untrusted, and it arrives in
      // a map of `Object?`. A cast that throws here takes down the entire
      // pull, not just the picture.
      expect(SketchIcon.validated(42), isNull);
      expect(SketchIcon.validated(null), isNull);
      expect(SketchIcon.validated(<String>['<svg/>']), isNull);
    });

    test('markup that survives the gate comes back as markup', () {
      expect(SketchIcon.validated(bowl), bowl);
      expect(SketchIcon.validated('  $bowl  '), bowl);
    });

    test('markup that does not survive the gate is no icon', () {
      expect(
        SketchIcon.validated('<svg viewBox="0 0 10 10"><script/></svg>'),
        isNull,
      );
    });
  });
}
