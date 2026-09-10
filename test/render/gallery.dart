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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

String? get gallerySkip =>
    renderingGallery ? null : 'set HEARTH_RENDER=1 to draw the gallery';

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
    this.tab,
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

  /// A tab to press after launch, for surfaces the launch target cannot reach
  /// on its own.
  final String? tab;

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
const List<Scene> scenes = <Scene>[
  Scene(name: 'today', target: LaunchTarget.today),
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
  Scene(name: 'recipes', tab: 'Recipes'),
  Scene(name: 'recipes-desktop', tab: 'Recipes', size: Size(1280, 900)),
  Scene(name: 'foods', tab: 'Foods'),
  Scene(name: 'shopping', tab: 'Shopping'),
];
