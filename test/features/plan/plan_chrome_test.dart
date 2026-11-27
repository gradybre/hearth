import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/features/plan/plan_date_header.dart';
import 'package:hearth/features/plan/plan_view_control.dart';

import '../../support/app_harness.dart';

/// The planner's chrome (spec §5.6, §6.3, and the November 2026 templates).
///
/// Two rows: the day in words with Day / Week beside it, and under that a
/// stepper with the date in the middle of it. The control used to be a fixed
/// band above the whole screen — a row of its own, spent on two words — and
/// the date sat off to one side with its arrows crowded against it.
///
/// Dates are fixed rather than taken from the clock: the longest weekday is
/// the case that decides whether the title row holds, and a test that waits
/// for a Wednesday to come round is a test that passes six days in seven.
void main() {
  // Wednesday, the longest weekday, which is what the title row has to fit
  // beside the control on an ordinary phone.
  final DateTime wednesday = DateTime(2026, 9, 30);

  Future<void> pumpHeader(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1.0,
    DateTime? date,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              PlanDateHeader.day(
                date: date ?? wednesday,
                // A day that is not the one shown, so the heading is a
                // weekday rather than the word "Today".
                today: DateTime(2026, 10, 7),
                onPrevious: () {},
                onToday: () {},
                onNext: () {},
                onCopy: () {},
                viewControl: PlanViewControl(
                  value: PlanView.day,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect navigationRow(WidgetTester tester) => tester.getRect(
    find.byKey(const ValueKey<String>('plan-date-navigation')),
  );

  Rect dateLabel(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('plan-date-label')));

  testWidgets('the day and the Day/Week control share a line', (
    WidgetTester tester,
  ) async {
    await pumpHeader(tester);

    final Rect heading = tester.getRect(find.text('Wednesday'));
    final Rect control = tester.getRect(
      find.byKey(const ValueKey<String>('plan-view-control')),
    );

    // Overlapping vertically is the claim, not equal tops: the serif heading
    // and a segmented button are different heights and sit centred on each
    // other.
    expect(
      heading.top < control.bottom && control.top < heading.bottom,
      isTrue,
      reason: 'the control is on a line of its own: $heading vs $control',
    );
    expect(
      control.left,
      greaterThan(heading.right),
      reason: 'the control should be at the far end of the heading row',
    );
  });

  testWidgets('and the date is in the middle of its own row', (
    WidgetTester tester,
  ) async {
    await pumpHeader(tester);

    final Rect row = navigationRow(tester);
    final Rect date = dateLabel(tester);

    // Within a point: the two buttons on each side are the same width, so
    // the centre of the row is the centre of the date and not the centre of
    // whatever space was left over.
    expect(
      (date.center.dx - row.center.dx).abs(),
      lessThan(1),
      reason: 'the date is off-centre: $date in $row',
    );
    expect(date.top, greaterThanOrEqualTo(row.top));
    expect(date.bottom, lessThanOrEqualTo(row.bottom));
  });

  testWidgets('with the arrows at the outside edges', (
    WidgetTester tester,
  ) async {
    // The templates' shape, and the one that reads as a stepper: previous at
    // the left edge, next at the right, everything else between them.
    await pumpHeader(tester);

    final Rect row = navigationRow(tester);
    final Rect previous = tester.getRect(find.byTooltip('Previous day'));
    final Rect next = tester.getRect(find.byTooltip('Next day'));
    final Rect today = tester.getRect(find.byTooltip('Go to today'));
    final Rect copy = tester.getRect(
      find.byTooltip('Copy this day to other days'),
    );

    expect(previous.left, row.left);
    expect(next.right, row.right);
    for (final Rect between in <Rect>[today, copy, dateLabel(tester)]) {
      expect(between.left, greaterThanOrEqualTo(previous.right));
      expect(between.right, lessThanOrEqualTo(next.left));
    }
  });

  testWidgets('at three times the text the stepper gives way', (
    WidgetTester tester,
  ) async {
    // A row cannot hold its middle when one arrow and the date are already
    // wider than the screen, and the date is the part that would be pushed
    // off the side. It takes the full width and the controls follow it
    // (spec §6.3).
    await pumpHeader(tester, size: const Size(320, 568), scale: 3.0);

    expect(tester.takeException(), isNull);
    expect(
      dateLabel(tester).bottom,
      lessThanOrEqualTo(navigationRow(tester).top),
    );
  });

  testWidgets('the control switches the view from where it now sits', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);

    expect(find.byType(SegmentedButton<PlanView>), findsOneWidget);
    await tester.tap(find.text('Week'));
    await pumpFrames(tester, frames: 16);

    // The week's own chrome, which only the week draws.
    expect(find.text('Meals'), findsWidgets);
    expect(find.byTooltip('Previous week'), findsOneWidget);
  });

  testWidgets('and travels with the header rather than hanging above it', (
    WidgetTester tester,
  ) async {
    // It was a fixed band over the whole screen, which cost a row of the
    // fold on the one screen the success bar is measured on — and left the
    // date stepper, which has always scrolled, moving out from under a
    // control that did not. The header is one block now.
    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(SegmentedButton<PlanView>), findsOneWidget);

    await scrollPastFold(tester, by: 900);

    expect(
      find.byType(SegmentedButton<PlanView>),
      findsNothing,
      reason: 'the control stayed behind while the header scrolled away',
    );
  });
}
