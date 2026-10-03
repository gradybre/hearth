@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/features/plan/nutrient_contributors_screen.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _scenes = <Scene>[
  Scene(name: 'day-contributors-phone'),
  Scene(name: 'day-contributors-phone-dark', brightness: Brightness.dark),
  Scene(name: 'day-contributors-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'day-contributors-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

Future<void> _bring(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFrames(tester, frames: 12);
  expect(finder.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _top(WidgetTester tester) async {
  final ScrollPosition position = tester
      .state<ScrollableState>(SweepTools.verticalScroller)
      .position;
  position.jumpTo(position.minScrollExtent);
  await pumpFrames(tester, frames: 12);
}

List<MealPlanEntry> _missingHistory(DateTime day, {required bool mixed}) =>
    <MealPlanEntry>[
      const MealPlanEntry(
        id: 'missing-history',
        dayId: 'day-1',
        slot: MealSlot.dinner,
        refType: PlanRefType.food,
        refId: 'f-oats',
        servings: 9,
        isLogged: true,
      ),
      if (mixed)
        MealPlanEntry(
          id: 'known-history',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'f-oats',
          servings: 1,
          isLogged: true,
          macroSnapshot: MacroSnapshot(
            label: 'Oats as logged',
            macros: const Macros(
              kcal: 315,
              proteinG: 23,
              carbG: 41,
              fatG: 8.5,
              fiberG: 0,
              sodiumMg: 80,
              cholesterolMg: 0,
            ),
            servings: 1,
            capturedAt: day,
            coverage: const NutrientCoverage.allComplete(),
          ),
        ),
    ];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _scenes) {
    for (final bool mixed in <bool>[false, true]) {
      for (final bool expanded in <bool>[false, true]) {
        testWidgets(
          '${scene.name} ${mixed ? 'mixed' : 'unavailable'} ${expanded ? 'expanded' : 'compact'} history',
          (WidgetTester tester) async {
            final DateTime day = DateTime(2026, 9, 30);
            final List<MealPlanEntry> entries = _missingHistory(
              day,
              mixed: mixed,
            );
            await pumpHearthApp(
              tester,
              size: scene.size,
              textScale: scene.textScale,
              brightness: scene.brightness,
              viewPadding: scene.size.width <= 320
                  ? const EdgeInsets.only(top: 24, bottom: 34)
                  : const EdgeInsets.only(top: 47, bottom: 34),
              launchTarget: LaunchTarget.today,
              selectedDate: day,
              foods: galleryFoods(),
              entries: entries,
              weekEntries: <DateTime, List<MealPlanEntry>>{day: entries},
              targets: galleryTargets,
              extraOverrides: <Object>[
                bootDaySummaryExpandedProvider.overrideWithValue(expanded),
              ],
            );
            await pumpFrames(tester, frames: 20);
            final SweepTools tools = SweepTools(tester);
            final String prefix =
                '${scene.name}-${mixed ? 'mixed' : 'unavailable'}-${expanded ? 'expanded' : 'compact'}';
            expect(tester.takeException(), isNull);
            await writeScene(tester, Scene(name: '$prefix-start'));
            for (final String key in <String>[
              'macro-total-calories',
              'minor-total-fiber',
            ]) {
              await _bring(tester, find.byKey(ValueKey<String>(key)));
              await writeScene(tester, Scene(name: '$prefix-$key'));
            }
            await tools.bring(
              find.byKey(const ValueKey<String>('meal-open-missing-history')),
            );
            expect(tester.takeException(), isNull);
            await writeScene(tester, Scene(name: '$prefix-missing-meal'));
            await _top(tester);
            await tools.bring(find.text(expanded ? 'Less' : 'Details'));
            await writeScene(tester, Scene(name: '$prefix-controls'));

            if (!expanded) {
              await tools.planView('Week');
              await tools.bring(
                find.byKey(
                  const ValueKey<String>('week-meal-open-missing-history'),
                ),
              );
              expect(find.text('Saved nutrition unavailable'), findsOneWidget);
              expect(tester.takeException(), isNull);
              await writeScene(tester, Scene(name: '$prefix-week-meal'));
              await _top(tester);
              await tools.weekContent('Nutrition');
              final Finder row = find.bySemanticsLabel(
                RegExp('Wednesday 9/30'),
              );
              await tools.bring(row);
              expect(tester.takeException(), isNull);
              await writeScene(tester, Scene(name: '$prefix-week-row'));
              final Rect visibleRow = tester
                  .getRect(row)
                  .intersect(tester.getRect(SweepTools.verticalScroller));
              await tester.tapAt(visibleRow.center);
              await pumpFrames(tester, frames: 12);
              await tools.bring(find.text('Open this day'));
              expect(tester.takeException(), isNull);
              await writeScene(tester, Scene(name: '$prefix-week-detail'));
              await tools.bring(
                find.textContaining(
                  'Saved nutrition unavailable for the weekly average.',
                ),
              );
              expect(tester.takeException(), isNull);
              await writeScene(tester, Scene(name: '$prefix-week-average'));
            }
          },
          skip: !renderingGallery,
        );
      }
    }

    for (final bool expanded in <bool>[false, true]) {
      testWidgets(
        '${scene.name} ${expanded ? 'expanded' : 'compact'}: totals and actions',
        (WidgetTester tester) async {
          final DateTime day = DateTime(2026, 9, 30);
          await pumpHearthApp(
            tester,
            size: scene.size,
            textScale: scene.textScale,
            brightness: scene.brightness,
            viewPadding: scene.size.width <= 320
                ? const EdgeInsets.only(top: 24, bottom: 34)
                : const EdgeInsets.only(top: 47, bottom: 34),
            launchTarget: LaunchTarget.today,
            selectedDate: day,
            foods: galleryFoods(),
            recipes: galleryRecipes(),
            entries: <MealPlanEntry>[
              MealPlanEntry(
                id: 'saved-oats',
                dayId: 'day-1',
                slot: MealSlot.breakfast,
                refType: PlanRefType.food,
                refId: 'f-oats',
                servings: 1,
                isLogged: true,
                macroSnapshot: MacroSnapshot(
                  label: 'Morning oats with berries',
                  servings: 1,
                  capturedAt: day.add(const Duration(hours: 8)),
                  macros: const Macros(
                    kcal: 450,
                    proteinG: 24,
                    carbG: 62,
                    fatG: 13,
                    fiberG: 8,
                    sodiumMg: 80,
                    cholesterolMg: 0,
                  ),
                  coverage: const NutrientCoverage.allComplete(),
                ),
              ),
              MealPlanEntry(
                id: 'saved-soup',
                dayId: 'day-1',
                slot: MealSlot.lunch,
                refType: PlanRefType.recipe,
                refId: 'r-soup',
                servings: 1,
                isLogged: true,
                macroSnapshot: MacroSnapshot(
                  label: 'Homemade mushroom soup',
                  servings: 1,
                  capturedAt: day.add(const Duration(hours: 12)),
                  macros: const Macros(
                    kcal: 150,
                    proteinG: 6,
                    carbG: 19,
                    fatG: 6,
                  ),
                ),
              ),
            ],
            targets: galleryTargets,
            extraOverrides: <Object>[
              bootDaySummaryExpandedProvider.overrideWithValue(expanded),
            ],
          );
          await pumpFrames(tester, frames: 20);
          final String prefix =
              '${scene.name}-${expanded ? 'expanded' : 'compact'}';
          expect(tester.takeException(), isNull);
          await writeScene(tester, Scene(name: '$prefix-start'));

          for (final String key in <String>[
            'macro-total-protein',
            'minor-total-fiber',
            'minor-total-cholesterol',
          ]) {
            final Finder action = find.byKey(ValueKey<String>(key));
            await _bring(tester, action);
            expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            await writeScene(tester, Scene(name: '$prefix-$key'));
          }
          await _bring(tester, find.text('This week’s targets · Change'));
          await writeScene(tester, Scene(name: '$prefix-targets'));
          await _bring(tester, find.text(expanded ? 'Less' : 'Details'));
          await writeScene(tester, Scene(name: '$prefix-layout-action'));

          final Finder fiber = find.byKey(
            const ValueKey<String>('minor-total-fiber'),
          );
          await _bring(tester, fiber);
          await tester.tap(fiber);
          await pumpFrames(tester, frames: 16);
          expect(
            tester
                .widget<NutrientContributorsScreen>(
                  find.byType(NutrientContributorsScreen),
                )
                .contributors
                .nutrient,
            SupportedNutrient.fiber,
          );
          expect(tester.takeException(), isNull);
          await writeScene(tester, Scene(name: '$prefix-receipt'));
        },
        skip: !renderingGallery,
      );
    }
  }
}
