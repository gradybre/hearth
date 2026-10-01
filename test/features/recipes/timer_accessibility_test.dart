import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/timer_bar.dart';

import '../../support/app_harness.dart';
import '../../support/fake_kitchen.dart';
import '../../support/fixtures.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool cooking,
  required bool finished,
  String label = 'Simmer the pasta',
  Brightness brightness = Brightness.light,
  List<CookTimer>? timers,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final CookTimer timer = CookTimer(
    id: 'pasta',
    label: label,
    duration: const Duration(minutes: 10),
    startedAt: DateTime.now().subtract(Duration(minutes: finished ? 12 : 2)),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cookTimersProvider.overrideWith(
          () => FakeCookTimers(timers ?? <CookTimer>[timer]),
        ),
        screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
        timerAlertsProvider.overrideWithValue(FakeTimerAlerts()),
        cookSessionStoreProvider.overrideWithValue(FakeCookSessionStore()),
        cookShowAllStepsProvider.overrideWith(FakeCookStepView.new),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? HearthTheme.dark()
            : HearthTheme.light(),
        home: cooking
            ? CookAlongScreen(
                recipe: aRecipe(
                  title: 'Pasta',
                  steps: <RecipeStep>[aStep('Simmer the pasta until tender.')],
                ),
              )
            : Scaffold(
                body: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => showCookTimersSheet(context),
                    child: const Text('Open timers'),
                  ),
                ),
              ),
      ),
    ),
  );
  await pumpFrames(tester);
  if (!cooking) {
    await tester.tap(find.text('Open timers'));
    await pumpFrames(tester, frames: 12);
  }
}

void main() {
  for (final int finishedCount in <int>[1, 3]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('Cook keeps $finishedCount finished timers visible after a long '
          'running timer at 320×568/3× ${brightness.name}', (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final DateTime now = DateTime.now();
        final List<CookTimer> timers = <CookTimer>[
          CookTimer(
            id: 'slow',
            label:
                'Heat 1 tablespoon neutral oil in a large heavy skillet, '
                'then simmer the pasta until it is tender and the sauce is thick.',
            duration: const Duration(hours: 3),
            startedAt: now.subtract(const Duration(hours: 1)),
          ),
          for (int index = 0; index < finishedCount; index++)
            CookTimer(
              id: 'finished-$index',
              label: 'Roast vegetables in pan ${index + 1}',
              duration: const Duration(minutes: 10),
              startedAt: now.subtract(const Duration(minutes: 10, seconds: 1)),
            ),
        ];
        await _pump(
          tester,
          cooking: true,
          finished: false,
          brightness: brightness,
          timers: timers,
        );
        final Finder notice = find.text('$finishedCount finished');
        expect(
          notice.hitTestable(),
          findsOneWidget,
          reason:
              'Later timers finishing must be visible without scrolling '
              'past the earlier running timer.',
        );
        expect(
          tester.getSemantics(notice),
          isSemantics(
            isLiveRegion: true,
            label:
                '$finishedCount ${finishedCount == 1 ? 'timer has' : 'timers have'} finished. '
                '${timers.skip(1).map((CookTimer timer) => timer.label).join('. ')}.',
          ),
        );
        final Finder tray = find.byKey(
          const ValueKey<String>('cook-timer-tray'),
        );
        final Finder scroll = find.descendant(
          of: tray,
          matching: find.byType(ListView),
        );
        final Rect noticeBounds = tester.getRect(notice);
        final Rect scrollBounds = tester.getRect(scroll);
        final Finder elapsed = find.descendant(
          of: find.byKey(const ValueKey<String>('timer-card-finished-0')),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Text &&
                RegExp(r'^\d+:\d\d ago$').hasMatch(widget.data ?? ''),
          ),
        );
        expect(elapsed, findsOneWidget);
        final Rect elapsedBounds = tester.getRect(elapsed);
        expect(
          elapsedBounds.intersect(scrollBounds),
          elapsedBounds,
          reason:
              'The complete elapsed readout must fit initially below '
              'the fixed finished notice. Viewport: $scrollBounds; elapsed: $elapsedBounds',
        );
        expect(elapsed.hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(elapsed).label,
          contains('${timers[1].label} timer is up.'),
        );
        expect(scrollBounds.bottom - noticeBounds.top, lessThanOrEqualTo(160));
        expect(tester.getSize(tray).height, lessThanOrEqualTo(160));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('timer-set-slow')),
          150,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 100,
        );
        await pumpFrames(tester);
        expect(
          notice.hitTestable(),
          findsOneWidget,
          reason: 'The finished notice must remain visible while another timer is inspected.',
        );
        final Finder setTime = find.byKey(
          const ValueKey<String>('timer-set-slow'),
        );
        expect(setTime.hitTestable(), findsOneWidget);
        await tester.tap(setTime);
        await pumpFrames(tester, frames: 12);
        expect(find.text('Minutes'), findsOneWidget);
        expect(find.text(timers.first.label), findsAtLeastNWidgets(1));
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester, frames: 12);
        final Finder addTime = find.byKey(
          const ValueKey<String>('timer-add-1-finished-0'),
        );
        await tester.scrollUntilVisible(
          addTime,
          -150,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 100,
        );
        await pumpFrames(tester);
        await tester.tap(addTime.hitTestable());
        await pumpFrames(tester);
        if (finishedCount == 1) {
          expect(
            find.byKey(const ValueKey<String>('cook-finished-timers')),
            findsNothing,
          );
        } else {
          expect(
            find.text('${finishedCount - 1} finished').hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }

  for (final bool finished in <bool>[false, true]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets(
        'Cook immediately shows ${finished ? 'finished' : 'running'} timer state '
        'with a long label at 320×568/3× ${brightness.name}',
        (WidgetTester tester) async {
          await _pump(
            tester,
            cooking: true,
            finished: finished,
            brightness: brightness,
            label:
                'Heat 1 tablespoon neutral oil in a large heavy skillet, '
                'then simmer the pasta until it is tender and the sauce is thick.',
          );
          final Finder card = find.byKey(
            const ValueKey<String>('timer-card-pasta'),
          );
          final Finder tray = find
              .ancestor(of: card, matching: find.byType(ListView))
              .first;
          final Finder status = find.descendant(
            of: card,
            matching: find.text(finished ? 'Time is up' : 'Running'),
          );
          final Finder clock = find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget is Text &&
                  RegExp(r'^\d+:\d\d(?: ago)?$').hasMatch(widget.data ?? ''),
            ),
          );
          expect(status, findsOneWidget);
          expect(clock, findsOneWidget);
          final Rect viewport = tester.getRect(tray);
          for (final Finder information in <Finder>[status, clock]) {
            final Rect bounds = tester.getRect(information);
            expect(
              bounds.intersect(viewport),
              bounds,
              reason:
                  'Timer status and time must be fully visible before '
                  'scrolling. Viewport: $viewport; information: $bounds',
            );
            expect(information.hitTestable(), findsOneWidget);
          }
          expect(
            viewport.height,
            lessThanOrEqualTo(160),
            reason: 'Timer details must preserve room for the recipe.',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final bool cooking in <bool>[false, true]) {
    for (final bool finished in <bool>[false, true]) {
      testWidgets('${cooking ? 'Cook' : 'Timers sheet'} with a '
          '${finished ? 'finished' : 'running'} timer fits at 320×568 and 3×', (
        WidgetTester tester,
      ) async {
        await _pump(tester, cooking: cooking, finished: finished);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
