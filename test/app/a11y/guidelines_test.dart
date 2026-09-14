import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// The §6.3 baseline, checked by Flutter's own auditors rather than by eye.
///
/// These are the guidelines the framework ships: every tappable thing is big
/// enough to hit and carries a label a screen reader can read, and text meets
/// WCAG AA contrast against what is behind it. Written as a sweep because the
/// baseline is not optional and a per-screen habit is how it rots.
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

  /// The three auditors, against whatever is on screen.
  ///
  /// [where] is carried into the failure, because a sweep that says only
  /// "tap target too small" leaves you to find which of thirty screens it
  /// meant.
  Future<void> check(
    WidgetTester tester,
    String where, {

    /// False only where the framework's contrast auditor cannot measure the
    /// screen — one surface, named and replaced below rather than skipped.
    bool contrast = true,
  }) async {
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
    if (contrast) {
      await expectLater(
        tester,
        meetsGuideline(textContrastGuideline),
        reason: 'text on $where is under WCAG AA contrast',
      );
    }
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
        await expectLater(
          tester,
          meetsGuideline(textContrastGuideline),
          reason: 'text on the $tab tab is under WCAG AA contrast',
        );
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
          // One surface the framework's contrast auditor cannot measure. It
          // is not skipped: its two labels are measured directly, by the
          // colours actually on the glass. See [_unmeasurableByTheAuditor].
          final bool measurable = surface.name != _unmeasurableByTheAuditor;
          await check(
            tester,
            '${surface.name} in $theme',
            contrast: measurable,
          );
          if (!measurable) {
            for (final String label in _logSheetGroupLabels) {
              await expectTextContrast(
                tester,
                find.text(label),
                '"$label" on ${surface.name} in $theme',
              );
            }
          }
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

/// The one surface [textContrastGuideline] reports a false failure on.
///
/// **What it reports.** The log sheet's two group headings — "Your recipes"
/// and "Your foods" — come back at a contrast ratio of 1.04 in light and 1.08
/// in dark, which would mean text painted in its own background colour.
///
/// **What is actually on the glass**, sampled out of the rendered frame inside
/// each heading's own line box:
///
/// ```
/// #ece2d0 x8852   the sheet behind it
/// #e9decb x338    one anti-aliased scanline, all of it at y=373
/// #6b5849 x40     the heading itself, at full strength
/// ```
///
/// `MinimumTextContrastGuideline` samples the label's paint bounds *inflated
/// by four points*, histograms the pixels, and takes the most frequent colour
/// above and below the mean lightness. Four points below a 12-point heading is
/// the top border of the `_PickRow` card underneath it
/// (`lib/features/plan/log_sheet.dart:1242`, `Border.all(color: colors.outline)`),
/// and one anti-aliased hairline across 338 pixels outvotes the 40 pixels of
/// glyph that are at the text's full colour. So the ratio it computes is
/// between two creams, and the heading is not in the answer at all.
///
/// The heading really is `#6b5849` on `#ece2d0`, which is **5.25:1** and
/// clears AA. Nothing here needs fixing for accessibility. Widening
/// `_GroupLabel`'s four-point bottom padding by a point would move the hairline
/// out of the sampled band and let the auditor see the text — but that is
/// `log_sheet.dart`, which this change does not own, and changing the design
/// to suit the measuring instrument is the wrong way round anyway.
///
/// So the surface keeps both tap-target guidelines and swaps the contrast one
/// for [expectTextContrast], which asks the same question of the same two
/// headings and answers it exactly. Wash either heading out and it goes red.
const String _unmeasurableByTheAuditor = 'choosing something to log';

/// The two headings on that sheet, measured by hand in its place.
///
/// Its third — "Recent" — needs a logged meal behind it, which this fixture
/// has no reason to carry; the two here share a widget with it, so what is
/// unmeasured is a position on screen rather than a colour.
const List<String> _logSheetGroupLabels = <String>[
  'Your recipes',
  'Your foods',
];

/// The contrast of one label against what is painted behind it.
///
/// A narrower question than the guideline asks, answered off the same frame:
/// the colour the label is drawn in, against the commonest colour inside its
/// own line box — no inflation, so nothing outside the text can vote.
Future<void> expectTextContrast(
  WidgetTester tester,
  Finder finder,
  String where,
) async {
  final Element element = tester.element(finder);
  final Text label = tester.widget<Text>(finder);
  final TextStyle? own = label.style;
  final TextStyle style = own == null || own.inherit
      ? DefaultTextStyle.of(element).style.merge(own)
      : own;
  final Color foreground = style.color!;

  final RenderBox box = element.renderObject! as RenderBox;
  final RenderView view = tester.binding.renderViews.first;
  // Two coordinate spaces, and they are only the same one by a single line in
  // the harness. `getTransformTo(null)` answers in **logical** pixels, while
  // `RenderView.paintBounds` is `size * devicePixelRatio` and the image below
  // comes out that big — **physical** pixels. `app_harness.dart` pins the
  // ratio at 1.0, so today they coincide; at 3.0 the same rectangle covers a
  // ninth of the glyphs and sits at a third of their offset, which is a
  // region of whatever the label happens to be above.
  //
  // That would not go red. The foreground below is read from the widget tree
  // rather than from the frame, so a washed-out label still reports its own
  // colour against *some* background and the negative test still passes —
  // the check would go on answering, about the wrong pixels. So the rect is
  // converted rather than assumed.
  final double scale = view.configuration.devicePixelRatio;
  final Rect logical = MatrixUtils.transformRect(
    box.getTransformTo(null),
    box.paintBounds,
  );
  final Rect bounds = Rect.fromLTRB(
    logical.left * scale,
    logical.top * scale,
    logical.right * scale,
    logical.bottom * scale,
  );

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

  final Map<int, int> histogram = <int, int>{};
  for (int y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
    for (int x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
      if (x < 0 || y < 0 || x >= width || y >= height) continue;
      final int argb = pixels!.getUint32((y * width + x) * 4);
      histogram[argb] = (histogram[argb] ?? 0) + 1;
    }
  }
  expect(histogram, isNotEmpty, reason: '$where was not on screen');

  final int commonest = histogram.entries
      .reduce(
        (MapEntry<int, int> a, MapEntry<int, int> b) =>
            a.value >= b.value ? a : b,
      )
      .key;
  // The frame is RGBA; `Color` wants ARGB.
  final Color background = Color(
    (commonest >>> 8) | ((commonest & 0xFF) << 24),
  );

  // WCAG's own formula: (L1 + 0.05) / (L2 + 0.05), lighter over darker.
  final double ink = foreground.computeLuminance() + 0.05;
  final double paper = background.computeLuminance() + 0.05;
  final double ratio = ink > paper ? ink / paper : paper / ink;

  expect(
    ratio,
    greaterThanOrEqualTo(4.5),
    reason:
        '$where is $foreground on $background — '
        '${ratio.toStringAsFixed(2)}:1, under WCAG AA',
  );
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
