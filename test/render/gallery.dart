/// The populated fixtures and surfaces the screen gallery renders
/// (review §9.1).
///
/// Its own file so a scene can be added without touching the test that draws
/// them, and so the fixture data is readable on its own: a gallery rendered
/// from empty state is the thing §9.1 explicitly rules out, and the easiest
/// mistake to make by accident.
///
/// **These are fixtures, not production data.** Nothing here is read from a
/// real household, and no number in a rendered image is evidence about
/// anybody's actual nutrition.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/unit.dart';

import '../support/fixtures.dart';

/// Whether the gallery is being drawn at all.
///
/// Opt-in by environment, the same way the live suite is: these are design
/// deliverables rather than correctness gates, they are slow, and a golden
/// rendered on macOS does not match one rendered on CI's Linux — so running
/// them by default would either fail every CI run or teach everybody to
/// ignore a red light.
bool get renderingGallery => Platform.environment['HEARTH_RENDER'] == '1';

/// Where the images are written. Gitignored by default, so drawing the
/// gallery to look at it never dirties the tree; point it somewhere under
/// `docs/` when the images are the deliverable.
String get galleryDirectory =>
    Platform.environment['HEARTH_RENDER_DIR'] ?? 'build/gallery';

/// Captures the current frame and writes it as a PNG.
///
/// Straight to a file rather than through `matchesGoldenFile`, because these
/// are artefacts rather than assertions — see the note in `gallery_test.dart`.
/// `runAsync` is required: encoding an image needs the real event loop, which
/// a widget test's fake async does not provide.
Future<void> writeScene(WidgetTester tester, Scene scene) async {
  final RenderView view = tester.binding.renderViews.first;
  final OffsetLayer layer = view.debugLayer! as OffsetLayer;

  final ByteData? png = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await layer.toImage(Offset.zero & view.size);
    try {
      return await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
  });
  if (png == null) throw StateError('${scene.name} produced no image');

  final Directory dir = Directory(galleryDirectory);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/${scene.name}.png')
      .writeAsBytesSync(png.buffer.asUint8List());
}

/// Loads the Material icon font.
///
/// `flutter_test_config.dart` loads Hearth's own two faces for every test,
/// which is what the correctness suite needs. It does not load the icon font,
/// and without it every icon draws as an empty box — fine for a finder, and
/// useless for a picture somebody is meant to judge a layout from.
///
/// Loaded here rather than globally because it is only the gallery that cares
/// what an icon *looks* like, and widening a shared hook to suit one directory
/// is how shared hooks stop being predictable.
Future<void> loadIconFont() async {
  final String? root =
      Platform.environment['FLUTTER_ROOT'] ?? _flutterRootFromExecutable();
  if (root == null) {
    throw StateError(
      'Cannot find the Flutter SDK to load MaterialIcons from. Set '
      'FLUTTER_ROOT, or run the gallery from a shell where `flutter` is on '
      'the path.',
    );
  }

  final File file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) {
    throw StateError('MaterialIcons-Regular.otf is not at ${file.path}');
  }

  final FontLoader loader = FontLoader('MaterialIcons')
    ..addFont(
      file.readAsBytes().then(
        (List<int> bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
      ),
    );
  await loader.load();
}

/// The SDK root, derived from wherever `flutter` resolves to.
String? _flutterRootFromExecutable() {
  final ProcessResult which = Process.runSync('which', <String>['flutter']);
  if (which.exitCode != 0) return null;
  final String path = (which.stdout as String).trim();
  if (path.isEmpty) return null;
  final File link = File(path);
  final String resolved = link.resolveSymbolicLinksSync();
  // …/bin/flutter → …
  return Directory(resolved).parent.parent.path;
}

/// The planner, opened on a day that is not today.
///
/// Subclassed rather than overridden with a fixed value because the real
/// notifier is what the screen's own arrows and "Go to today" button drive; a
/// scene that replaced it with a constant would picture a day screen whose
/// controls do nothing, which is not the screen that ships.
class GalleryDate extends SelectedDate {
  GalleryDate(this.offset);

  /// Days from today. Negative is the past.
  final int offset;

  @override
  DateTime build() {
    final DateTime today = super.build();
    return DateTime(today.year, today.month, today.day + offset);
  }
}

/// The provider overrides a scene needs, in the untyped shape `pumpHearthApp`
/// takes — riverpod 3 exports the methods that make an `Override` and not the
/// type itself, which is why the harness types them as `Object` too.
List<Object> galleryOverrides(Scene scene) => <Object>[
  if (scene.dayOffset != 0)
    selectedDateProvider.overrideWith(() => GalleryDate(scene.dayOffset)),
];

/// Presses one of [Scene.taps].
///
/// Visible text first, tooltip second: a tab is a word on screen, while "add
/// to breakfast" is a bare `+` whose only name is its tooltip. `.last` because
/// a label on screen is often also a label behind the sheet on top of it, and
/// the thing to press is the one in front.
///
/// Scrolled to first when nothing on screen carries the label. The picker
/// half of the logging sheet lists the whole library, and a `ListView` builds
/// only what is near the viewport — so a food below the fold is not merely
/// off-screen, it is absent from the tree and no finder can see it.
Future<void> pressLabel(WidgetTester tester, String label) async {
  Finder? onScreen() {
    final Finder byText = find.text(label);
    if (byText.evaluate().isNotEmpty) return byText.last;
    final Finder byTooltip = find.byTooltip(label);
    if (byTooltip.evaluate().isNotEmpty) return byTooltip.last;
    return null;
  }

  if (onScreen() == null) {
    final Finder scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      throw StateError('Nothing on screen is labelled "$label" to press.');
    }
    // The innermost list, for the same reason `.last` is used above: the one
    // in front is the one being read.
    await tester.scrollUntilVisible(
      find.text(label),
      120,
      scrollable: scrollables.last,
      maxScrolls: 40,
    );
  }

  final Finder? target = onScreen();
  if (target == null) {
    throw StateError('Nothing on screen is labelled "$label" to press.');
  }
  await tester.ensureVisible(target);
  await tester.tap(target);
}

/// Weekly targets, so the day screen shows progress rather than a setup
/// prompt. A gallery of the un-set-up state judges the wrong screen.
const MacroTargets galleryTargets = MacroTargets(
  kcal: 2200,
  proteinG: 150,
  carbG: 250,
  fatG: 70,
  fiberG: 28,
  sodiumMg: 2300,
  cholesterolMg: 300,
);

/// One surface, at one size, in one theme, at one text size.
@immutable
class Scene {
  const Scene({
    required this.name,
    this.target,
    this.size = const Size(390, 844),
    this.brightness = Brightness.light,
    this.textScale = 1.0,
    this.dayOffset = 0,
    this.taps = const <String>[],
  });

  /// The file name, without extension. Also the caption in the index.
  final String name;

  /// Where the app opens, which is how a scene reaches its screen without a
  /// tap sequence that would break every time navigation is rearranged.
  ///
  /// Null means the harness default — the Nutrition shell, which is where the
  /// tabbed surfaces live. `LaunchTarget.home` opens the launcher, which has
  /// no tabs at all.
  final LaunchTarget? target;

  /// Things to press after launch, in order, for surfaces no launch target
  /// reaches: a tab in the shell, and — two presses deeper — the logging
  /// sheet, which exists only as a modal over the day screen.
  ///
  /// Matched as visible text first and as a tooltip second, because half of
  /// what has to be pressed here is an icon button whose only name is its
  /// tooltip. Labels rather than keys or types, so a scene reads as the thing
  /// a person would do; a rearranged screen breaks the scene loudly, which is
  /// the right failure for a picture that would otherwise be silently of the
  /// wrong screen.
  final List<String> taps;

  /// How far from today the planner opens, in days. Negative is the past.
  ///
  /// An offset rather than a date, because the day screen resolves "today"
  /// from the wall clock: a fixed date would be three days ago this week and
  /// last March by the spring, and what these scenes are about is the
  /// relationship between the two, never a particular Tuesday.
  final int dayOffset;

  final Size size;
  final Brightness brightness;
  final double textScale;
}

/// A household with enough in it to judge a layout.
///
/// Deliberately awkward: a long restaurant name, a recipe title that wraps, a
/// food with unknown minor nutrients, and a partial day. A gallery of tidy
/// short strings shows nothing about the layout that will actually ship.
List<Recipe> galleryRecipes() => <Recipe>[
  aRecipe(
    id: 'r-lasagne',
    title: 'Easy classic lasagne with béchamel',
    servings: 6,
    tags: <String>['Italian', 'Batch'],
    ingredients: <RecipeIngredient>[
      anIngredient('ground beef', amount: 500, unit: Units.gram),
      anIngredient('lasagne sheets', amount: 12),
      anIngredient('whole milk', amount: 600, unit: Units.millilitre),
    ],
  ),
  aRecipe(
    id: 'r-oats',
    title: 'Blueberry overnight oats',
    servings: 1,
    ingredients: <RecipeIngredient>[
      anIngredient('rolled oats', amount: 80, unit: Units.gram),
      anIngredient('greek yogurt', amount: 170, unit: Units.gram),
    ],
  ),
  aRecipe(
    id: 'r-chilli',
    title: 'Weeknight chilli',
    servings: 4,
    tags: <String>['Batch'],
    ingredients: <RecipeIngredient>[
      anIngredient('ground beef', amount: 450, unit: Units.gram),
      anIngredient('kidney beans', amount: 2),
    ],
  ),
];

List<Food> galleryFoods() => <Food>[
  // The two the logging sheet scenes pick, first in the list on purpose. The
  // picker is a lazy list, so reaching a food further down means scrolling —
  // and scrolling a draggable sheet drags it open on the way, which pictures
  // the sheet at a height nobody chose.
  //
  // One serving, and it is a weight. The sheet has two arrangements for the
  // row above the stepper and this is the one nothing else in the gallery
  // reaches: a single serving still has to say what it is, because "1" on its
  // own could be a fillet or 170 g.
  aFood(
    'Chicken breast, roasted',
    id: 'f-chicken',
    servingOptions: <ServingOption>[
      aServing(
        amount: 170,
        unit: Units.gram,
        label: '170 g',
        macros: const Macros(kcal: 281, proteinG: 53, carbG: 0, fatG: 6),
      ),
    ],
  ),
  // And the other arrangement: several servings of the same kind, which is
  // the only case the sheet offers a picker for. All weights deliberately —
  // the sheet drops any option it cannot express as a multiple of the default
  // one, so a spoon measured by volume would silently not appear.
  aFood(
    'Peanut butter, smooth',
    id: 'f-pb',
    brand: 'Whole Earth',
    servingOptions: <ServingOption>[
      aServing(
        amount: 32,
        unit: Units.gram,
        label: '2 tbsp (32 g)',
        macros: const Macros(kcal: 191, proteinG: 8, carbG: 6, fatG: 16),
      ),
      aServing(
        amount: 100,
        unit: Units.gram,
        label: '100 g',
        macros: const Macros(kcal: 597, proteinG: 25, carbG: 20, fatG: 51),
      ),
      aServing(
        amount: 340,
        unit: Units.gram,
        label: '1 jar (340 g)',
        macros: const Macros(kcal: 2030, proteinG: 85, carbG: 68, fatG: 173),
      ),
    ],
  ),
  aFoodPer100g(
    'Greek yogurt, 0%',
    kcal: 59,
    protein: 10,
    carbs: 4,
    id: 'f-yog',
  ),
  aFoodPer100g(
    'Rolled oats',
    kcal: 379,
    protein: 13,
    carbs: 68,
    fat: 7,
    id: 'f-oats',
  ),
  aFood(
    'Burrito bowl · chicken, brown rice, black beans',
    id: 'f-bowl',
    brand: 'Chipotle Mexican Grill',
    source: FoodSource.restaurant,
    menuGroup: 'Burrito bowls',
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        label: '1 bowl',
        macros: const Macros(kcal: 630, proteinG: 44, carbG: 66, fatG: 20),
      ),
    ],
  ),
];

/// A day with one meal eaten and one still planned, which is the state the
/// day screen is actually looked at in.
List<MealPlanEntry> galleryEntries(DateTime day) => <MealPlanEntry>[
  MealPlanEntry(
    id: 'e-breakfast',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'f-yog',
    servings: 1.7,
    isPlanned: false,
    isLogged: true,
    loggedAt: day,
    macroSnapshot: MacroSnapshot(
      macros: const Macros(kcal: 100, proteinG: 17, carbG: 6, fatG: 0),
      servings: 1.7,
      capturedAt: day,
      label: '170 g',
    ),
  ),
  const MealPlanEntry(
    id: 'e-lunch',
    dayId: 'day-1',
    slot: MealSlot.lunch,
    refType: PlanRefType.recipe,
    refId: 'r-oats',
    servings: 1,
  ),
];

/// The surfaces §9.1 asks for, plus the two states that catch most layout
/// problems: dark, and a small phone at enlarged text.
///
/// And the two that only exist as a *before* picture: a past day, and the
/// logging sheet. Both are surfaces a redesign has to be judged against and
/// neither was drawn, so the review had nothing to compare its proposals to.
const List<Scene> scenes = <Scene>[
  Scene(name: 'today', target: LaunchTarget.today),
  // The same screen, three days back. Its own scene because the day view is
  // not one screen: everything on it is supposed to follow the date in the
  // header, and a redesign judged only against today cannot show whether it
  // does. As of this writing it does not — the summary card is captioned
  // "Today" whatever day is selected (`day_screen.dart`, `_RemainingCard`) —
  // and the point of drawing the before state is that the picture says so
  // rather than a sentence in a review.
  Scene(name: 'day-past', target: LaunchTarget.today, dayOffset: -3),
  Scene(
    name: 'today-dark',
    target: LaunchTarget.today,
    brightness: Brightness.dark,
  ),
  Scene(
    name: 'today-large-text',
    target: LaunchTarget.today,
    size: Size(320, 568),
    textScale: 2.0,
  ),
  Scene(name: 'home', target: LaunchTarget.home),
  Scene(name: 'recipes', taps: <String>['Recipes']),
  Scene(
    name: 'recipes-desktop',
    taps: <String>['Recipes'],
    size: Size(1280, 900),
  ),
  Scene(name: 'foods', taps: <String>['Foods']),
  Scene(name: 'shopping', taps: <String>['Shopping']),
  // The sheet every logged meal goes through, in both of its arrangements.
  // Reached by pressing what a person presses, because it is a modal over the
  // day screen and no launch target can open it.
  Scene(
    name: 'log-sheet-mass',
    target: LaunchTarget.today,
    taps: <String>['Add to breakfast', 'Chicken breast, roasted'],
  ),
  Scene(
    name: 'log-sheet-servings',
    target: LaunchTarget.today,
    taps: <String>['Add to lunch', 'Peanut butter, smooth'],
  ),
];
