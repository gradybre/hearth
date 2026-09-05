import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/features/recipes/timer_bar.dart';

import '../../support/app_harness.dart';

CookTimer aTimer({
  String id = 'timer-1',
  String label = 'Cover and cook',
  Duration duration = const Duration(hours: 3),
  Duration ago = Duration.zero,
  Duration? pausedAfter,
}) => CookTimer(
  id: id,
  label: label,
  duration: duration,
  startedAt: DateTime.now().subtract(ago),
  elapsedWhenPaused: pausedAfter,
);

void main() {
  group('a running timer is visible from anywhere (spec §5.2)', () {
    testWidgets('nothing is shown when nothing is on', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      expect(find.byType(CookTimerBar), findsOneWidget);
      expect(find.textContaining(':'), findsNothing);
    });

    testWidgets('a timer shows on the recipe tab, where it was not started', (
      WidgetTester tester,
    ) async {
      // A timer you cannot see from the rest of the app is a timer you have to
      // remember, and remembering is the job it was for.
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[aTimer(ago: const Duration(minutes: 1))],
      );
      await pumpFrames(tester);

      expect(find.text('Cover and cook'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^2:5\d:\d\d$')), findsOneWidget);
    });

    testWidgets('and still shows after switching to the planner', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[aTimer(ago: const Duration(minutes: 1))],
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Plan'));
      await pumpFrames(tester);

      expect(find.text('Cover and cook'), findsOneWidget);
    });

    testWidgets('and does not go out when you leave the section for home', (
      WidgetTester tester,
    ) async {
      // "Anywhere" has to include the home screen, which is above the shell
      // rather than inside it: going home is a route swap, so the shell — and
      // the bar it carries — is unmounted on the way. Set a twenty-minute
      // timer, tap Home, and the pot goes out of sight.
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(
            label: 'Cover and cook',
            duration: const Duration(minutes: 20),
            ago: const Duration(minutes: 1),
          ),
        ],
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Home'));
      await pumpFrames(tester, frames: 10);

      expect(find.textContaining('Still being built'), findsOneWidget);
      expect(
        find.text('Cover and cook'),
        findsOneWidget,
        reason: 'the running timer dropped out of sight on the home screen',
      );
      expect(find.textContaining(RegExp(r'^18:5\d$')), findsOneWidget);
    });

    testWidgets('several timers collapse to the most urgent plus a count', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(id: 'oven', label: 'Oven', duration: const Duration(hours: 3)),
          aTimer(
            id: 'pasta',
            label: 'Pasta',
            duration: const Duration(minutes: 9),
          ),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Pasta'), findsOneWidget, reason: 'the soonest');
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('a paused timer never counts as the most urgent', (
      WidgetTester tester,
    ) async {
      // It is not waiting on anything.
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(
            id: 'paused',
            label: 'Paused thing',
            duration: const Duration(minutes: 1),
            pausedAfter: Duration.zero,
          ),
          aTimer(id: 'oven', label: 'Oven', duration: const Duration(hours: 3)),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Oven'), findsOneWidget);
      expect(find.text('Paused thing'), findsNothing);
    });
  });

  group('a finished timer', () {
    testWidgets('says so rather than showing a countdown at zero', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(
            label: 'Pasta',
            duration: const Duration(minutes: 9),
            ago: const Duration(minutes: 10),
          ),
        ],
      );
      await pumpFrames(tester);

      expect(find.text('Pasta — time is up'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('is announced, not only coloured', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(
            label: 'Pasta',
            duration: const Duration(minutes: 9),
            ago: const Duration(minutes: 10),
          ),
        ],
      );
      await pumpFrames(tester);

      expect(
        find.bySemanticsLabel(RegExp('Pasta timer is up')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('opening the timers', () {
    testWidgets('tapping the bar lists every timer with its controls', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        timers: <CookTimer>[
          aTimer(id: 'oven', label: 'Oven'),
          aTimer(
            id: 'pasta',
            label: 'Pasta',
            duration: const Duration(minutes: 9),
          ),
        ],
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Pasta'));
      await pumpFrames(tester, frames: 10);

      expect(find.text('Timers'), findsOneWidget);
      expect(find.byTooltip('Stop timer'), findsNWidgets(2));
      expect(find.byTooltip('Pause timer'), findsNWidgets(2));
    });
  });

  group('durations read the way a cook says them', () {
    test('a countdown breaks out hours once there are any', () {
      expect(
        countdown(const Duration(hours: 2, minutes: 59, seconds: 57)),
        '2:59:57',
      );
      expect(countdown(const Duration(minutes: 9, seconds: 5)), '9:05');
      expect(countdown(Duration.zero), '0:00');
    });

    test('a screen reader is not read a row of colons', () {
      expect(
        spokenDuration(const Duration(hours: 2, minutes: 30)),
        '2 hours 30 minutes',
      );
      expect(spokenDuration(const Duration(hours: 3)), '3 hours');
      expect(spokenDuration(const Duration(minutes: 9)), '9 minutes');
      expect(spokenDuration(const Duration(seconds: 30)), '30 seconds');
    });
  });
}
