import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The way in must not sit on top of the way out (spec §6.3, CLAUDE.md 6).
///
/// "Add recipe" floats over the library list. At three times the text on a
/// short desktop window it is 274pt wide and 72pt tall with its margin,
/// parked over the right-hand end of every row — which is exactly where the
/// delete a swipe uncovers lands. The delete was not merely hidden under it:
/// the hit test stopped at the floating button, so a tap on a visible,
/// enabled Delete opened the Add recipe sheet instead.
///
/// Dynamic type is to be *honoured*, not survived, so what is asserted here
/// is a real hit test rather than `findsOneWidget` — a button under another
/// button still exists, is still enabled, and still cannot be pressed.

/// The row the accessibility sweep uses: a title long enough to wrap several
/// times at large text, so the card is tall and its delete sits well down the
/// screen.
Recipe chilli() => aRecipe(
  id: 'r-chilli',
  title: 'Slow chilli with all the trimmings',
  servings: 4,
  sections: <RecipeSection>[
    aSection(
      id: 's1',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'ground beef',
          amount: 2,
          unit: Units.pound,
          sectionId: 's1',
        ),
      ],
      steps: <RecipeStep>[aStep('Brown the beef.', sectionId: 's1')],
    ),
  ],
);

Rect _rectOf(Element element) {
  final RenderBox box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Whether a tap at [at] is actually delivered to [element].
///
/// The hit path, not the widget tree: what is asked is whether the press
/// arrives, and something drawn over the top takes it first.
bool _tapReaches(WidgetTester tester, Element element, Offset at) {
  final RenderObject target = element.renderObject!;
  for (final HitTestEntry<HitTestTarget> entry
      in tester.hitTestOnBinding(at).path) {
    if (identical(entry.target, target)) return true;
  }
  return false;
}

/// What the tap landed on instead, so a failure names the thief.
String _whatTookIt(WidgetTester tester, Offset at) {
  for (final HitTestEntry<HitTestTarget> entry
      in tester.hitTestOnBinding(at).path) {
    if (entry.target case final RenderObject hit) {
      // The widget, where the render object still remembers which one built
      // it: "RenderParagraph" says far less than "Text("Add recipe")".
      if (hit.debugCreator case final DebugCreator creator) {
        return creator.element.widget.toString();
      }
      return hit.runtimeType.toString();
    }
  }
  return 'nothing';
}

void main() {
  // A short desktop window — macOS and Windows are shipping targets, and 500
  // points of height is an ordinary half-screen there. The sweep that found
  // this uses the same one.
  const Size shortWindow = Size(900, 500);

  for (final double scale in <double>[1.0, 2.0, 2.5, 3.0]) {
    testWidgets('a delete that is on screen can be pressed at text scale '
        '$scale', (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        size: shortWindow,
        textScale: scale,
        recipes: <Recipe>[chilli()],
      );
      await pumpFrames(tester);

      final ScrollableState list = tester.state(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final double extent = list.position.maxScrollExtent;

      // Uncover the delete, from a scroll position where the card is
      // comfortably on screen to swipe from.
      list.position.jumpTo(extent);
      await pumpFrames(tester, frames: 12);
      final Rect card = _rectOf(find.byType(RecipeCard).evaluate().first);
      await tester.dragFrom(
        Offset(card.center.dx, card.center.dy.clamp(80.0, 420.0)),
        const Offset(-200, 0),
      );
      await pumpFrames(tester, frames: 12);

      // Then walk the whole scroll, because a floating button covers a
      // different row at every offset. Anywhere the control is fully on the
      // glass and switched on it has to be pressable — "scroll somewhere else
      // first" is not a way to reach a button.
      //
      // "On the glass" is the list's own viewport, not the window: a row's
      // render box reports where it *would* be, so a row scrolled past the end
      // of the list still has coordinates, and they are not a place anybody
      // can press.
      for (double offset = 0; offset <= extent; offset += 20) {
        list.position.jumpTo(offset);
        await pumpFrames(tester, frames: 2);

        final RenderBox viewport = tester.renderObject<RenderBox>(
          find.byType(CustomScrollView),
        );
        final Rect visible = (Offset.zero & shortWindow).intersect(
          viewport.localToGlobal(Offset.zero) & viewport.size,
        );

        for (final Element element
            in find.widgetWithText(TextButton, 'Delete').evaluate()) {
          if ((element.widget as TextButton).onPressed == null) continue;
          final Rect where = _rectOf(element);
          if (!visible.contains(where.topLeft)) continue;
          if (!visible.contains(where.bottomRight)) continue;

          expect(
            _tapReaches(tester, element, where.center),
            isTrue,
            reason:
                'at text scale $scale, scrolled to $offset, the delete at '
                '$where is on screen and switched on, but the tap lands on '
                '${_whatTookIt(tester, where.center)}',
          );
        }
      }
    });
  }

  testWidgets('the pill is still the pill at an ordinary text size', (
    WidgetTester tester,
  ) async {
    // The cure is scoped to accessibility sizes on purpose. A floating button
    // over a list is the design at ordinary sizes and is not being changed —
    // this is here so that "dock it everywhere" cannot arrive quietly.
    await pumpHearthApp(
      tester,
      size: shortWindow,
      textScale: 1.0,
      recipes: <Recipe>[chilli()],
    );
    await pumpFrames(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Add recipe'), findsOneWidget);
  });

  testWidgets('and gives way to a bar at an accessibility one', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      size: shortWindow,
      textScale: 3.0,
      recipes: <Recipe>[chilli()],
    );
    await pumpFrames(tester);

    expect(
      find.byType(FloatingActionButton),
      findsNothing,
      reason: 'nothing may float over the rows at accessibility text sizes',
    );
    // Same words, same way in — only the shape changes (U05).
    expect(find.text('Add recipe'), findsOneWidget);
    await tester.tap(find.text('Add recipe'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('Write a recipe'), findsOneWidget);
  });

  testWidgets('the way in says what it is at the largest text', (
    WidgetTester tester,
  ) async {
    // The other half of the same defect: at 3x the label's line box is taller
    // than the pill Material draws it in, so the words the control exists to
    // show are clipped top and bottom.
    await pumpHearthApp(
      tester,
      size: shortWindow,
      textScale: 3.0,
      recipes: <Recipe>[chilli()],
    );
    await pumpFrames(tester);

    final Finder words = find.text('Add recipe');
    expect(words, findsOneWidget);

    final RenderBox label = tester.renderObject<RenderBox>(words);
    // The innermost Material is the button's own surface, whichever shape the
    // control is wearing.
    final RenderBox surface = tester.renderObject<RenderBox>(
      find.ancestor(of: words, matching: find.byType(Material)).first,
    );

    expect(
      label.size.height,
      lessThanOrEqualTo(surface.size.height),
      reason: 'the Add recipe label overflows the control that holds it',
    );
  });
}
