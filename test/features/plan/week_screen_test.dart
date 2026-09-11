import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/planning/week.dart';

import '../../support/app_harness.dart';

Future<void> openPlan(WidgetTester tester) async {
  await pumpHearthApp(tester);
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester);
}

Future<void> showWeek(WidgetTester tester) async {
  await tester.tap(find.text('Week'));
  await pumpFrames(tester);
}

void main() {
  group('the plan section', () {
    testWidgets('opens on the day, not the week', (WidgetTester tester) async {
      // Logging is the loop the app is judged on; the week is the step back.
      await openPlan(tester);

      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    testWidgets('offers both views', (WidgetTester tester) async {
      await openPlan(tester);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
    });

    testWidgets('switching to the week shows the summary', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);

      await showWeek(tester);

      // The week is named by the toggle above it and dated by its range;
      // there is no page title under either any more (review §6.2.1).
      expect(find.textContaining('–'), findsWidgets);
      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets('the week carries all seven days, Monday first', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      final DateTime now = DateTime.now();
      final DateTime monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));

      for (int i = 0; i < 7; i++) {
        final DateTime day = monday.add(Duration(days: i));
        expect(
          find.bySemanticsLabel(RegExp('${day.month}/${day.day}[.,]')),
          findsOneWidget,
          reason: 'day $i should have a row',
        );
      }
      // Monday first, whatever today happens to be (spec §5.6).
      expect(find.bySemanticsLabel(RegExp('^Monday ')), findsOneWidget);
    });

    testWidgets('today is named, in the row and in its label', (
      WidgetTester tester,
    ) async {
      // A row has the width for it now, so "Today" is on the screen as well
      // as in the label — the weight it is drawn in was never the only
      // signal, and now it is not a signal at all (§6.3).
      await openPlan(tester);
      await showWeek(tester);

      expect(find.bySemanticsLabel(RegExp(', today[.]')), findsOneWidget);
      expect(find.textContaining('· Today'), findsOneWidget);
    });

    testWidgets('a date says which month it is in', (
      WidgetTester tester,
    ) async {
      // Brendan's report: a bare "1" is unreadable in a week that straddles
      // two months — the day before it might be the 30th of August. The strip
      // shows the numeral, so the month lives in the spoken label and in the
      // card's own title.
      await openPlan(tester);
      await showWeek(tester);

      final DateTime now = DateTime.now();
      expect(
        find.bySemanticsLabel(RegExp('${now.month}/${now.day}, today')),
        findsOneWidget,
      );
    });

    testWidgets('an empty week says so rather than showing zeros', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      expect(find.text('Nothing logged this week yet.'), findsOneWidget);
      // One per day, and all seven of them say the same thing: nobody has
      // logged anything. A day logged as nothing would read differently.
      expect(find.text('nothing logged'), findsNWidgets(7));
      expect(find.text('logged as nothing'), findsNothing);
    });

    testWidgets('tapping a day selects it without leaving the week', (
      WidgetTester tester,
    ) async {
      // The point of a strip: look across the week without going into it.
      await openPlan(tester);
      await showWeek(tester);

      final DateTime now = DateTime.now();
      final DateTime monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final DateTime other = isSameDay(monday, now)
          ? monday.add(const Duration(days: 1))
          : monday;

      await tester.tap(
        find.bySemanticsLabel(RegExp('${other.month}/${other.day}[.,]')),
      );
      await pumpFrames(tester);

      expect(find.text('Breakfast'), findsNothing);
      // Still on the week, and the row that was tapped has opened in place.
      expect(find.text('Open this day'), findsOneWidget);
    });

    testWidgets('and the way into logging is said out loud', (
      WidgetTester tester,
    ) async {
      // A row selects and expands rather than navigating, so the day view
      // needs a door rather than a hint that tapping a row would take you
      // there.
      await openPlan(tester);
      await showWeek(tester);

      await tester.tap(find.bySemanticsLabel(RegExp(', today[.]')));
      await pumpFrames(tester);
      await tester.tap(find.text('Open this day'));
      await pumpFrames(tester);

      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });
  });

  group('accessibility (spec §6.3)', () {
    testWidgets('the week meets the tap-target guidelines', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      final SemanticsHandle handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });
  });
}
