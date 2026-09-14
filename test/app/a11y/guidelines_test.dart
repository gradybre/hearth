import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/data/adapters/thermostat.dart';
import 'package:hearth/domain/house/thermostat.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fake_auth.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

/// The §6.3 baseline, checked by machine rather than by eye.
///
/// Three questions, on every screen the app has: is every tappable thing big
/// enough to hit, does it carry a label a screen reader can read, and does the
/// text clear WCAG contrast against what is behind it. Written as a sweep
/// because the baseline is not optional and a per-screen habit is how it rots.
///
/// The first two are the guidelines the framework ships. The third was too,
/// and is now [expectTextContrast] instead — `textContrastGuideline` guesses
/// the text's colour out of the pixels and guesses differently on a Mac and on
/// Linux, which made this suite green here and red on CI. That function says
/// what it does instead, and why the change widens the check rather than
/// loosening it.
///
/// **It used to reach four screens.** It tapped each of the four Nutrition
/// tabs and a handful of hand-written journeys past them, which is most of
/// thirty screens unchecked — the six settings pages, the editors, the
/// library-maintenance lists, the thermostat, every sheet. A guideline check
/// that covers a seventh of the app is decoration.
///
/// So it walks two lists now, and they are two lists on purpose:
///
///  * [sweptSurfaces] — everything the app puts *over* a screen. It is already
///    the declared registry of sheets and dialogs, `every_surface_is_swept_test`
///    fails when something in `lib/` opens one it does not mention, and the
///    text-scaling sweep walks the same list. Writing a second copy here would
///    be a second list to forget to add to, which is the exact failure that
///    file was written to end.
///  * [_destinations] below — everything the app *pushes*: a route, a screen
///    with its own app bar. No registry declares those, and the guard behind
///    `sweptSurfaces` cannot invent one, because it recognises a sheet by the
///    call that opens it and a `context.push` is not that call. So they are
///    written out here, beside the checks that read them.
///
/// Both lists, in both themes. Dark is where contrast breaks: a palette tuned
/// on paper-cream does not survive being inverted for free.
///
/// The fixture is the flow sweep's, deliberately: the [sweptSurfaces]
/// callbacks name the food they expect — this recipe, a Chopt menu row, a
/// shopping list with a line on it — and a journey that arrives somewhere else
/// sweeps nothing while reporting success.
const String _recipeTitle = 'Slow chilli with all the trimmings';

void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: _recipeTitle,
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
        // A step, so cook-along has something to cook along with. Without one
        // the screen says so and every control on it goes away — which would
        // pass this check by having nothing left to check.
        steps: <RecipeStep>[
          aStep('Brown the beef, then braise it.', sectionId: 's1'),
        ],
      ),
    ],
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o1',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 160, proteinG: 15, carbG: 8, fatG: 8),
      ),
    ],
  );

  /// One restaurant, one row, so the eat-out builder has a menu to draw.
  Food menuItem() => aFood(
    'Harvest Bowl',
    id: 'f-chopt-harvest',
    brand: 'Chopt',
    source: FoodSource.restaurant,
    menuGroup: 'Warm bowls',
    menuOrder: 1,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o-bowl',
        label: '1 bowl',
        amount: Quantity.of(1, Units.item),
        macros: const Macros(kcal: 690, proteinG: 26, carbG: 78, fatG: 30),
      ),
    ],
  );

  MealPlanEntry breakfast() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 1,
  );

  const List<String> tabs = <String>['Recipes', 'Plan', 'Shopping', 'Foods'];

  const Size phone = Size(390, 844);
  const Size desktop = Size(900, 500);

  Future<void> open(
    WidgetTester tester,
    Brightness brightness, {
    Size size = phone,
    double textScale = 1.0,
    LaunchTarget? launchTarget,
    bool signedIn = false,
    ThermostatGateway? thermostat,
  }) => pumpHearthApp(
    tester,
    size: size,
    recipes: <Recipe>[chilli()],
    foods: <Food>[yoghurt(), menuItem()],
    // A shopping list with something on it: the list screen has two shapes,
    // and `Manage list` — which one of the swept surfaces opens — exists only
    // in the one that has something to shop for.
    shoppingLines: <ShoppingLine>[
      ShoppingLine(
        key: 'ground-beef',
        name: 'Ground beef',
        planned: <Quantity>[Quantity.of(2, Units.pound)],
        storeTag: 'Costco',
      ),
    ],
    entries: <MealPlanEntry>[breakfast()],
    // A week with meals in it. An empty one is seven rows of nothing, which
    // is not the screen anybody has to read in the dark.
    weekEntries: <DateTime, List<MealPlanEntry>>{
      for (final DateTime day in weekOf(dayKey(DateTime.now())))
        day: <MealPlanEntry>[breakfast()],
    },
    targets: const MacroTargets(
      kcal: 2200,
      proteinG: 170,
      carbG: 200,
      fatG: 70,
    ),
    textScale: textScale,
    brightness: brightness,
    launchTarget: launchTarget,
    thermostat: thermostat,
    // A real address and a real share code, where the destination needs them.
    // The harness signs in as `LocalAuthGateway.account`, which has neither —
    // so with it the account page hides the password-reset row and the
    // cook-together page hides the code and its copy button, and three of the
    // most control-dense things in Settings were unreachable by any sweep.
    extraOverrides: <Object>[
      if (signedIn)
        authGatewayProvider.overrideWithValue(
          FakeAuthGateway(signedIn: FakeAuthGateway.anAccount),
        ),
    ],
  );

  /// The three questions, against whatever is on screen.
  ///
  /// [where] is carried into the failure, because a sweep that says only
  /// "tap target too small" leaves you to find which of thirty screens it
  /// meant.
  Future<void> check(WidgetTester tester, String where) async {
    // Big enough to hit — a 44pt target is the difference between logging a
    // meal one-handed in a kitchen and not.
    //
    // iOS only, deliberately. Android's guideline asks for 48, and Hearth
    // ships iOS, macOS and Windows (CLAUDE.md) — growing every button in the
    // app by four points to satisfy a platform it does not run on would be
    // the guideline choosing the design language.
    await expectLater(
      tester,
      meetsGuideline(iOSTapTargetGuideline),
      reason: 'a tap target on $where is under 44 points',
    );
    // And named, so VoiceOver reads something other than "button".
    await expectLater(
      tester,
      meetsGuideline(labeledTapTargetGuideline),
      reason: 'something tappable on $where has no label',
    );
    // And readable against what is behind it. Measured here rather than by
    // `textContrastGuideline`, for the reason [expectTextContrast] gives.
    await expectTextContrast(tester, where);
  }

  for (final Brightness brightness in Brightness.values) {
    final String theme = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('every tap target is reachable and labelled in $theme', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, brightness);
      await pumpFrames(tester);

      for (final String tab in tabs) {
        await tester.tap(find.text(tab).last);
        await pumpFrames(tester, frames: 10);

        await expectLater(
          tester,
          meetsGuideline(iOSTapTargetGuideline),
          reason: 'a tap target on the $tab tab is under 44 points',
        );
        await expectLater(
          tester,
          meetsGuideline(labeledTapTargetGuideline),
          reason: 'something tappable on the $tab tab has no label',
        );
      }
      handle.dispose();
    });

    testWidgets('text meets WCAG AA contrast in $theme', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, brightness);
      await pumpFrames(tester);

      for (final String tab in tabs) {
        await tester.tap(find.text(tab).last);
        await pumpFrames(tester, frames: 10);
        await expectTextContrast(tester, 'the $tab tab');
      }
      handle.dispose();
    });
  }

  group('the shell, where the sweep had only ever been pumped one way', () {
    testWidgets('the home screen on a desk, at the largest text', (
      WidgetTester tester,
    ) async {
      // A desktop window at 3x is where the shell's own chrome grows: nothing
      // in this sweep had ever been pumped anywhere but a phone at 1x.
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(
        tester,
        Brightness.light,
        size: desktop,
        textScale: 3.0,
        launchTarget: LaunchTarget.home,
      );
      await pumpFrames(tester);

      await check(tester, 'the home screen on a desk at 3x');
      handle.dispose();
    });

    testWidgets('and the sidebar beside a section, at the largest text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await open(tester, Brightness.light, size: desktop, textScale: 3.0);
      await pumpFrames(tester);

      await check(tester, 'the sidebar at 3x');
      handle.dispose();
    });
  });

  group('every sheet and dialog the app can put over a screen', () {
    // The list is `swept_surfaces.dart`'s, not a copy of it. That file is the
    // *knowing* — a guard reads `lib/` and fails when something opens a sheet
    // it does not mention — and this is one more kind of *walking* over it,
    // beside the text-scaling sweep that was its first caller.
    for (final Brightness brightness in Brightness.values) {
      final String theme = brightness == Brightness.light ? 'light' : 'dark';

      for (final SweptSurface surface in sweptSurfaces) {
        testWidgets('${surface.name} in $theme', (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await open(tester, brightness);
          await pumpFrames(tester);

          final SweepTools tools = SweepTools(tester);
          await surface.open(tester, tools);

          // Arrived, before anything is claimed about the guidelines: three
          // guidelines pass trivially on a screen the journey never left.
          expect(
            surface.arrived,
            findsWidgets,
            reason: '${surface.name} never opened in $theme',
          );
          await check(tester, '${surface.name} in $theme');
          handle.dispose();
        });
      }
    }
  });

  group('every screen the app can push', () {
    for (final Brightness brightness in Brightness.values) {
      final String theme = brightness == Brightness.light ? 'light' : 'dark';

      for (final _Destination destination in _destinations) {
        testWidgets('${destination.name} in $theme', (
          WidgetTester tester,
        ) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await open(
            tester,
            brightness,
            launchTarget: destination.launchTarget,
            signedIn: destination.signedIn,
            thermostat: destination.thermostat,
          );
          await pumpFrames(tester);

          if (destination.open case final _Journey journey) {
            await journey(tester, SweepTools(tester));
          }

          expect(
            destination.arrived,
            findsWidgets,
            reason: '${destination.name} never opened in $theme',
          );
          await check(tester, '${destination.name} in $theme');
          handle.dispose();
        });
      }
    }
  });
}

/// Every piece of text painted on [tester]'s screen, against what is behind it.
///
/// **Why this is not [textContrastGuideline].** The framework's auditor samples
/// each label's paint bounds *inflated by four points*, histograms those
/// pixels, splits them at the mean lightness and takes the most frequent colour
/// from each half. Neither half is guaranteed to be the text: four points
/// outside a small label reaches a card border or a field fill, and inside it
/// the glyph edges are a spread of anti-aliased blends that can out-number the
/// glyph *cores*. When both halves come back as something other than the ink,
/// the ratio it reports is between two colours the designer never paired.
///
/// That is not hypothetical. This sweep was green on macOS and red on Linux CI
/// with seven failures, and all seven reported a pair like this:
///
/// ```
/// the thermostat in light   "House"   1.28:1   #F6EFE1 / #DDD4C6
/// seasonings … in light     "basil"   1.96:1   #ECE2D0 / #ACA294
/// the day's targets, light  "170"     3.04:1   #E1D4BA / #817666
/// ```
///
/// In every one of the seven the lighter colour is an exact Hearth surface
/// token and the darker one is **not a Hearth colour at all** — `#DDD4C6`,
/// `#ACA294` and `#817666` are partial blends of cocoa over cream, which is to
/// say anti-aliasing. Measured properly those three are 5.89:1, 12.29:1 and
/// 10.77:1. Nothing was wrong with the screens; what differed was how many
/// pixels the rasteriser leaves at the glyph's full strength, and that is a
/// property of the font engine — CoreText on a Mac, FreeType on the CI box.
/// A check whose verdict moves with the host's text rendering is not measuring
/// the palette.
///
/// **What this asks instead.** For each run of text actually painted: the
/// colour it is drawn in, taken from the render tree, against the commonest
/// colour inside its own **tight** line box, taken from the rendered frame.
/// No inflation, so nothing outside the text votes; and the foreground is
/// known rather than guessed at, so anti-aliasing cannot stand in for it.
/// Both halves are then platform-independent — a text colour comes from the
/// theme, and the ground is a flat fill whose commonest pixel does not depend
/// on glyph shape.
///
/// **It is a wider net than the one it replaces, not a narrower one.** The
/// auditor only reaches text that is in the semantics tree *and* is matched by
/// `find.text` *and* hit-tests to its own glyphs; this walks the render tree,
/// so a chip's label, a field's value and the text inside a merged row are all
/// measured now. The thermostat's three mode chips are the plainest example —
/// cream on terracotta, and never once looked at before this. Across the 78
/// cases it measures about 1,300 runs of text, seventeen to a screen.
///
/// The surface that had to be exempted from the old auditor, and the two
/// headings measured by hand in its place, are gone with it. **There is no
/// exemption list.** If one ever starts, that is the signal to look at the
/// screens rather than lengthen the list — a check that grows exceptions
/// faster than it grows coverage has stopped being a check.
///
/// **What it does not look at**, said plainly:
///
///  * text the frame does not hold at this instant — scrolled out of its list,
///    or behind the sheet in front of it. One frame per screen sees one frame
///    per screen, and the sheet gets its own case.
///  * text that something else is drawn over ([_isUncovered]). A floating
///    button passing over a list is doing its job, and the row beneath it is
///    not a question about the palette.
///  * a control that is switched off ([_inactiveAreas]). WCAG exempts an
///    inactive component and the framework's auditor skips one too.
///  * text over a photograph or a gradient. The commonest pixel in the box is
///    a fair ground for a flat fill and a poor one for a picture. No screen
///    this sweep visits has one; the day one does, this needs a worst-pixel
///    rule rather than to quietly go on answering.
Future<void> expectTextContrast(WidgetTester tester, String where) async {
  final RenderView view = tester.binding.renderViews.first;

  // Two coordinate spaces, and they are only the same one by a single line in
  // the harness. `getTransformTo(null)` answers in **logical** pixels, while
  // `RenderView.paintBounds` is `size * devicePixelRatio` and the image below
  // comes out that big — **physical** pixels. `app_harness.dart` pins the
  // ratio at 1.0, so today they coincide; at 3.0 the same rectangle covers a
  // ninth of the glyphs and sits at a third of their offset, which is a region
  // of whatever the text happens to be above. That would not go red — the
  // foreground is read from the widget tree, so a washed-out label still
  // reports its own colour against *some* background and a negative test still
  // passes, while the check answers about the wrong pixels. So it is
  // converted rather than assumed.
  final double scale = view.configuration.devicePixelRatio;

  late int width;
  late int height;
  final ByteData? pixels = await tester.binding.runAsync<ByteData?>(() async {
    final ui.Image image = await (view.debugLayer! as OffsetLayer).toImage(
      view.paintBounds,
    );
    width = image.width;
    height = image.height;
    final ByteData? data = await image.toByteData();
    image.dispose();
    return data;
  });

  // WCAG exempts an inactive control, and so does the framework's auditor
  // ("skip disabled nodes, as they are not required to pass contrast check").
  // Cook-along's Back and Next are the app's example: at either end of a
  // recipe one of them is dead, drawn at Material's 38% and reading 2.20:1,
  // and that is the whole point of the state.
  final List<Rect> inactive = _inactiveAreas(tester, scale);

  final List<String> failures = <String>[];
  int measured = 0;

  for (final _PaintedText text in _textOnScreen(view)) {
    final Rect logical = MatrixUtils.transformRect(
      text.box.getTransformTo(null),
      text.box.paintBounds,
    );
    if (!_isUncovered(tester, text.box, logical)) continue;
    // Contained by a disabled control, not merely touching one. The rule is
    // "a disabled control's own text", and a box that overlaps a disabled
    // rect at one corner is a *neighbouring* label — which `overlaps` would
    // drop from the sweep with nothing to say it had. Today both spellings
    // skip the same ten runs (cook-along's dead Back and Next, with their
    // icons, in both themes); this one goes on meaning that when a screen
    // grows a disabled region with something else inside it.
    if (inactive.any(
      (Rect rect) =>
          rect.inflate(1).contains(logical.topLeft) &&
          rect.inflate(1).contains(logical.bottomRight),
    )) {
      continue;
    }
    final Rect bounds = Rect.fromLTRB(
      logical.left * scale,
      logical.top * scale,
      logical.right * scale,
      logical.bottom * scale,
    );

    final Map<int, int> histogram = <int, int>{};
    for (int y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
      for (int x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        final int rgba = pixels!.getUint32((y * width + x) * 4);
        histogram[rgba] = (histogram[rgba] ?? 0) + 1;
      }
    }
    // Nothing of it is inside the frame — scrolled out, or clipped away.
    if (histogram.isEmpty) continue;

    // Every colour this paragraph paints *with* is disqualified as the colour
    // it is painted *on*. Without that, a heading heavy enough to cover more
    // of its own line box than the ground does reports itself as its own
    // background and comes back at 1.00:1 — which is what the framework's
    // auditor does to a 24pt title, and is a statement about type weight
    // rather than about contrast.
    final Set<int> inks = <int>{
      for (final _Ink ink in text.inks)
        if (ink.colour case final Color colour) _rgba(colour),
    };
    for (final int ink in inks) {
      histogram.remove(ink);
    }
    if (histogram.isEmpty) {
      // Every pixel in the line box is one of the colours the text itself is
      // drawn in: there is nothing behind it to read it against, which is what
      // invisible text looks like from here.
      failures.add(
        '${text.describe()} has nothing behind it but its own ink '
        '(${inks.map((int c) => _hex(_colour(c))).join(', ')})',
      );
      continue;
    }

    final Color ground = _colour(
      histogram.entries
          .reduce(
            (MapEntry<int, int> a, MapEntry<int, int> b) =>
                a.value >= b.value ? a : b,
          )
          .key,
    );

    for (final _Ink ink in text.inks) {
      measured++;
      if (ink.colour == null) {
        failures.add(
          '${text.describe()} is painted with no colour in its style, so '
          'there is nothing to measure it by',
        );
        continue;
      }
      // A partly transparent ink is the blend of it over the ground, not the
      // opaque colour: `computeLuminance` ignores alpha and would report a
      // faded label as if it were at full strength.
      final Color ink0 = Color.alphaBlend(ink.colour!, ground);
      // WCAG's own formula: (L1 + 0.05) / (L2 + 0.05), lighter over darker.
      final double a = ink0.computeLuminance() + 0.05;
      final double b = ground.computeLuminance() + 0.05;
      final double ratio = a > b ? a / b : b / a;
      // A tie counts as passing, but only a tie: both colours here are exact
      // — the ink comes from the render tree and the ground is a flat theme
      // token — so the ratio is the same number on every platform, and the
      // only slack it needs is the last bits of a double. 4.5 means 4.5.
      if (ratio >= ink.target - 1e-9) continue;
      failures.add(
        '${text.describe()} is ${_hex(ink.colour!)} on ${_hex(ground)} — '
        '${ratio.toStringAsFixed(2)}:1, under ${ink.target}:1 '
        '(${ink.why})',
      );
    }
  }

  // A sweep that measured nothing passes, and a screen that drew nothing is
  // not what any of these journeys is for.
  expect(
    measured,
    greaterThan(0),
    reason: 'no text was measured on $where — did the journey arrive?',
  );
  expect(
    failures,
    isEmpty,
    reason:
        'text on $where is under WCAG contrast:\n  ${failures.join('\n  ')}',
  );
}

/// One run of text, and the threshold it has to clear.
@immutable
class _Ink {
  const _Ink({required this.colour, required this.target, required this.why});

  /// Null where the painted style carries no colour at all, which is a failure
  /// rather than a skip: nothing in `hearth_typography.dart` leaves one unset,
  /// so a null here means text is being painted in whatever the engine's
  /// default happens to be.
  final Color? colour;

  /// 4.5 for body text, 3.0 for large or bold text and for icon glyphs.
  final double target;

  /// Which of WCAG's rules that threshold came from, for the failure to say.
  final String why;
}

/// A paragraph or a field's value, with every colour it is drawn in.
@immutable
class _PaintedText {
  const _PaintedText({
    required this.box,
    required this.text,
    required this.inks,
  });

  final RenderBox box;
  final String text;
  final List<_Ink> inks;

  String describe() => '"${text.replaceAll('\n', ' / ')}"';
}

/// Whether nothing is drawn over [box] — not over any part of it.
///
/// The topmost thing hit at a point has to be [box] itself or something it
/// sits inside. A label under a pushed screen, or behind a sheet's barrier,
/// hits that screen or that barrier instead — neither is in its lineage — and
/// is not on the glass to be read.
///
/// **Five points, not one.** A floating button is *supposed* to pass over the
/// content, and at the largest text the recipe list's delete button ends up
/// three-quarters under the "Add recipe" button. Its centre is clear, so a
/// one-point test measures it and takes the button's terracotta as its
/// background: cocoa on terracotta, 1.01:1, a failure about occlusion wearing
/// the clothes of a failure about palette. Something partly hidden is not a
/// contrast question at all, so it is left alone.
///
/// Deliberately not `Finder.hitTestable`, which the framework's auditor uses
/// and which asks the stricter question of whether the *text* is in the hit
/// path. A `Chip` never hit-tests its own label (`_RenderChip.hitTestChildren`
/// offers only the delete icon), so every chip in the app — the thermostat's
/// mode row among them, cream on terracotta — is invisible to that question
/// while being perfectly visible on screen.
bool _isUncovered(WidgetTester tester, RenderBox box, Rect logical) {
  if (!box.attached || !box.hasSize || box.size.isEmpty) return false;
  if (logical.isEmpty || logical.hasNaN) return false;
  final Set<RenderObject> lineage = <RenderObject>{};
  for (RenderObject? node = box; node != null; node = node.parent) {
    lineage.add(node);
  }
  // The middle of each edge rather than the corners, inset by a point. A
  // rounded button's label reaches the full width of its inside, so its
  // corners sit outside the curve and hit whatever is behind the button —
  // which would drop every floating action button's own label as covered.
  final Rect inner = logical.deflate(1);
  final Size view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final Rect screen = Offset.zero & view;
  bool clear(Offset at, {required bool edge}) {
    // Off the edge of the window. A *corner* may be: a label flush to the edge
    // would otherwise be dropped for being at it. Its middle may not — text
    // whose middle is not on the glass is not being read, and sampling the
    // sliver of it that is on screen is how a row scrolled almost out of a
    // list came to be measured against the scrim of the dialog in front of it.
    if (!screen.contains(at)) return edge;
    final HitTestResult result = tester.hitTestOnBinding(at);
    // The first *render object* in the path, not the first entry: a
    // `RenderParagraph` hands its `TextSpan` to the hit test as well, so the
    // topmost entry is routinely an annotation rather than a box — and a check
    // that read `path.first` alone found no paragraph anywhere and passed
    // every screen by measuring nothing at all.
    for (final HitTestEntry<HitTestTarget> entry in result.path) {
      if (entry.target is! RenderObject) continue;
      return lineage.contains(entry.target);
    }
    return false;
  }

  return clear(inner.center, edge: false) &&
      clear(inner.centerLeft, edge: true) &&
      clear(inner.centerRight, edge: true) &&
      clear(inner.topCenter, edge: true) &&
      clear(inner.bottomCenter, edge: true);
}

/// Where the screen has a control that is switched off.
///
/// Read off the compiled semantics tree, which is where "disabled" is actually
/// recorded — the render tree only knows it as a colour. Returned in logical
/// pixels, the space [_isUncovered] and the sampling below both work in.
List<Rect> _inactiveAreas(WidgetTester tester, double scale) {
  final List<Rect> found = <Rect>[];
  for (final RenderView view in tester.binding.renderViews) {
    final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root == null) continue;
    void walk(SemanticsNode node) {
      if (node.flagsCollection.isEnabled == ui.Tristate.isFalse) {
        Rect rect = node.rect;
        for (SemanticsNode? up = node; up != null; up = up.parent) {
          if (up.transform case final Matrix4 transform) {
            rect = MatrixUtils.transformRect(transform, rect);
          }
        }
        // The semantics tree is in physical pixels, because the root transform
        // carries the device pixel ratio.
        found.add(
          Rect.fromLTRB(
            rect.left / scale,
            rect.top / scale,
            rect.right / scale,
            rect.bottom / scale,
          ),
        );
      }
      node.visitChildren((SemanticsNode child) {
        walk(child);
        return true;
      });
    }

    walk(root);
  }
  return found;
}

/// Every paragraph and editable in the render tree, with its resolved colours.
Iterable<_PaintedText> _textOnScreen(RenderView view) {
  final List<_PaintedText> found = <_PaintedText>[];
  void walk(RenderObject node) {
    final InlineSpan? span = switch (node) {
      RenderParagraph(:final InlineSpan text) => text,
      RenderEditable(:final InlineSpan? text) => text,
      _ => null,
    };
    if (span != null && node is RenderBox) {
      final List<_Ink> inks = <_Ink>[];
      final StringBuffer plain = StringBuffer();
      _readSpan(span, const TextStyle(), inks, plain);
      if (inks.isNotEmpty) {
        found.add(_PaintedText(box: node, text: plain.toString(), inks: inks));
      }
    }
    node.visitChildren(walk);
  }

  walk(view);
  return found;
}

/// Walks a span tree, accumulating the style the way a `TextPainter` does.
void _readSpan(
  InlineSpan span,
  TextStyle inherited,
  List<_Ink> inks,
  StringBuffer plain,
) {
  if (span is! TextSpan) return;
  final TextStyle style = span.style == null
      ? inherited
      : inherited.merge(span.style);
  final String? text = span.text;
  if (text != null && text.trim().isNotEmpty) {
    plain.write(text);
    // A null colour is carried forward rather than dropped: it cannot happen
    // through Hearth's themes, so it is reported as a failure above rather
    // than quietly skipped here.
    final Color? colour = style.color;
    final String rule = _rule(style, text);
    inks.add(
      _Ink(colour: colour, target: rule == _normalText ? 4.5 : 3.0, why: rule),
    );
  }
  for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
    _readSpan(child, style, inks, plain);
  }
}

const String _normalText = 'WCAG 1.4.3, normal text';

/// Which of WCAG's contrast rules a run of text drawn in [style] falls under.
String _rule(TextStyle style, String text) {
  // An icon is a glyph from an icon font, and holding a picture to the rule
  // for prose would be this check inventing a policy. WCAG has its own rule
  // for one, and it is the 3:1 that large text gets.
  if (text.runes.every(_isPrivateUse)) return 'WCAG 1.4.11, a graphic';
  final double size = style.fontSize ?? 12.0;
  final bool bold =
      (style.fontWeight?.value ?? FontWeight.normal.value) >=
      FontWeight.bold.value;
  if (size >= 18 || (bold && size >= 14)) return 'WCAG 1.4.3, large text';
  return _normalText;
}

/// The private-use planes, which is where every icon font puts its glyphs.
bool _isPrivateUse(int rune) =>
    (rune >= 0xE000 && rune <= 0xF8FF) ||
    (rune >= 0xF0000 && rune <= 0xFFFFD) ||
    (rune >= 0x100000 && rune <= 0x10FFFD);

/// The frame is RGBA; [Color] is ARGB.
Color _colour(int rgba) => Color((rgba >>> 8) | ((rgba & 0xFF) << 24));

int _rgba(Color colour) {
  final int argb = colour.toARGB32();
  return ((argb & 0x00FFFFFF) << 8) | ((argb >>> 24) & 0xFF);
}

String _hex(Color colour) {
  final int argb = colour.toARGB32();
  final String rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final int alpha = (argb >>> 24) & 0xFF;
  return alpha == 0xFF ? '#$rgb' : '#$rgb at ${(alpha / 255 * 100).round()}%';
}

typedef _Journey = Future<void> Function(WidgetTester tester, SweepTools tools);

/// A screen the app pushes onto the navigator, and how to get to it.
///
/// Deliberately not added to [sweptSurfaces]: that list is sheets and dialogs,
/// it is reconciled against a guard that reads `lib/` for the calls that open
/// one, and a full-screen route is neither. Two lists with two definitions is
/// clearer than one list whose guard only understands half of it.
@immutable
class _Destination {
  const _Destination({
    required this.name,
    required this.arrived,
    this.open,
    this.launchTarget,
    this.signedIn = false,
    this.thermostat,
  });

  /// What it is, in the words the failure will use.
  final String name;

  /// Something only this screen shows, asserted before the guidelines are.
  final Finder arrived;

  /// How to get there from a freshly opened app. Null for a screen the app
  /// can be launched straight onto.
  final _Journey? open;

  /// Where the app opens, for a screen that is not inside Nutrition.
  final LaunchTarget? launchTarget;

  /// Whether the app needs a real account behind it.
  ///
  /// Two of Settings' most control-dense pieces — the share code with its copy
  /// button, and the password-reset row — are drawn only when the account has
  /// a code and an address, which the offline gateway a widget test gets has
  /// neither of. `swept_surfaces.dart` records the same gap as the reason its
  /// settings dialogs are unswept; a fake gateway closes it.
  final bool signedIn;

  /// A thermostat for the one screen that is somebody else's cloud.
  final ThermostatGateway? thermostat;
}

/// Opens Settings from wherever the shell is.
Future<void> _settings(WidgetTester tester, SweepTools tools) =>
    tools.reach(find.byTooltip('Settings'));

/// Opens one of Settings' six pages.
_Journey _settingsPage(String row) =>
    (WidgetTester tester, SweepTools tools) async {
      await _settings(tester, tools);
      await tools.reach(find.text(row));
    };

/// Opens one of the library-maintenance lists behind a tab's overflow menu.
_Journey _maintenance(String tab, String row) =>
    (WidgetTester tester, SweepTools tools) async {
      await tools.tab(tab);
      await tools.reach(find.byTooltip('More'));
      await tools.reach(find.text(row));
    };

/// The screens behind a push, and how to reach each one.
final List<_Destination> _destinations = <_Destination>[
  // The front door, which the sweep used never to see: it passed no launch
  // target, so every run started inside Nutrition.
  _Destination(
    name: 'the home screen',
    launchTarget: LaunchTarget.home,
    arrived: find.text('Hearth'),
  ),
  _Destination(
    name: 'a recipe',
    open: (WidgetTester tester, SweepTools tools) =>
        tools.reach(find.text(_recipeTitle)),
    arrived: find.widgetWithText(FloatingActionButton, 'Cook'),
  ),
  // The screen most likely to be read in a dim kitchen, and the one with the
  // most chrome per square inch: four icon buttons in the bar and a step card
  // with its own controls.
  _Destination(
    name: 'cook-along, which is used with wet hands',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.text(_recipeTitle));
      await tools.reach(find.widgetWithText(FloatingActionButton, 'Cook'));
    },
    arrived: find.byTooltip('Finish cooking'),
  ),
  _Destination(
    name: 'the week',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.text('Week'));
    },
    arrived: find.byTooltip('Previous week'),
  ),
  _Destination(
    name: 'the settings index',
    open: _settings,
    arrived: find.text('Sign out'),
  ),
  // The six pages behind the index (review §7.8). Every one of them was past
  // the single tap this sweep used to stop at.
  _Destination(
    name: 'settings · account',
    signedIn: true,
    open: _settingsPage('Account'),
    arrived: find.text('Your food profile'),
  ),
  _Destination(
    name: 'settings · cook together',
    signedIn: true,
    open: _settingsPage('Cook together'),
    arrived: find.text('Join'),
  ),
  _Destination(
    name: 'settings · appearance',
    open: _settingsPage('Appearance'),
    // One of the two answers the page adds. Not "Follow the device": that is
    // the *value* on the index's own row, so it is on screen before the tap
    // and an arrival finder that matches the room you started in guards
    // nothing.
    arrived: find.text('Light'),
  ),
  _Destination(
    name: 'settings · opens on',
    open: _settingsPage('Opens on'),
    // Same reason as Appearance: "The home screen" is the index's own value.
    arrived: find.text('Today'),
  ),
  _Destination(
    name: 'settings · syncing',
    open: _settingsPage('Syncing'),
    arrived: find.text('Sync now'),
  ),
  _Destination(
    name: 'settings · your data',
    open: _settingsPage('Your data'),
    arrived: find.text('Export my data'),
  ),
  _Destination(
    name: 'your food profile',
    signedIn: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _settingsPage('Account')(tester, tools);
      await tools.reach(find.text('Your food profile'));
    },
    // The first field on it. "Roughly per meal" is further down than a
    // ListView builds on a phone, and a finder that only matches when the
    // screen happens to be short enough is a finder that fails by the clock.
    arrived: find.text('Allergies'),
  ),
  // The two questions Settings asks before it does something. Unreachable
  // without an account, which is why `swept_surfaces.dart` records them as
  // unswept; a fake gateway is all they needed.
  _Destination(
    name: 'the sign-out question',
    signedIn: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _settings(tester, tools);
      await tools.reach(find.text('Sign out'));
    },
    arrived: find.text('Sign out?'),
  ),
  _Destination(
    name: 'the password-reset question',
    signedIn: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _settingsPage('Account')(tester, tools);
      await tools.reach(find.text('Reset password'));
    },
    arrived: find.text('Send a reset link?'),
  ),
  _Destination(
    name: 'the recipe editor',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
      await tools.reach(find.text('Write a recipe'));
    },
    arrived: find.text('New recipe'),
  ),
  _Destination(
    name: 'the food editor',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Foods');
      await tools.reach(find.text('Add food'));
      await tools.reach(find.text('Enter it by hand'));
    },
    arrived: find.text('New food'),
  ),
  _Destination(
    name: 'a food already in the library',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Foods');
      await tools.reach(find.text('Greek yoghurt'));
    },
    arrived: find.text('Edit food'),
  ),
  _Destination(
    name: 'foods with no pack size',
    open: _maintenance('Foods', 'Foods with no pack size'),
    arrived: find.text('Pack sizes'),
  ),
  _Destination(
    name: 'seasonings that need no match',
    open: _maintenance('Foods', 'Seasonings that need no match'),
    arrived: find.text('Seasonings'),
  ),
  _Destination(
    name: 'duplicate foods',
    open: _maintenance('Foods', 'Duplicate foods'),
    // In the bar, not anywhere: the menu row that opens it is worded the same,
    // so a plain text finder would be satisfied by the menu still being open.
    arrived: find.widgetWithText(AppBar, 'Duplicate foods'),
  ),
  _Destination(
    name: 'nutrition repair',
    open: _maintenance('Recipes', 'Nutrition repair'),
    arrived: find.widgetWithText(AppBar, 'Nutrition repair'),
  ),
  _Destination(
    name: 'eating out',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
      await tools.reach(find.text('Eat out'));
    },
    arrived: find.text('Chopt'),
  ),
  // The typed-barcode path. A widget test has no camera and the harness says
  // so, which is the whole screen apart from the detector itself.
  _Destination(
    name: 'the barcode scanner',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Foods');
      await tools.reach(find.text('Add food'));
      await tools.reach(find.text('Scan a barcode'));
    },
    arrived: find.text('Type the number'),
  ),
  // Another room entirely (spec §11), and the only screen in the app that is
  // somebody else's cloud.
  _Destination(
    name: 'the thermostat',
    launchTarget: _house,
    thermostat: const _LinkedThermostat(),
    arrived: find.text('Hallway'),
  ),
  _Destination(
    name: 'a room that is not furnished yet',
    launchTarget: _fitness,
    arrived: find.text('Workouts'),
  ),
];

LaunchTarget get _house => LaunchTarget.section(sectionById('home')!);
LaunchTarget get _fitness => LaunchTarget.section(sectionById('fitness')!);

/// A house with one thermostat in it, answering instantly.
///
/// Small and local rather than borrowed from `thermostat_screen_test.dart`:
/// what this sweep needs is a screen with its controls drawn, and importing a
/// test file for its fixtures makes two suites move together for no reason.
class _LinkedThermostat implements ThermostatGateway {
  const _LinkedThermostat();

  @override
  String get displayName => 'Google Nest';

  @override
  Future<Uri> consentUrl() async => Uri.parse('https://example.test/consent');

  @override
  Future<ThermostatLink> status() async => ThermostatLink.linked(
    devices: <ThermostatState>[
      ThermostatState(
        id: 'enterprises/p/devices/downstairs',
        label: 'Hallway',
        ambientC: Temp.fToC(70),
        humidityPercent: 43,
        mode: ThermostatMode.heat,
        availableModes: const <ThermostatMode>{
          ThermostatMode.off,
          ThermostatMode.heat,
          ThermostatMode.cool,
          ThermostatMode.heatCool,
        },
        hvac: HvacStatus.heating,
        heatC: Temp.fToC(68),
        eco: EcoMode.off,
      ),
    ],
    linkedByYou: true,
  );

  @override
  Future<void> send(ThermostatCommand command, {required String deviceId}) =>
      Future<void>.value();

  @override
  Future<void> unlink() => Future<void>.value();
}
