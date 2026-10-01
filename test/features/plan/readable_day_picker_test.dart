import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/features/plan/day_picker_sheet.dart';

final DateTime _anchor = DateTime(2026, 8, 31);

void main() {
  testWidgets('large-text Copy reaches the last day and returns sorted dates', (
    WidgetTester tester,
  ) async {
    final List<List<DateTime>?> results = await _openPicker<List<DateTime>>(
      tester,
      (BuildContext context) => showDayPicker(
        context,
        title: 'Copy this day',
        actionLabel: 'Copy',
        excluding: _anchor,
      ),
    );

    _expectFullScale(tester, find.text('Copy this day'));
    _expectReachableAction(tester, find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(results, <List<DateTime>?>[null]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Choose the last offered day first: the returned order must come from
    // the calendar, not the order in which the person found the dates.
    final DateTime lastDay = DateTime(2026, 9, 13);
    final DateTime earlierDay = DateTime(2026, 9, 1);
    await _chooseDate(tester, lastDay);
    await _chooseDate(tester, earlierDay, scrollBy: -160);

    _expectReachableAction(tester, find.widgetWithText(TextButton, 'Cancel'));
    final Finder copy = find.widgetWithText(FilledButton, 'Copy');
    _expectReachableAction(tester, copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();

    expect(results, <List<DateTime>?>[
      null,
      <DateTime>[earlierDay, lastDay],
    ]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text Move reaches meal slots after choosing a date', (
    WidgetTester tester,
  ) async {
    final List<MealDestination?> results = await _openPicker<MealDestination>(
      tester,
      (BuildContext context) => showMealDestination(
        context,
        title: 'Move this meal',
        actionLabel: 'Move it',
        slot: MealSlot.breakfast,
      ),
    );

    _expectFullScale(tester, find.text('Move this meal'));
    _expectReachableAction(tester, find.widgetWithText(TextButton, 'Cancel'));
    final DateTime destination = DateTime(2026, 9, 1);
    await _chooseDate(tester, destination);

    final Finder dinner = find.widgetWithText(ChoiceChip, 'Dinner');
    await _reveal(tester, dinner);
    _expectFullScale(tester, find.text('Dinner'));
    expect(dinner.hitTestable(), findsOneWidget);
    await tester.tap(dinner);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(dinner).selected, isTrue);

    _expectReachableAction(tester, find.widgetWithText(TextButton, 'Cancel'));
    final Finder move = find.widgetWithText(FilledButton, 'Move it');
    _expectReachableAction(tester, move);
    await tester.tap(move);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single?.date, destination);
    expect(results.single?.slot, MealSlot.dinner);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<List<T?>> _openPicker<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = 3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final List<T?> results = <T?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [selectedDateProvider.overrideWith(_FixedDate.new)],
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: SafeArea(
              child: Center(
                child: FilledButton(
                  onPressed: () async => results.add(await open(context)),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return results;
}

Future<void> _chooseDate(
  WidgetTester tester,
  DateTime day, {
  double scrollBy = 160,
}) async {
  final Finder date = find.textContaining(
    '${weekdayName(day)} ${shortDate(day)}',
  );
  await _reveal(tester, date, scrollBy: scrollBy);
  _expectFullScale(tester, date);
  expect(date.hitTestable(), findsOneWidget);
  await tester.tap(date);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double scrollBy = 160,
}) async {
  await tester.scrollUntilVisible(
    target,
    scrollBy,
    maxScrolls: 80,
    scrollable: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _expectReachableAction(WidgetTester tester, Finder action) {
  expect(action.hitTestable(), findsOneWidget);
  final Rect bounds = tester.getRect(action);
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(320));
  expect(bounds.top, greaterThanOrEqualTo(24));
  expect(bounds.bottom, lessThanOrEqualTo(568 - 34));
  expect(bounds.width, greaterThanOrEqualTo(48));
  expect(bounds.height, greaterThanOrEqualTo(48));
  _expectFullScale(
    tester,
    find.descendant(of: action, matching: find.byType(Text)),
  );
}

void _expectFullScale(WidgetTester tester, Finder label) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  expect(paragraph.textScaler.scale(16), 48);
}

class _FixedDate extends SelectedDate {
  @override
  DateTime build() => _anchor;
}
