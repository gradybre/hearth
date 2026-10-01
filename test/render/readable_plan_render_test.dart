@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/planning/meal_plan.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'readable-plan-phone'),
  Scene(name: 'readable-plan-phone-dark', brightness: Brightness.dark),
  Scene(name: 'readable-plan-desktop', size: Size(1280, 800)),
  Scene(
    name: 'readable-plan-desktop-dark',
    size: Size(1280, 800),
    brightness: Brightness.dark,
  ),
  Scene(name: 'readable-plan-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'readable-plan-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets('${scene.name}: populated Day and Week initial view', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      expect(find.byTooltip('Previous day'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-day'));

      await SweepTools(tester).planView('Week');
      expect(find.byTooltip('Previous week'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-week'));
    }, skip: !renderingGallery);

    testWidgets('${scene.name}: Copy day choices and reachable actions', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      final SweepTools tools = SweepTools(tester);
      await tools.reach(find.byTooltip('Copy this day to other days'));
      expect(find.text('Copy this day to'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-copy-top'));

      // Exercise the far end of the date list, not just the first choices.
      await tools.bring(find.textContaining('Sunday 10/11'));
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-copy-end'));
      await tools.reach(find.text('Cancel'));
      expect(find.text('Copy this day to'), findsNothing);
    }, skip: !renderingGallery);
  }
}

Future<void> _open(WidgetTester tester, Scene scene) async {
  final DateTime day = DateTime(2026, 9, 30);
  await pumpHearthApp(
    tester,
    launchTarget: LaunchTarget.today,
    selectedDate: day,
    size: scene.size,
    brightness: scene.brightness,
    textScale: scene.textScale,
    viewPadding: scene.size.width >= 840
        ? const EdgeInsets.only(top: 24)
        : scene.size.width <= 320
        ? const EdgeInsets.only(top: 24, bottom: 34)
        : const EdgeInsets.only(top: 47, bottom: 34),
    recipes: galleryRecipes(),
    foods: galleryFoods(),
    entries: <MealPlanEntry>[
      ...galleryEntries(day).where((MealPlanEntry entry) => entry.isLogged),
      const MealPlanEntry(
        id: 'readable-plan-dinner',
        dayId: 'day-1',
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'f-bowl',
        servings: 1,
      ),
    ],
    weekEntries: galleryWeek(day),
    targets: galleryTargets,
  );
  await pumpFrames(tester, frames: 20);
}
