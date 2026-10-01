import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/day_screen.dart';
import 'package:hearth/features/plan/plan_screen.dart';
import 'package:hearth/features/plan/week_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

// Historical-year and Today labels have their own coverage. This fixture
// checks the ordinary current-year layout with Wednesday's stable amounts.
final DateTime _selected = _layoutDate(DateTime.now());

DateTime _layoutDate(DateTime reference) {
  final DateTime candidate = addDays(
    startOfWeek(DateTime(reference.year, 9, 30)),
    2,
  );
  return startOfWeek(candidate) == startOfWeek(reference)
      ? addDays(candidate, -7)
      : candidate;
}

const Macros _oats = Macros(
  kcal: 400,
  proteinG: 20,
  carbG: 60,
  fatG: 9,
  fiberG: 8,
  sodiumMg: 50,
  cholesterolMg: 5,
);

void main() {
  test('viewport fixture avoids historical years and the Today week', () {
    for (final int year in <int>[2026, 2027, 2028, 2032]) {
      for (final DateTime reference in <DateTime>[
        DateTime(year, 1, 1),
        for (int day = 20; day <= 37; day++) DateTime(year, 9, day),
        DateTime(year, 12, 31),
      ]) {
        final DateTime selected = _layoutDate(reference);
        expect(selected.year, reference.year);
        expect(selected.weekday, DateTime.wednesday);
        expect(
          startOfWeek(selected),
          isNot(startOfWeek(reference)),
          reason:
              'The initial-viewport case must not acquire a Today label '
              'when the clock is $reference.',
        );
      }
    }
  });

  for (final Brightness brightness in Brightness.values) {
    for (final PlanView view in PlanView.values) {
      testWidgets(
        'real shell small 3x ${brightness.name} ${view.name}: date controls '
        'and a nutrition fact are fully above the initial fold',
        (WidgetTester tester) async {
          await _openPlan(tester, brightness: brightness);
          if (view == PlanView.week) await _switchView(tester, view);
          _expectInitialContent(tester, view: view, scale: 3);
          expect(
            find.bySemanticsLabel(
              RegExp(
                view == PlanView.day
                    ? '600 of 2000 calories'
                    : '1840 / 2000 kcal',
              ),
            ),
            findsOneWidget,
            reason: 'the complete target comparison remains spoken',
          );
          for (final String label
              in view == PlanView.day
                  ? <String>[
                      'of 2000 kcal',
                      '1400 left',
                      '650 kcal still planned',
                    ]
                  : <String>['of 2000 kcal', '1 logged']) {
            final Finder detail = find.text(label).first;
            await tester.ensureVisible(detail);
            await pumpFrames(tester);
            _expectInRect(
              tester.getRect(detail),
              _viewport(tester, view),
              label,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final ({String name, Size size, EdgeInsets insets}) device
        in <({String name, Size size, EdgeInsets insets})>[
          (
            name: 'phone',
            size: const Size(390, 844),
            insets: const EdgeInsets.only(top: 47, bottom: 34),
          ),
          (
            name: 'desktop',
            size: const Size(1280, 800),
            insets: const EdgeInsets.only(top: 24),
          ),
        ]) {
      testWidgets(
        'real shell ${device.name} ${brightness.name}: populated Day and '
        'Week keep useful content visible',
        (WidgetTester tester) async {
          await _openPlan(
            tester,
            brightness: brightness,
            size: device.size,
            scale: 1,
            insets: device.insets,
          );
          _expectInitialContent(tester, view: PlanView.day, scale: 1);
          await _switchView(tester, PlanView.week);
          _expectInitialContent(tester, view: PlanView.week, scale: 1);
          await _switchView(tester, PlanView.day);
          expect(_container(tester).read(selectedDateProvider), _selected);
          expect(find.text('600 of 2000 kcal'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'real shell small 3x ${brightness.name}: date identity, Today and '
      'saved-week controls survive view changes',
      (WidgetTester tester) async {
        await _openPlan(tester, brightness: brightness);
        final List<String> missingAnnouncements = <String>[];
        final ProviderContainer container = _container(tester);
        await _tapDateAction(tester, 'Previous day', PlanView.day);
        final DateTime previous = addDays(_selected, -1);
        expect(container.read(selectedDateProvider), previous);
        _recordFullDate(tester, previous, missingAnnouncements);
        await _tapDateAction(tester, 'Next day', PlanView.day);
        expect(container.read(selectedDateProvider), _selected);

        await _switchView(tester, PlanView.week);
        await _tapDateAction(tester, 'Next week', PlanView.week);
        expect(container.read(selectedDateProvider), addDays(_selected, 7));
        await _tapDateAction(tester, 'Previous week', PlanView.week);
        expect(container.read(selectedDateProvider), _selected);
        final List<DateTime> days = weekOf(_selected);
        final String range =
            '${_fullDate(days.first)} through '
            '${_fullDate(days.last)}';
        if (find.bySemanticsLabel(range).evaluate().isEmpty) {
          missingAnnouncements.add('Week does not announce $range');
        }

        await _tapDateAction(tester, 'More', PlanView.week);
        for (final String label in <String>[
          'Save this week to use again',
          'Use a saved week',
        ]) {
          final Finder choice = find.text(label);
          expect(choice.hitTestable(), findsOneWidget);
          _expectInRect(
            tester.getRect(choice),
            const Rect.fromLTWH(0, 24, 320, 510),
            label,
          );
        }
        await tester.binding.handlePopRoute();
        await pumpFrames(tester, frames: 12);

        await _tapDateAction(tester, 'Go to this week', PlanView.week);
        final DateTime today = dayKey(DateTime.now());
        expect(container.read(selectedDateProvider), today);
        await _switchView(tester, PlanView.day);
        _recordFullDate(tester, today, missingAnnouncements);
        await _tapDateAction(tester, 'Previous day', PlanView.day);
        await _tapDateAction(tester, 'Go to today', PlanView.day);
        expect(container.read(selectedDateProvider), dayKey(DateTime.now()));
        expect(tester.takeException(), isNull);
        expect(
          missingAnnouncements,
          isEmpty,
          reason: missingAnnouncements.join('\n'),
        );
      },
    );

    testWidgets(
      'real shell small 3x ${brightness.name}: Copy day sheet stays readable '
      'and can be cancelled',
      (WidgetTester tester) async {
        await _openPlan(tester, brightness: brightness);
        await _tapDateAction(
          tester,
          'Copy this day to other days',
          PlanView.day,
        );
        final Object? layoutError = tester.takeException();
        expect(find.text('Copy this day to'), findsOneWidget);
        final Finder cancel = find.widgetWithText(TextButton, 'Cancel');
        await tester.ensureVisible(cancel);
        final Rect cancelBounds = tester.getRect(cancel);
        final List<String> issues = <String>[
          if (layoutError != null) layoutError.toString().split('\n').first,
          if (!_inside(cancelBounds, const Rect.fromLTWH(0, 24, 320, 510)) ||
              cancel.hitTestable().evaluate().isEmpty)
            'Cancel remains unreachable at $cancelBounds after trying to '
                'scroll it into view.',
        ];
        expect(issues, isEmpty, reason: issues.join('\n'));
        await tester.tap(cancel);
        await pumpFrames(tester, frames: 12);
        expect(_container(tester).read(selectedDateProvider), _selected);
      },
    );
  }
}

Future<void> _openPlan(
  WidgetTester tester, {
  required Brightness brightness,
  Size size = const Size(320, 568),
  double scale = 3,
  EdgeInsets insets = const EdgeInsets.only(top: 24, bottom: 34),
}) async {
  final List<DateTime> days = weekOf(_selected);
  final Map<DateTime, List<MealPlanEntry>> meals =
      <DateTime, List<MealPlanEntry>>{
        for (int i = 0; i < days.length; i++)
          days[i]: <MealPlanEntry>[
            MealPlanEntry(
              id: 'oats-$i',
              dayId: 'plan-day-$i',
              slot: MealSlot.breakfast,
              refType: PlanRefType.food,
              refId: 'oats',
              servingOptionId: 'oats-serving',
              // A realistic full-day total in the first Week row, not only
              // the shorter three-digit amount shown by the selected day.
              servings: i == 0 ? 4.6 : 1 + i * 0.25,
            ).log(
              liveMacros: _oats,
              at: days[i].add(const Duration(hours: 8)),
              label: 'Oats with berries',
              coverage: const NutrientCoverage.allComplete(),
            ),
            MealPlanEntry(
              id: 'chili-$i',
              dayId: 'plan-day-$i',
              slot: MealSlot.dinner,
              refType: PlanRefType.food,
              refId: 'chili',
              servingOptionId: 'chili-serving',
              servings: 1,
            ),
          ],
      };
  await pumpHearthApp(
    tester,
    size: size,
    textScale: scale,
    brightness: brightness,
    viewPadding: insets,
    launchTarget: LaunchTarget.today,
    selectedDate: _selected,
    foods: <Food>[
      aFood(
        'Oats with berries',
        id: 'oats',
        servingOptions: <ServingOption>[
          aServing(
            id: 'oats-serving',
            amount: 100,
            unit: Units.gram,
            macros: _oats,
          ),
        ],
      ),
      aFood(
        'Turkey chili',
        id: 'chili',
        servingOptions: <ServingOption>[
          aServing(
            id: 'chili-serving',
            amount: 350,
            unit: Units.gram,
            macros: const Macros(kcal: 650, proteinG: 40, carbG: 60, fatG: 20),
          ),
        ],
      ),
    ],
    entries: meals[_selected]!,
    weekEntries: meals,
    targets: const MacroTargets(
      kcal: 2000,
      proteinG: 150,
      carbG: 200,
      fatG: 70,
    ),
  );
  await pumpFrames(tester, frames: 16);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlanScreen)));

Finder _screen(PlanView view) =>
    find.byType(view == PlanView.day ? DayScreen : WeekScreen);

Rect _viewport(WidgetTester tester, PlanView view) => tester.getRect(
  find.descendant(of: _screen(view), matching: find.byType(ListView)).first,
);

Future<void> _switchView(WidgetTester tester, PlanView view) async {
  final SweepTools tools = SweepTools(tester);
  await tools.planView(view == PlanView.day ? 'Day' : 'Week');
  if (view == PlanView.week) await tools.weekContent('Nutrition');
  await pumpFrames(tester, frames: 16);
  expect(_container(tester).read(planViewProvider), view);
}

void _expectInitialContent(
  WidgetTester tester, {
  required PlanView view,
  required double scale,
}) {
  expect(
    find.bySemanticsLabel(
      'Home. Leave Nutrition and go back to all of Hearth.',
    ),
    findsOneWidget,
    reason: 'measure the real shell, including its Home bar or sidebar',
  );
  final Rect viewport = _viewport(tester, view);
  expect(viewport.height, greaterThan(0));
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
    expect(
      viewport.bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      reason: 'the fold is above the tabs, not the bottom of the screen',
    );
  }
  expect(
    MediaQuery.textScalerOf(tester.element(_screen(view))).scale(16),
    16 * scale,
    reason: 'making room must preserve the system text setting',
  );

  final List<String> issues = <String>[];
  void requireVisible(Finder finder, String label, {bool button = false}) {
    if (finder.evaluate().isEmpty) {
      issues.add('$label is not built in the initial viewport or its cache.');
      return;
    }
    final Rect bounds = tester.getRect(finder.first);
    if (!_inside(bounds, viewport)) {
      issues.add('$label occupies $bounds outside viewport $viewport.');
    }
    if (button &&
        (bounds.width < 48 ||
            bounds.height < 48 ||
            finder.hitTestable().evaluate().isEmpty)) {
      issues.add('$label is not a reachable 48-point target: $bounds.');
    }
  }

  final Finder newDate = find.byKey(const ValueKey<String>('plan-date-label'));
  final Finder currentDate = view == PlanView.day
      ? find.text(
          '${weekdayName(_selected)} ${_selected.day} ${monthName(_selected)}',
        )
      : find
            .descendant(of: _screen(view), matching: find.textContaining('–'))
            .first;
  requireVisible(newDate.evaluate().isNotEmpty ? newDate : currentDate, 'Date');
  for (final String tooltip
      in view == PlanView.day
          ? <String>[
              'Previous day',
              'Go to today',
              'Next day',
              'Copy this day to other days',
            ]
          : <String>['Previous week', 'Go to this week', 'Next week', 'More']) {
    requireVisible(_dateAction(tooltip), tooltip, button: true);
  }
  requireVisible(
    find.text(
      scale > 1
          ? view == PlanView.day
                ? '600 kcal'
                : '1840 kcal'
          : view == PlanView.day
          ? '600 of 2000 kcal'
          : '1840 / 2000 kcal',
    ),
    view == PlanView.day ? 'Consumed calories' : "Monday's consumed calories",
  );
  if (view == PlanView.week) {
    final DateTime monday = startOfWeek(_selected);
    requireVisible(
      find.text('${shortWeekdayName(monday)} ${monday.day}'),
      "The first amount's day",
    );
  }
  expect(tester.takeException(), isNull);
  expect(issues, isEmpty, reason: issues.join('\n'));
}

Future<void> _tapDateAction(
  WidgetTester tester,
  String tooltip,
  PlanView view,
) async {
  final Finder action = _dateAction(tooltip);
  await tester.ensureVisible(action);
  await pumpFrames(tester);
  expect(action.hitTestable(), findsOneWidget, reason: tooltip);
  _expectInRect(tester.getRect(action), _viewport(tester, view), tooltip);
  await tester.tap(action);
  await pumpFrames(tester, frames: 12);
}

// The tooltip is inside Material's padded 48-point IconButton. Measuring the
// tooltip itself measures only the 40-point decoration, not the touch target.
Finder _dateAction(String tooltip) => find.byWidgetPredicate(
  (Widget widget) => widget is IconButton && widget.tooltip == tooltip,
);

String _fullDate(DateTime date) =>
    '${weekdayName(date)}, ${monthName(date)} ${date.day}, ${date.year}';

void _recordFullDate(WidgetTester tester, DateTime date, List<String> missing) {
  final String label = _fullDate(date);
  if (find.bySemanticsLabel(label).evaluate().isEmpty) {
    missing.add('Day does not announce $label');
  }
}

bool _inside(Rect child, Rect viewport) =>
    child.left >= viewport.left - 1 &&
    child.right <= viewport.right + 1 &&
    child.top >= viewport.top - 1 &&
    child.bottom <= viewport.bottom + 1;

void _expectInRect(Rect child, Rect viewport, String label) => expect(
  _inside(child, viewport),
  isTrue,
  reason: '$label occupies $child outside $viewport',
);
