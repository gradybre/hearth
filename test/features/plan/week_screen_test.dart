import 'package:flutter_test/flutter_test.dart';

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

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets('the week lists all seven days, Monday first', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      // Identified by date rather than by weekday name: today's row says
      // "Today" where the others say "Mon", which is the point of the label.
      final DateTime now = DateTime.now();
      final DateTime monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));

      for (int i = 0; i < 7; i++) {
        final DateTime day = monday.add(Duration(days: i));
        expect(
          find.text('${day.month}/${day.day}'),
          findsOneWidget,
          reason: 'day $i',
        );
      }
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('a date says which month it is in', (
      WidgetTester tester,
    ) async {
      // Brendan's report: the list showed a bare "1", which is unreadable in
      // a week that straddles two months — the row above it might be the
      // 30th of August.
      await openPlan(tester);
      await showWeek(tester);

      final DateTime now = DateTime.now();
      expect(find.text('${now.month}/${now.day}'), findsOneWidget);
      expect(find.text('${now.day}'), findsNothing);
    });

    testWidgets('an empty week says so rather than showing zeros', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      expect(find.text('Nothing logged this week yet.'), findsOneWidget);
      expect(find.text('nothing logged'), findsNWidgets(7));
    });

    testWidgets('tapping a day drops back into the day view', (
      WidgetTester tester,
    ) async {
      await openPlan(tester);
      await showWeek(tester);

      await tester.tap(find.text('Wed'));
      await pumpFrames(tester);

      // Back on the day, where things actually get logged.
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
