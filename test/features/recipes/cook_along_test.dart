import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';

import '../../support/fake_kitchen.dart';
import '../../support/fixtures.dart';

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
  List<CookTimer> timers = const <CookTimer>[],
}) async {
  final FakeScreenKeeper keeper = FakeScreenKeeper();
  final FakeTimerAlerts alerts = FakeTimerAlerts();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        screenKeeperProvider.overrideWithValue(keeper),
        timerAlertsProvider.overrideWithValue(alerts),
        cookTimersProvider.overrideWith(() => FakeCookTimers(timers)),
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
      final (FakeScreenKeeper keeper, _) = await pumpCookAlong(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(keeper.released, 1);
    });

    testWidgets('but leaving cook mode does not cancel the timers', (
      WidgetTester tester,
    ) async {
      // The braise keeps cooking whether or not you are looking at the recipe.
      // Cancelling on the way out was the bug: back out to check the planner
      // and an hour of cooking silently stopped being tracked.
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await tester.tap(find.text('Season the ribs generously'));
      await tester.pump();
      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(alerts.cancelAlls, 0);
      expect(alerts.cancelled, isEmpty);
      expect(
        alerts.scheduled,
        hasLength(1),
        reason: 'the scheduled alert must still be standing',
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

      expect(find.text('Step 2 of 3  ·  1 done'), findsOneWidget);
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

  group('a finished timer', () {
    testWidgets('cannot be paused — only stopped', (WidgetTester tester) async {
      // Seeded already overdue rather than pumped forward: the screen reads
      // the real wall clock, which a widget test cannot move.
      await pumpCookAlong(
        tester,
        timers: <CookTimer>[
          CookTimer(
            id: 'blanch',
            label: 'Blanch',
            duration: const Duration(seconds: 10),
            startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ],
      );
      await tester.pump();

      final IconButton pause = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.pause),
          matching: find.byType(IconButton),
        ),
      );
      expect(pause.onPressed, isNull);
      expect(find.byTooltip('Stop timer'), findsOneWidget);
    });
  });

  group('the step in focus', () {
    testWidgets('sits in the middle of the space it has', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);

      final double stepCentre = tester
          .getCenter(find.text('Season the ribs generously'))
          .dy;
      final double screenCentre =
          tester.getSize(find.byType(Scaffold)).height / 2;

      expect(
        (stepCentre - screenCentre).abs(),
        lessThan(120),
        reason:
            'the step should read as the subject of the screen, not as a '
            'caption above a lot of empty space',
      );
    });

    testWidgets('a long step scrolls rather than overflowing', (
      WidgetTester tester,
    ) async {
      // Centring is exactly where this breaks: a centred child that cannot
      // shrink overflows at both ends instead of scrolling.
      await pumpCookAlong(
        tester,
        recipe: aRecipe(
          steps: <RecipeStep>[
            aStep(
              'Season the ribs generously on every side, then leave them '
              'uncovered in the fridge for at least an hour so the surface '
              'dries out, which is what lets them take on a proper crust '
              'when they hit the pan rather than steaming in their own '
              'moisture and going grey.',
              stepNumber: 1,
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('all-steps view', () {
    Future<void> showList(WidgetTester tester) async {
      await tester.tap(find.byTooltip('All steps'));
      await tester.pump();
    }

    testWidgets('shows every step at once, not just the one in focus', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);
      expect(find.textContaining('Sear until browned'), findsNothing);

      await showList(tester);

      expect(find.textContaining('Season the ribs generously'), findsOneWidget);
      expect(find.textContaining('Sear until browned'), findsOneWidget);
      expect(find.textContaining('Serve over polenta'), findsOneWidget);
    });

    testWidgets('drops Back and Next, which mean nothing here', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);
      expect(find.widgetWithText(OutlinedButton, 'Next'), findsOneWidget);

      await showList(tester);

      expect(find.widgetWithText(OutlinedButton, 'Next'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsNothing);
    });

    testWidgets('ticking a step off does not jump to it', (
      WidgetTester tester,
    ) async {
      // The check is its own target precisely so that scanning the list and
      // marking something done are two different actions.
      await pumpCookAlong(tester);
      await showList(tester);

      await tester.tap(find.byTooltip('Mark done').last);
      await tester.pump();

      expect(find.text('Step 1 of 3  ·  1 done'), findsOneWidget);
      expect(
        find.byTooltip('One step at a time'),
        findsOneWidget,
        reason: 'still in the list, not thrown back into the card',
      );
    });

    testWidgets('tapping a step cooks from there', (WidgetTester tester) async {
      await pumpCookAlong(tester);
      await showList(tester);

      await tester.tap(find.textContaining('Serve over polenta'));
      await tester.pump();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(
        find.byTooltip('All steps'),
        findsOneWidget,
        reason: 'the list is how you reach a step, not somewhere to stay',
      );
    });

    testWidgets('a timer can be started without leaving the list', (
      WidgetTester tester,
    ) async {
      final (_, FakeTimerAlerts alerts) = await pumpCookAlong(tester);
      await showList(tester);

      await tester.tap(find.text('Start 10 min timer'));
      await tester.pump();

      expect(alerts.scheduled, hasLength(1));
    });

    testWidgets('the step you are on is marked, and not by colour alone', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpCookAlong(tester);
      await showList(tester);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel(RegExp('Step 1. Season the ribs')),
        ),
        matchesSemantics(
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          hasTapAction: true,
          label: 'Step 1. Season the ribs generously. Tap to cook from here.',
        ),
      );
      handle.dispose();
    });
  });

  group('the progress header', () {
    testWidgets('is centred over the step', (WidgetTester tester) async {
      await pumpCookAlong(tester);

      final double headerCentre = tester.getCenter(find.text('Step 1 of 3')).dx;
      final double screenCentre =
          tester.getSize(find.byType(Scaffold)).width / 2;

      expect((headerCentre - screenCentre).abs(), lessThan(2));
    });

    testWidgets('carries the done count on the same line', (
      WidgetTester tester,
    ) async {
      await pumpCookAlong(tester);
      expect(find.text('Step 1 of 3'), findsOneWidget);

      await tester.tap(find.text('Mark done'));
      await tester.pump();

      expect(find.text('Step 2 of 3  ·  1 done'), findsOneWidget);
    });
  });
}
