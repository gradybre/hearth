import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/hearth_marks.dart';
import 'package:hearth/domain/recipes/sketch_icon.dart';

/// Hearth's own drawings go through the same gate a recipe's does.
///
/// The whitelist in [SketchIcon] exists because a recipe's sketch is written
/// by a language model, and nothing here needs protecting from its author.
/// What the gate is worth to these is the opposite: it is the one check that
/// a mark will actually draw. A path with a typo in it fails the parse and
/// renders nothing at all, and nothing else in the app would say so — the
/// widget draws an empty box and the screen looks a little plainer than it
/// should.
void main() {
  for (final (name: String name, svg: String svg) in kHearthMarks) {
    test('$name is something the painter will draw', () {
      final SketchIcon? icon = SketchIcon.parse(svg);
      expect(icon, isNotNull, reason: '$name did not survive the whitelist');
      expect(
        icon!.shapes,
        isNotEmpty,
        reason: '$name parsed to a drawing with nothing in it',
      );
    });

    test('$name is drawn in line, not in fill', () {
      // A sketch is strokes. Any paint at all counts as a fill to the
      // parser, and the painter washes a filled shape at 16% — which on a
      // mark of this size turns a pot into a smudge.
      final SketchIcon icon = SketchIcon.parse(svg)!;
      expect(
        icon.shapes.every((SketchShape s) => !s.filled),
        isTrue,
        reason: '$name has a filled shape in it',
      );
    });

    test('$name fits the box it says it does', () {
      // The painter fits the viewBox the way `xMidYMid meet` would, so a
      // shape outside it is not clipped — it shrinks everything else to make
      // room, and the mark quietly gets smaller than its neighbours.
      final SketchIcon icon = SketchIcon.parse(svg)!;
      expect(icon.minX, greaterThanOrEqualTo(-1));
      expect(icon.minY, greaterThanOrEqualTo(-1));
    });
  }
}
