@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'adjust-timer-phone'),
  Scene(name: 'adjust-timer-dark', brightness: Brightness.dark),
  Scene(name: 'adjust-timer-desktop', size: Size(1280, 900)),
  Scene(name: 'adjust-timer-small-3x', size: Size(320, 568), textScale: 3),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('Cook multiple timers at 320×568/3× ${brightness.name}', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime.now();
      final Recipe recipe = aRecipe(
        id: 'timer-supper',
        title: 'Beans and roast vegetables',
        ingredients: <RecipeIngredient>[
          anIngredient('white beans', amount: 2),
          anIngredient('carrots', amount: 4),
          anIngredient('potatoes', amount: 4),
          anIngredient('broccoli', amount: 1),
        ],
        steps: <RecipeStep>[
          aStep(
            'Simmer the white beans with garlic, rosemary and enough water '
            'to cover them, until soft and creamy.',
            stepNumber: 1,
            timerSeconds: 10800,
          ),
          aStep(
            'Roast the carrots until golden.',
            stepNumber: 2,
            timerSeconds: 600,
          ),
          aStep(
            'Roast the potatoes until crisp.',
            stepNumber: 3,
            timerSeconds: 600,
          ),
          aStep(
            'Steam the broccoli until tender.',
            stepNumber: 4,
            timerSeconds: 600,
          ),
        ],
      );
      await pumpHearthApp(
        tester,
        size: const Size(320, 568),
        textScale: 3,
        brightness: brightness,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        recipes: <Recipe>[recipe],
        timers: <CookTimer>[
          // Keep the earlier running timer first in storage order. The Cook
          // tray must still reveal the three later timers that have finished.
          CookTimer(
            id: 'slow',
            label: recipe.allSteps.first.text,
            duration: const Duration(hours: 3),
            startedAt: now.subtract(const Duration(hours: 1)),
            stepId: recipe.allSteps.first.id,
            stepNumber: 1,
          ),
          for (int index = 0; index < 3; index++)
            CookTimer(
              id: 'finished-$index',
              label: recipe.allSteps[index + 1].text,
              duration: const Duration(minutes: 10),
              startedAt: now.subtract(const Duration(minutes: 10, seconds: 1)),
              stepId: recipe.allSteps[index + 1].id,
              stepNumber: index + 2,
            ),
        ],
      );
      final SweepTools tools = SweepTools(tester);
      Navigator.of(
        tester.element(find.byType(Scaffold).first),
        rootNavigator: true,
      ).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => CookAlongScreen(recipe: recipe),
        ),
      );
      await pumpFrames(tester, frames: 12);
      expect(find.byType(CookAlongScreen), findsOneWidget);
      final String name = 'cook-multiple-timers-small-3x-${brightness.name}';
      final Finder tray = find.byKey(const ValueKey<String>('cook-timer-tray'));
      expect(tester.getSize(tray).height, lessThanOrEqualTo(160));
      expect(find.text('3 finished').hitTestable(), findsOneWidget);
      final Finder elapsed = find.descendant(
        of: find.byKey(const ValueKey<String>('timer-card-finished-0')),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Text &&
              RegExp(r'^\d+:\d\d ago$').hasMatch(widget.data ?? ''),
        ),
      );
      final Rect readoutBounds = tester.getRect(elapsed);
      final Rect timerViewport = tester.getRect(
        find.descendant(of: tray, matching: find.byType(ListView)),
      );
      expect(
        readoutBounds.intersect(timerViewport),
        readoutBounds,
        reason: 'The initial elapsed readout must be fully visible below the finished count.',
      );
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '$name-initial'));

      final Finder runningControl = find.byKey(
        const ValueKey<String>('timer-add-5-slow'),
      );
      await tools.bring(runningControl);
      expect(runningControl.hitTestable(), findsOneWidget);
      expect(find.text('3 finished').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '$name-running-control'));

      final Finder addTime = find.byKey(
        const ValueKey<String>('timer-add-1-finished-0'),
      );
      await tester.scrollUntilVisible(
        addTime,
        -120,
        scrollable: find
            .descendant(of: tray, matching: find.byType(Scrollable))
            .last,
        maxScrolls: 60,
      );
      await tools.reach(addTime);
      expect(find.text('2 finished').hitTestable(), findsOneWidget);
      expect(find.text('3 finished'), findsNothing);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '$name-restarted'));
    }, skip: !renderingGallery);
  }

  for (final Scene scene in _devices) {
    for (final String state in <String>['running', 'paused', 'finished']) {
      testWidgets('${scene.name}: $state timer can be adjusted', (
        WidgetTester tester,
      ) async {
        final DateTime now = DateTime.now();
        CookTimer timer = CookTimer(
          id: 'beans',
          label: 'Simmer the white beans',
          duration: const Duration(minutes: 10),
          startedAt: now.subtract(
            Duration(minutes: state == 'finished' ? 12 : 2),
          ),
        );
        if (state == 'paused') timer = timer.pausedAt(now);
        await pumpHearthApp(
          tester,
          size: scene.size,
          textScale: scene.textScale,
          brightness: scene.brightness,
          timers: <CookTimer>[timer],
          viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        );
        final SweepTools tools = SweepTools(tester);
        await tools.reach(find.textContaining(timer.label));
        expect(find.text('Timers'), findsOneWidget);
        final String name = '${scene.name}-$state';
        await writeScene(tester, Scene(name: '$name-card'));
        await tools.bring(
          find.byKey(const ValueKey<String>('timer-add-1-beans')),
        );
        await writeScene(tester, Scene(name: '$name-adjustments'));
        await tools.reach(
          find.byKey(const ValueKey<String>('timer-set-beans')),
        );
        expect(find.text('Minutes'), findsOneWidget);
        await writeScene(tester, Scene(name: '$name-set-time'));
        await tools.bring(find.text('Cancel'));
        await writeScene(tester, Scene(name: '$name-set-actions'));
        await tools.reach(find.text('Cancel'));
        await tools.reach(
          find.byKey(const ValueKey<String>('timer-add-1-beans')),
        );
        await tools.bring(
          find.byKey(const ValueKey<String>('timer-card-beans')),
        );
        await writeScene(tester, Scene(name: '$name-added-minute'));
        expect(tester.takeException(), isNull);
      }, skip: !renderingGallery);
    }
  }
}
