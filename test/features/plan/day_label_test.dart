import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/week.dart';

import '../../support/app_harness.dart';

/// Which day the day screen says it is showing (spec §5.6, review F05).
///
/// The screen's whole job is attributing food to the right date, so a date it
/// states and does not mean is the worst thing on it. Two separate faults
/// were: a summary card captioned with the literal string `Today` whatever
/// was selected, and a relative label counted in elapsed hours rather than
/// calendar days.
void main() {
  /// Opens the planner on [date].
  ///
  /// Through the real `SelectedDate` notifier rather than by tapping the
  /// arrows: what is under test is what the screen *says* about a date, and a
  /// tap sequence would put the arrows' own arithmetic in the way of it.
  Future<void> openOn(WidgetTester tester, DateTime date) async {
    // Before pumping, not after: `build()` runs during the pump, and setting
    // it afterwards leaves the notifier holding today — which is how the
    // first version of this test opened on today and reported the bug from
    // the wrong date.
    _FixedDate.date = dayKey(date);
    await pumpHearthApp(
      tester,
      // Without targets the day screen offers to set some up and never draws
      // the summary card at all — so a test without them asserts nothing
      // about the card's caption while looking as though it does.
      targets: const MacroTargets(
        kcal: 2000,
        proteinG: 150,
        carbG: 200,
        fatG: 70,
      ),
      extraOverrides: <Object>[
        selectedDateProvider.overrideWith(_FixedDate.new),
      ],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('a past day does not have a card saying Today', (
    WidgetTester tester,
  ) async {
    // The caption was a literal string in the widget, so scrolling back to
    // Monday left a card asserting these were today's numbers sixty points
    // under a header reading "Monday 7 September".
    await openOn(tester, addDays(dayKey(DateTime.now()), -3));

    expect(
      find.text('Today'),
      findsNothing,
      reason: 'a day three days ago is not today, anywhere on the screen',
    );
    expect(find.text('Daily totals'), findsOneWidget);
  });

  testWidgets('and neither does a future one', (WidgetTester tester) async {
    await openOn(tester, addDays(dayKey(DateTime.now()), 2));

    expect(find.text('Today'), findsNothing);
    expect(find.text('Daily totals'), findsOneWidget);
  });

  testWidgets('today keeps its name in the header, once', (
    WidgetTester tester,
  ) async {
    // The header still says Today — that is the label doing its job. What it
    // must not do is say it twice, which is what the card was for.
    await openOn(tester, DateTime.now());

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Daily totals'), findsOneWidget);
  });

  // One pump per test. Pumping a second app into the same tester leaves the
  // first one's widgets standing, and the finder then reads a screen nobody
  // is looking at — which is why the first version of this found "Yesterday"
  // and then failed to find "Tomorrow".
  testWidgets('yesterday is named, not numbered', (WidgetTester tester) async {
    await openOn(tester, addDays(dayKey(DateTime.now()), -1));
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('and so is tomorrow', (WidgetTester tester) async {
    await openOn(tester, addDays(dayKey(DateTime.now()), 1));
    expect(find.text('Tomorrow'), findsOneWidget);
  });
}

/// A [SelectedDate] that opens wherever the test puts it.
///
/// Static, because Riverpod builds the notifier and there is nowhere to hand
/// a constructor argument through `overrideWith`.
class _FixedDate extends SelectedDate {
  static DateTime date = dayKey(DateTime.now());

  @override
  DateTime build() => date;
}
