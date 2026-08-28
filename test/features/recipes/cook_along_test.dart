import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/kitchen_devices.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../../support/fixtures.dart';

/// Records what cook mode asked of the platform.
class FakeScreenKeeper implements ScreenKeeper {
  int awake = 0;
  int released = 0;

  @override
  Future<void> keepAwake() async => awake++;

  @override
  Future<void> release() async => released++;
}

class FakeTimerAlerts implements TimerAlerts {
  final List<String> scheduled = <String>[];
  final List<String> cancelled = <String>[];
  final List<DateTime> firesAt = <DateTime>[];
  int permissionRequests = 0;
  int cancelAlls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    scheduled.add(id);
    firesAt.add(at);
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAlls++;
}

Recipe aCookableRecipe() => aRecipe(
  title: 'Braised short ribs',
  ingredients: <RecipeIngredient>[
    anIngredient('olive oil', amount: 2, unit: Units.tbsp),
  ],
  steps: <RecipeStep>[
    aStep('Season the ribs generously', stepNumber: 1),
    aStep('Sear until browned', stepNumber: 2, timerSeconds: 600),
    aStep('Serve over polenta', stepNumber: 3),
  ],
);

Future<(FakeScreenKeeper, FakeTimerAlerts)> pumpCookAlong(
  WidgetTester tester, {
  Recipe? recipe,
}) async {
  final FakeScreenKeeper keeper = FakeScreenKeeper();
  final FakeTimerAlerts alerts = FakeTimerAlerts();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenKeeperProvider.overrideWithValue(keeper),
        timerAlertsProvider.overrideWithValue(alerts),
      ],
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: CookAlongScreen(recipe: recipe ?? aCookableRecipe()),
      ),
    ),
  );
  await tester.pump();
  return (keeper, alerts);
}

void main() {
  group('the screen stays awake (spec §5.2)', () {
    testWidgets('cook mode asks for it on the way in', (
      WidgetTester tester,
    ) async {
      final (FakeScreenKeeper keeper, _) = await pumpCookAlong(tester);
      expect(keeper.awake, 1);
      expect(keeper.released, 0);
    });

    testWidgets('and hands it back however the screen closes', (
      WidgetTester tester,
    ) async {
      // Including a back gesture: a phone left awake in a pocket is a flat
      // battery by evening.
      final (FakeScreenKeeper keeper, FakeTimerAlerts alerts) =
          await pumpCookAlong(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(keeper.released, 1);
      expect(
        alerts.cancelAlls,
        1,
        reason: 'an alert for a session nobody is in is just noise',
      );
    });
  });

  group('steps', () {
    testWidgets('opens on the first step, one in focus', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Season the ribs generously'), findsOneWidget);
      expect(find.text('Sear until browned'), findsNothing);
    });

    testWidgets('tapping the card anywhere advances', (
      WidgetTester tester,
    ) async {
      // Messy hands should not have to aim at a button.
      await pumpCookAlong(tester);

      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();

      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('marking done ticks the step and moves on', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);

      await tester.tap(find.text('Mark done'));
      await tester.pump();

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('1 done'), findsOneWidget);
    });

    testWidgets('Back is unavailable on the first step', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);

      final Finder back = find.widgetWithText(OutlinedButton, 'Back');
      expect(tester.widget<OutlinedButton>(back).onPressed, isNull);
    });
  });

  group('timers', () {
    testWidgets('a step with a timer offers to start it', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);
      expect(find.textContaining('Start'), findsNothing);

      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();

      expect(find.text('Start 10 min timer'), findsOneWidget);
    });

    testWidgets('starting one schedules an alert that outlives the app', (
      WidgetTester tester,
    ) async {
      // The phone goes face down on the counter and the cook walks away — an
      // in-app countdown cannot reach them there.
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();

      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      expect(alerts.scheduled, hasLength(1));
      expect(alerts.permissionRequests, 1);
      expect(
        alerts.firesAt.single.difference(DateTime.now()).inMinutes,
        closeTo(10, 1),
      );
    });

    testWidgets('permission is asked once, at the stove', (
      WidgetTester tester,
    ) async {
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();

      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      expect(alerts.scheduled, hasLength(2));
      expect(alerts.permissionRequests, 1);
    });

    testWidgets('several run side by side', (WidgetTester tester) async {
      await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();

      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      expect(find.byTooltip('Pause timer'), findsNWidgets(2));
    });

    testWidgets('pausing rewrites the scheduled alert rather than leaving it', (
      WidgetTester tester,
    ) async {
      // A paused timer that still goes off is worse than no timer at all.
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      await tester.tap(find.byTooltip('Pause timer'));
      await tester.pump();

      expect(alerts.cancelled, hasLength(1));
      expect(
        alerts.scheduled,
        hasLength(1),
        reason: 'a paused timer has nothing to schedule',
      );
      expect(find.byTooltip('Resume timer'), findsOneWidget);
    });

    testWidgets('stopping one cancels its alert and leaves the rest', (
      WidgetTester tester,
    ) async {
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      await tester.tap(find.byTooltip('Stop timer').first);
      await tester.pump();

      expect(alerts.cancelled, hasLength(1));
      expect(find.byTooltip('Pause timer'), findsOneWidget);
    });
  });

  group('ingredients stay reachable', () {
    testWidgets('without leaving the step you are on', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);

      await tester.tap(find.byTooltip('Ingredients'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('olive oil'), findsOneWidget);

      await tester.tap(find.text('Back to cooking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Step 1 of 3'), findsOneWidget);
    });
  });

  group('a recipe with no steps', () {
    testWidgets('says so rather than showing an empty card', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester, recipe: aRecipe(title: 'Just a note'));
      expect(
        find.text('This recipe has no steps to cook along with.'),
        findsOneWidget,
      );
    });
  });

  group('a kitchen reads hours as hours', () {
    testWidgets('a three-hour braise is not offered as "180 min"', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(
        tester,
        recipe: aRecipe(
          steps: <RecipeStep>[
            aStep('Cover and cook', stepNumber: 1, timerSeconds: 10800),
          ],
        ),
      );

      expect(find.text('Start 3 hr timer'), findsOneWidget);
    });

    testWidgets('and its countdown breaks the hours out', (
      WidgetTester tester,
    ) async {
      // "179:57" is not a number anyone reads as most of three hours.
      await pumpCookAlong(
        tester,
        recipe: aRecipe(
          steps: <RecipeStep>[
            aStep('Cover and cook', stepNumber: 1, timerSeconds: 10800),
          ],
        ),
      );

      await tester.tap(find.text('Start 3 hr timer'));
      await tester.pump();

      expect(find.textContaining(RegExp(r'^2:59:\d\d$')), findsOneWidget);
    });

    testWidgets('the timer label keeps the part that matters', (
      WidgetTester tester,
    ) async {
      // Splitting on punctuation turned "Cover and cook for approx. 3 hr."
      // into "Cover and cook for approx".
      await pumpCookAlong(
        tester,
        recipe: aRecipe(
          steps: <RecipeStep>[
            aStep(
              'Cover and cook for approx. 3 hr.',
              stepNumber: 1,
              timerSeconds: 10800,
            ),
          ],
        ),
      );

      await tester.tap(find.text('Start 3 hr timer'));
      await tester.pump();

      // Twice: once on the step card, once on the timer in the tray. The
      // point is that neither reads "Cover and cook for approx".
      expect(find.text('Cover and cook for approx. 3 hr.'), findsNWidgets(2));
      expect(find.text('Cover and cook for approx'), findsNothing);
    });
  });
}
