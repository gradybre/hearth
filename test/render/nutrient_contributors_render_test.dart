@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/features/plan/nutrient_contributors_screen.dart';

import 'gallery.dart';

MealPlanEntry _meal({
  required String id,
  required String name,
  double? amount,
  MinorCoverage coverage = MinorCoverage.complete,
  bool snapshot = true,
  bool approximate = false,
}) => MealPlanEntry(
  id: id,
  dayId: 'captured-day',
  slot: id == 'oats' ? MealSlot.breakfast : MealSlot.lunch,
  refType: PlanRefType.recipe,
  refId: id,
  servings: 99,
  isLogged: true,
  macroSnapshot: snapshot
      ? MacroSnapshot(
          label: name,
          servings: 1.5,
          capturedAt: DateTime(2026, 9, 30, 8, 30),
          macros: Macros(
            kcal: amount ?? 0,
            proteinG: amount ?? 0,
            carbG: amount ?? 0,
            fatG: amount ?? 0,
            fiberG: amount,
            sodiumMg: amount,
            cholesterolMg: amount,
          ),
          coverage: NutrientCoverage(<MinorNutrient, MinorCoverage>{
            for (final MinorNutrient nutrient in MinorNutrient.values)
              nutrient: coverage,
          }),
          usesApproximatePackageNutrition: approximate,
        )
      : null,
);

Future<void> _bring(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 120,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in const <Scene>[
    Scene(name: 'nutrient-contributors-phone'),
    Scene(name: 'nutrient-contributors-dark', brightness: Brightness.dark),
    Scene(name: 'nutrient-contributors-desktop', size: Size(1280, 900)),
    Scene(
      name: 'nutrient-contributors-small-3x',
      size: Size(320, 568),
      textScale: 3,
    ),
    Scene(
      name: 'nutrient-contributors-small-3x-dark',
      size: Size(320, 568),
      textScale: 3,
      brightness: Brightness.dark,
    ),
  ]) {
    for (final String state in <String>[
      'partial',
      'legacy',
      'empty',
      'unknown',
      'signed',
      'fractional',
    ]) {
      testWidgets('${scene.name} $state', (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scene.size;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.platformDispatcher.textScaleFactorTestValue = scene.textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final List<MealPlanEntry> entries = switch (state) {
          'empty' => <MealPlanEntry>[],
          'unknown' => <MealPlanEntry>[
            _meal(
              id: 'unknown',
              name: 'Roasted vegetable bowl',
              coverage: MinorCoverage.unknown,
            ),
            _meal(
              id: 'absent',
              name: 'Must never be displayed',
              snapshot: false,
            ),
          ],
          'signed' => <MealPlanEntry>[
            _meal(id: 'oats', name: 'Morning oats with berries', amount: 8),
            _meal(
              id: 'deduction',
              name: 'Saved restaurant adjustment',
              amount: -2,
            ),
          ],
          'fractional' => <MealPlanEntry>[
            _meal(
              id: 'oats',
              name: 'Morning oats with berries',
              amount: 11.266666666666667,
            ),
            _meal(id: 'one', name: 'A little extra fruit', amount: 0.1),
            _meal(id: 'two', name: 'A spoonful of seeds', amount: 0.2),
          ],
          _ => <MealPlanEntry>[
            _meal(id: 'oats', name: 'Morning oats with berries', amount: 6),
            _meal(
              id: 'bowl',
              name: 'Roasted vegetable bowl',
              amount: 3,
              coverage: state == 'legacy'
                  ? MinorCoverage.notRecorded
                  : MinorCoverage.partial,
              approximate: true,
            ),
            _meal(
              id: 'unknown',
              name: 'Homemade mushroom soup',
              coverage: MinorCoverage.unknown,
            ),
          ],
        };
        final DailyNutrientContributors projection = DailyNutrientContributors(
          date: DateTime(2026, 9, 30),
          nutrient: scene.brightness == Brightness.dark
              ? SupportedNutrient.cholesterol
              : SupportedNutrient.fiber,
          entries: entries,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: scene.brightness == Brightness.light
                ? HearthTheme.light()
                : HearthTheme.dark(),
            home: NutrientContributorsScreen(
              contributors: projection,
              onOpenLoggedDetails: (_) async {},
              onImproveFuture: (_) async {},
              isSourceAvailable: (MealPlanEntry entry) => entry.id != 'unknown',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final String prefix = '${scene.name}-$state';
        await writeScene(tester, Scene(name: '$prefix-start'));
        if (state == 'fractional') {
          await _bring(
            tester,
            find.text('about 11.5667 ${projection.nutrient.unit}'),
          );
          await writeScene(tester, Scene(name: '$prefix-qualified-total'));
          await _bring(
            tester,
            find.text('about 11.2667 ${projection.nutrient.unit}'),
          );
          await writeScene(tester, Scene(name: '$prefix-qualified-amount'));
        }
        if (projection.knownContributors.isNotEmpty) {
          final String firstId = projection.knownContributors.first.entry.id;
          final Finder first = find.byKey(
            ValueKey<String>('contributor-known-open-$firstId'),
          );
          await _bring(
            tester,
            find.descendant(
              of: first,
              matching: find.text('View logged details'),
            ),
          );
          await writeScene(tester, Scene(name: '$prefix-saved-meal'));
          if (state == 'signed') {
            await _bring(
              tester,
              find.text(projection.nutrient.unit == 'g' ? '-2 g' : '-2 mg'),
            );
            await writeScene(tester, Scene(name: '$prefix-signed-amount'));
          }
        }
        if (projection.missingInformation.isNotEmpty) {
          await _bring(tester, find.text('Missing information'));
          await writeScene(tester, Scene(name: '$prefix-missing'));
          for (final NutrientContributor row in projection.missingInformation) {
            if (row.entry.id == 'unknown') {
              await _bring(
                tester,
                find.text(
                  'The current recipe is unavailable. This saved log is unchanged.',
                ),
              );
              await writeScene(tester, Scene(name: '$prefix-unavailable'));
            } else {
              final Finder action = find.byKey(
                ValueKey<String>('contributor-missing-improve-${row.entry.id}'),
              );
              await _bring(tester, action);
              final Rect actionBounds = tester.getRect(action);
              expect(actionBounds.top, greaterThanOrEqualTo(24));
              expect(
                actionBounds.bottom,
                lessThanOrEqualTo(scene.size.height - 34),
              );
              await writeScene(tester, Scene(name: '$prefix-future-action'));
            }
          }
        }
        expect(tester.takeException(), isNull);
      }, skip: !renderingGallery);
    }
  }
}
