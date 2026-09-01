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

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets('the strip carries all seven days, Monday first', (
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
          reason: 'day $i should be in the strip',
        );
      }
      // Monday first, whatever today happens to be (spec §5.6).
      expect(find.bySemanticsLabel(RegExp('^Monday ')), findsOneWidget);
    });

    testWidgets('today is named, and only to a screen reader is it a word', (
      WidgetTester tester,
    ) async {
      // A column is too narrow for "Today", so on screen it is the bold
      // initial that says so — never colour alone (§6.3). The label spells it
      // out for anyone who cannot see the weight.
      await openPlan(tester);
      await showWeek(tester);

      expect(find.bySemanticsLabel(RegExp(', today[.]')), findsOneWidget);
      // And the card below names the selected day, which opens on today.
      expect(find.text('Today'), findsOneWidget);
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
      expect(find.text('nothing logged'), findsOneWidget);
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

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Breakfast'), findsNothing);
      // The card below follows the strip.
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('and the way into logging is said out loud', (
      WidgetTester tester,
    ) async {
      // The strip no longer navigates, so the day view needs a door rather
      // than a hint that tapping a row would take you there.
      await openPlan(tester);
      await showWeek(tester);

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
