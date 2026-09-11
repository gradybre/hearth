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
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
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
  DateTime build() => addDays(super.build(), offset);
}

/// The food library a scene is pumped with.
///
/// Everything gets [galleryFoods]; only a scene that asks for it also gets
/// [choptMenu]. Kept apart rather than appended to the shared list because a
/// forty-four-row menu in the library would take the Foods tab and the two
/// logging-sheet scenes with it — three pictures of a chain's toppings, and
/// none of them the screen anybody wanted to look at.
List<Food> galleryFoodsFor(Scene scene) => <Food>[
  ...galleryFoods(),
  if (scene.longMenu) ...<Food>[...choptMenu(), ...otherRestaurants()],
];

/// The shopping list a scene is pumped with.
///
/// Empty for every scene but the shopping ones, for the same reason
/// [galleryFoodsFor] keeps the long menu to itself: a list already on the
/// phone is exactly what the `shopping` scene is a picture of *not* having,
/// and the two states have to be able to stand beside each other.
List<ShoppingLine> galleryShoppingLinesFor(Scene scene) =>
    scene.shoppingList ? galleryShoppingLines() : const <ShoppingLine>[];

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
    this.longMenu = false,
    this.shoppingList = false,
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

  /// Whether this scene is pumped with [choptMenu] as well as the ordinary
  /// fixtures.
  ///
  /// Only the eat-out scenes want it: the point of that menu is its length,
  /// and length is the one thing that would ruin every other scene it appeared
  /// in.
  final bool longMenu;

  /// Whether this scene is pumped with [galleryShoppingLines].
  ///
  /// Only the shopping scenes want it, and the `shopping` scene wants the
  /// opposite: it is the empty state, and a list seeded into every scene would
  /// quietly delete that picture.
  final bool shoppingList;

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

/// One row off a pasted nutrition sheet.
///
/// [order] is the position on that sheet, which is what
/// `RestaurantMenu.itemsFor` sorts by — so the fixture is laid out here in the
/// order the builder will draw it, and moving an item down the list is a
/// matter of moving its number.
Food _menuItem(
  String name, {
  required int order,
  required String section,
  required double kcal,
  double proteinG = 0,
  double carbG = 0,
  double fatG = 0,
  num amount = 4,
  Unit? unit,
}) => aFood(
  name,
  id: 'f-chopt-$order',
  brand: 'Chopt Creative Salad Co.',
  source: FoodSource.restaurant,
  menuGroup: section,
  menuOrder: order,
  servingOptions: <ServingOption>[
    aServing(
      amount: amount,
      unit: unit ?? Units.ounce,
      macros: Macros(kcal: kcal, proteinG: proteinG, carbG: carbG, fatG: fatG),
    ),
  ],
);

/// A whole chain menu — forty-four rows in six sections.
///
/// Long on purpose. Every other restaurant fixture in the suite is three or
/// four items, which is a size at which no menu screen can be wrong: the
/// review's complaint is that finding the guacamole means travelling past
/// everything else, and a four-row menu is a picture of that complaint being
/// false. Guacamole is deliberately the forty-third row of forty-four, under
/// Toppings, where a real sheet would put it.
///
/// **Invented.** The chain is real; these numbers are not, and nothing here
/// was read off a published nutrition sheet. It is a fixture for judging a
/// layout, and no figure in it is evidence about anybody's lunch.
List<Food> choptMenu() => <Food>[
  _menuItem(
    'Harvest Bowl',
    order: 1,
    section: 'Warm bowls',
    kcal: 690,
    proteinG: 27,
    carbG: 74,
    fatG: 32,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Spicy Chicken Tinga Bowl',
    order: 2,
    section: 'Warm bowls',
    kcal: 640,
    proteinG: 38,
    carbG: 58,
    fatG: 27,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Miso Ginger Salmon Bowl',
    order: 3,
    section: 'Warm bowls',
    kcal: 720,
    proteinG: 36,
    carbG: 61,
    fatG: 38,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Buffalo Chicken Warm Bowl',
    order: 4,
    section: 'Warm bowls',
    kcal: 760,
    proteinG: 41,
    carbG: 55,
    fatG: 42,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Chimichurri Steak Bowl',
    order: 5,
    section: 'Warm bowls',
    kcal: 810,
    proteinG: 44,
    carbG: 59,
    fatG: 45,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Sweet Potato & Farro Bowl',
    order: 6,
    section: 'Warm bowls',
    kcal: 580,
    proteinG: 16,
    carbG: 82,
    fatG: 21,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Kale Caesar',
    order: 7,
    section: 'Chopped salads',
    kcal: 520,
    proteinG: 21,
    carbG: 24,
    fatG: 38,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Mexican Caesar',
    order: 8,
    section: 'Chopped salads',
    kcal: 610,
    proteinG: 26,
    carbG: 31,
    fatG: 43,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Santa Fe Chopped',
    order: 9,
    section: 'Chopped salads',
    kcal: 660,
    proteinG: 34,
    carbG: 44,
    fatG: 37,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Palm Beach Chopped',
    order: 10,
    section: 'Chopped salads',
    kcal: 540,
    proteinG: 29,
    carbG: 36,
    fatG: 28,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Cobb, no blue cheese',
    order: 11,
    section: 'Chopped salads',
    kcal: 590,
    proteinG: 38,
    carbG: 18,
    fatG: 41,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Falafel & Feta Chopped',
    order: 12,
    section: 'Chopped salads',
    kcal: 630,
    proteinG: 22,
    carbG: 52,
    fatG: 36,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Thai Crunch',
    order: 13,
    section: 'Chopped salads',
    kcal: 570,
    proteinG: 24,
    carbG: 47,
    fatG: 31,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Build your own chopped salad',
    order: 14,
    section: 'Chopped salads',
    kcal: 180,
    proteinG: 6,
    carbG: 22,
    fatG: 7,
    amount: 1,
    unit: Units.item,
  ),
  _menuItem(
    'Romaine',
    order: 15,
    section: 'Greens & grains',
    kcal: 15,
    proteinG: 1,
    carbG: 3,
  ),
  _menuItem(
    'Baby kale',
    order: 16,
    section: 'Greens & grains',
    kcal: 25,
    proteinG: 2,
    carbG: 4,
  ),
  _menuItem(
    'Spinach & arugula',
    order: 17,
    section: 'Greens & grains',
    kcal: 20,
    proteinG: 2,
    carbG: 3,
  ),
  _menuItem(
    'Warm wild rice',
    order: 18,
    section: 'Greens & grains',
    kcal: 190,
    proteinG: 5,
    carbG: 40,
    fatG: 2,
  ),
  _menuItem(
    'Cilantro-lime brown rice',
    order: 19,
    section: 'Greens & grains',
    kcal: 210,
    proteinG: 4,
    carbG: 44,
    fatG: 3,
  ),
  _menuItem(
    'Farro',
    order: 20,
    section: 'Greens & grains',
    kcal: 230,
    proteinG: 8,
    carbG: 47,
    fatG: 2,
  ),
  _menuItem(
    'Grilled chicken',
    order: 21,
    section: 'Proteins',
    kcal: 180,
    proteinG: 32,
    fatG: 6,
  ),
  _menuItem(
    'Spicy chicken tinga',
    order: 22,
    section: 'Proteins',
    kcal: 220,
    proteinG: 29,
    carbG: 4,
    fatG: 10,
  ),
  _menuItem(
    'Falafel',
    order: 23,
    section: 'Proteins',
    kcal: 260,
    proteinG: 9,
    carbG: 26,
    fatG: 14,
  ),
  _menuItem(
    'Miso ginger salmon',
    order: 24,
    section: 'Proteins',
    kcal: 290,
    proteinG: 28,
    carbG: 6,
    fatG: 17,
  ),
  _menuItem(
    'Chimichurri steak',
    order: 25,
    section: 'Proteins',
    kcal: 310,
    proteinG: 34,
    carbG: 2,
    fatG: 19,
  ),
  _menuItem(
    'Braised beef',
    order: 26,
    section: 'Proteins',
    kcal: 340,
    proteinG: 31,
    carbG: 3,
    fatG: 23,
  ),
  _menuItem(
    'Crispy tofu',
    order: 27,
    section: 'Proteins',
    kcal: 200,
    proteinG: 14,
    carbG: 9,
    fatG: 13,
  ),
  _menuItem(
    'Mexican Caesar dressing',
    order: 28,
    section: 'Dressings',
    kcal: 190,
    proteinG: 2,
    carbG: 3,
    fatG: 19,
    amount: 2,
  ),
  _menuItem(
    'Spicy chipotle ranch',
    order: 29,
    section: 'Dressings',
    kcal: 210,
    proteinG: 1,
    carbG: 4,
    fatG: 22,
    amount: 2,
  ),
  _menuItem(
    'Sesame ginger vinaigrette',
    order: 30,
    section: 'Dressings',
    kcal: 160,
    carbG: 9,
    fatG: 14,
    amount: 2,
  ),
  _menuItem(
    'Lemon tahini',
    order: 31,
    section: 'Dressings',
    kcal: 180,
    proteinG: 3,
    carbG: 6,
    fatG: 16,
    amount: 2,
  ),
  _menuItem(
    'Red wine vinaigrette',
    order: 32,
    section: 'Dressings',
    kcal: 120,
    carbG: 3,
    fatG: 12,
    amount: 2,
  ),
  _menuItem(
    'Avocado green goddess',
    order: 33,
    section: 'Dressings',
    kcal: 170,
    proteinG: 2,
    carbG: 5,
    fatG: 16,
    amount: 2,
  ),
  _menuItem(
    'Balsamic, on the side',
    order: 34,
    section: 'Dressings',
    kcal: 110,
    carbG: 6,
    fatG: 10,
    amount: 2,
  ),
  _menuItem(
    'Roasted sweet potato',
    order: 35,
    section: 'Toppings',
    kcal: 120,
    proteinG: 2,
    carbG: 27,
  ),
  _menuItem(
    'Sweet corn & tomato salsa',
    order: 36,
    section: 'Toppings',
    kcal: 70,
    proteinG: 2,
    carbG: 15,
    fatG: 1,
  ),
  _menuItem(
    'Pickled red onion',
    order: 37,
    section: 'Toppings',
    kcal: 20,
    carbG: 5,
    amount: 1,
  ),
  _menuItem(
    'Cotija cheese',
    order: 38,
    section: 'Toppings',
    kcal: 110,
    proteinG: 7,
    carbG: 1,
    fatG: 9,
    amount: 1,
  ),
  _menuItem(
    'Spicy broccoli',
    order: 39,
    section: 'Toppings',
    kcal: 90,
    proteinG: 4,
    carbG: 10,
    fatG: 4,
  ),
  _menuItem(
    'Crispy shallots',
    order: 40,
    section: 'Toppings',
    kcal: 130,
    proteinG: 1,
    carbG: 9,
    fatG: 10,
    amount: 1,
  ),
  _menuItem(
    'Toasted almonds',
    order: 41,
    section: 'Toppings',
    kcal: 170,
    proteinG: 6,
    carbG: 6,
    fatG: 15,
    amount: 1,
  ),
  _menuItem(
    'Feta',
    order: 42,
    section: 'Toppings',
    kcal: 100,
    proteinG: 6,
    carbG: 2,
    fatG: 8,
    amount: 1,
  ),
  // The one everybody is looking for: the forty-third row of forty-four, at
  // the bottom of the last section. Its position is the point of the fixture.
  _menuItem(
    'Guacamole',
    order: 43,
    section: 'Toppings',
    kcal: 150,
    proteinG: 2,
    carbG: 8,
    fatG: 13,
    amount: 2,
  ),
  _menuItem(
    'Tortilla chips',
    order: 44,
    section: 'Toppings',
    kcal: 140,
    proteinG: 2,
    carbG: 18,
    fatG: 7,
    amount: 1,
  ),
];

/// Two more chains, a couple of rows each.
///
/// Nothing on these menus is picked by any scene; they exist so the first
/// stage of the builder is a *list* rather than a pair. A household that has
/// pasted one menu is a first-run state, and the screen already has a scene
/// for that in its own right — what nobody had a picture of is the ordinary
/// case, four places you eat, and whether choosing between them reads.
///
/// Invented, like [choptMenu], and for the same reason.
List<Food> otherRestaurants() => <Food>[
  aFood(
    'Guacamole & Chips',
    id: 'f-sg-1',
    brand: 'Sweetgreen',
    source: FoodSource.restaurant,
    menuGroup: 'Sides',
    menuOrder: 1,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        label: '1 side',
        macros: const Macros(kcal: 340, proteinG: 4, carbG: 30, fatG: 24),
      ),
    ],
  ),
  aFood(
    'Harvest Bowl',
    id: 'f-sg-2',
    brand: 'Sweetgreen',
    source: FoodSource.restaurant,
    menuGroup: 'Warm bowls',
    menuOrder: 2,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        label: '1 bowl',
        macros: const Macros(kcal: 705, proteinG: 30, carbG: 66, fatG: 36),
      ),
    ],
  ),
  aFood(
    'Charred Chicken & Sweet Potato',
    id: 'f-dig-1',
    brand: 'Dig — the one on Fulton St',
    source: FoodSource.restaurant,
    menuGroup: 'Bowls',
    menuOrder: 1,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        label: '1 bowl',
        macros: const Macros(kcal: 620, proteinG: 41, carbG: 58, fatG: 22),
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

/// One line of the shopping fixture.
///
/// [store] is the shop the line is tagged with, which is the only thing the
/// screen groups by — it has no notion of an aisle. Empty means untagged, and
/// those sort to the bottom under "Anywhere".
ShoppingLine _line(
  String name, {
  required int order,
  String store = '',
  List<Quantity> planned = const <Quantity>[],
  Quantity? wanted,
  Quantity? onHand,
  bool checked = false,
  bool manual = false,
  bool unquantified = false,
  List<String> from = const <String>[],
}) => ShoppingLine(
  key: name.toLowerCase().replaceAll(' ', '-'),
  name: name,
  planned: planned,
  wanted: wanted,
  onHand: onHand,
  checked: checked,
  storeTag: store.isEmpty ? null : store,
  isManual: manual,
  hasUnquantified: unquantified,
  sortOrder: order,
  sourceRecipeIds: from,
);

/// A shop's worth of list: sixteen lines, three groups, four already ticked.
///
/// Sized and shaped like the list the complaint is about rather than like a
/// test's two rows. It carries every arrangement a line has — an amount
/// changed by hand, a cupboard amount subtracted, two units that cannot be
/// reconciled, a line with no amount at all, and two items no recipe asked
/// for — so a redesign is judged against all of them at once instead of
/// against the easy one.
///
/// **Invented**, like the rest of this file. Nothing here was on anybody's
/// actual list.
List<ShoppingLine> galleryShoppingLines() => <ShoppingLine>[
  // Costco: the bulk half of the shop.
  _line(
    'Ground beef',
    order: 0,
    store: 'Costco',
    planned: <Quantity>[Quantity.of(1.5, Units.pound)],
    // Bought in packets, so the number to buy is not the number the recipes
    // add up to — the case the edit pencil exists for.
    wanted: Quantity.of(2, Units.pound),
    from: <String>['r-lasagne', 'r-chilli'],
  ),
  _line(
    'Chicken breast',
    order: 1,
    store: 'Costco',
    planned: <Quantity>[Quantity.of(3, Units.pound)],
    checked: true,
  ),
  _line(
    'Rolled oats',
    order: 2,
    store: 'Costco',
    planned: <Quantity>[Quantity.of(1600, Units.gram)],
    from: <String>['r-oats'],
  ),
  _line(
    'Greek yogurt, 0%',
    order: 3,
    store: 'Costco',
    planned: <Quantity>[Quantity.of(1020, Units.gram)],
  ),
  // Trader Joe's: the weekly half.
  _line(
    'Lasagne sheets',
    order: 4,
    store: "Trader Joe's",
    planned: <Quantity>[Quantity.of(12, Units.item)],
    from: <String>['r-lasagne'],
  ),
  _line(
    'Whole milk',
    order: 5,
    store: "Trader Joe's",
    planned: <Quantity>[Quantity.of(1200, Units.millilitre)],
    // Half of it is already in the fridge, so the shop needs the rest.
    onHand: Quantity.of(500, Units.millilitre),
    from: <String>['r-lasagne'],
  ),
  _line(
    'Parmesan, grated',
    order: 6,
    store: "Trader Joe's",
    planned: <Quantity>[Quantity.of(200, Units.gram)],
    checked: true,
  ),
  _line(
    'Baby spinach',
    order: 7,
    store: "Trader Joe's",
    planned: <Quantity>[Quantity.of(2, Units.package)],
  ),
  // Anywhere: everything no shop was named for, which is most of a real list.
  _line(
    'Kidney beans',
    order: 8,
    planned: <Quantity>[Quantity.of(4, Units.can)],
    from: <String>['r-chilli'],
  ),
  _line(
    'Crushed tomatoes',
    order: 9,
    planned: <Quantity>[Quantity.of(2, Units.can)],
    from: <String>['r-chilli'],
  ),
  _line(
    'Yellow onion',
    order: 10,
    planned: <Quantity>[Quantity.of(5, Units.item)],
  ),
  // A recipe called for three cloves and another just said "garlic", so the
  // total understates it and the line has to say so.
  _line(
    'Garlic',
    order: 11,
    planned: <Quantity>[Quantity.of(3, Units.clove)],
    unquantified: true,
  ),
  _line(
    'Blueberries',
    order: 12,
    planned: <Quantity>[Quantity.of(2, Units.container)],
    checked: true,
    from: <String>['r-oats'],
  ),
  // Two units with no density between them, which §5.7 says to show side by
  // side rather than guess at. It has no single amount, so the tick is the
  // only thing that can be said about it.
  _line(
    'Butter',
    order: 13,
    planned: <Quantity>[
      Quantity.of(2, Units.tbsp),
      Quantity.of(50, Units.gram),
    ],
  ),
  // The two nobody planned. A rebuild cannot take them off, and — worth
  // seeing in the picture — nothing on the row says they were added by hand.
  _line('Coffee beans', order: 14, manual: true),
  _line('Paper towels', order: 15, manual: true, checked: true),
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
  // does.
  //
  // What it shows is the *chrome* following the date, and only that. The
  // meals are the same fixtures as every other scene — `galleryEntries`
  // keys them to `day-1` and the harness hands them to whichever date is
  // asked for — so this is not a picture of a past day's own food, and
  // nothing here has been exercised against a day that is empty or
  // differently full. Said out loud because a design artefact that is partly
  // invented has to say which part.
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
  // The same tab with a shop's worth of list on it, which is the state the
  // screen is actually used in and the one nothing had a picture of. The
  // empty scene above cannot show the complaint: with no lines, the setup
  // card sitting above them is the only thing there is.
  Scene(name: 'shopping-list', shoppingList: true, taps: <String>['Shopping']),
  // A small phone at double text, where the setup card's cost is at its
  // worst: it grows with the type and the list starts below it either way.
  Scene(
    name: 'shopping-list-large-text',
    shoppingList: true,
    size: Size(320, 640),
    textScale: 2.0,
    taps: <String>['Shopping'],
  ),
  // And a desktop window, where the same card is stretched across 1280pt of
  // width for the sake of a date and a switch.
  Scene(
    name: 'shopping-list-desktop',
    shoppingList: true,
    size: Size(1280, 900),
    taps: <String>['Shopping'],
  ),
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
  // The eat-out builder, in the four states a redesign has to answer for. All
  // four carry [choptMenu], because the complaint the redesign is about is a
  // property of a long menu and invisible on a short one.
  //
  // Reached by pressing what a person presses — Recipes, Add recipe, Eat out —
  // because `/recipe/eat-out` is a pushed route and no launch target opens it.
  Scene(
    name: 'eat-out-restaurants',
    longMenu: true,
    taps: <String>['Recipes', 'Add recipe', 'Eat out'],
  ),
  Scene(
    name: 'eat-out-menu',
    longMenu: true,
    taps: <String>[
      'Recipes',
      'Add recipe',
      'Eat out',
      'Chopt Creative Salad Co.',
    ],
  ),
  // A salad and two things on it, which is what somebody actually orders —
  // and it takes three taps spread over thirty-six rows to say so.
  //
  // The order matters and so does the ending. `pressLabel` aligns whatever it
  // presses to the top of the viewport, so the *last* tap decides where the
  // list is standing when the shutter goes; and a lazy list drops what it has
  // scrolled past, so pressing back up the menu cannot be done at all. Ending
  // on the last two rows is what puts more than one pick in frame: the list
  // is already against its own end, so the scroll clamps and the rows above
  // stay where they are.
  //
  // What no arrangement of this scene can show is the first pick alongside
  // the last two. Thirty-six rows apart, they do not fit on a phone, and that
  // is a property of the screen rather than of the fixture.
  Scene(
    name: 'eat-out-picked',
    longMenu: true,
    taps: <String>[
      'Recipes',
      'Add recipe',
      'Eat out',
      'Chopt Creative Salad Co.',
      'Kale Caesar',
      'Guacamole',
      'Tortilla chips',
    ],
  ),
  // Settings, which the review calls "a long expanded page [that] exposes
  // every option at once" (§7.8). One viewport is all a frame can hold, so
  // what these show is the top of it; how far it runs below the fold is a
  // number, and `settings_length_test.dart` measures it.
  Scene(name: 'settings', taps: <String>['Settings']),
  Scene(
    name: 'settings-dark',
    brightness: Brightness.dark,
    taps: <String>['Settings'],
  ),
  Scene(
    name: 'settings-large-text',
    size: Size(320, 568),
    textScale: 2.0,
    taps: <String>['Settings'],
  ),
  Scene(
    name: 'settings-desktop',
    size: Size(1280, 900),
    taps: <String>['Settings'],
  ),
  // A small phone at double text, which is where a list with no way to jump
  // costs the most: the same forty-four rows, four or five of them on screen.
  Scene(
    name: 'eat-out-menu-large-text',
    longMenu: true,
    size: Size(320, 640),
    textScale: 2.0,
    taps: <String>[
      'Recipes',
      'Add recipe',
      'Eat out',
      'Chopt Creative Salad Co.',
    ],
  ),
];
