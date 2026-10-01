import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/widgets/reading_column.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/features/plan/plan_date_header.dart';
import 'package:hearth/features/plan/plan_view_control.dart';

const Key _summaryKey = ValueKey<String>('meaningful-summary');
const Key _scrollKey = ValueKey<String>('header-example-scroll');
const Key _dateKey = ValueKey<String>('plan-date-label');
const Key _navigationKey = ValueKey<String>('plan-date-navigation');
const Key _viewKey = ValueKey<String>('plan-view-control');

void main() {
  // These are component compositions, not claims that DayScreen/WeekScreen
  // have been wired to the header. The real screens are integrated separately.
  for (final ({String name, Size size, double scale}) device
      in <({String name, Size size, double scale})>[
        (name: 'small', size: const Size(320, 568), scale: 1),
        (name: 'small 3x', size: const Size(320, 568), scale: 3),
        (name: 'phone', size: const Size(390, 844), scale: 1),
        (name: 'phone 3x', size: const Size(390, 844), scale: 3),
        (name: 'desktop', size: const Size(1280, 800), scale: 1),
        (name: 'desktop 3x', size: const Size(1280, 800), scale: 3),
      ]) {
    for (final Brightness brightness in Brightness.values) {
      for (final PlanView view in PlanView.values) {
        testWidgets(
          '${device.name} ${brightness.name} ${view.name}: date, actions and '
          'first nutrition fact fit before scrolling',
          (WidgetTester tester) async {
            final List<DateTime> copied = <DateTime>[];
            final List<DateTime> saved = <DateTime>[];
            await _pumpExample(
              tester,
              size: device.size,
              scale: device.scale,
              brightness: brightness,
              initialView: view,
              onCopy: copied.add,
              onSaveWeek: saved.add,
            );
            final Rect viewport = tester.getRect(find.byKey(_scrollKey));
            _expectInside(tester.getRect(find.byKey(_dateKey)), viewport);
            _expectInside(tester.getRect(find.byKey(_navigationKey)), viewport);
            _expectInside(tester.getRect(find.byKey(_summaryKey)), viewport);
            _expectInside(
              tester.getRect(find.byKey(_viewKey)),
              Offset.zero & device.size,
            );

            final bool compact = device.size.width == 320 || device.scale > 1;
            if (compact) {
              expect(
                tester.getRect(find.byKey(_dateKey)).bottom,
                lessThanOrEqualTo(
                  tester.getRect(find.byKey(_navigationKey)).top,
                ),
                reason: 'the date gets the full width above the controls',
              );
              expect(find.text('Today'), findsNothing);
              expect(find.byType(SegmentedButton<PlanView>), findsNothing);
            }
            expect(
              MediaQuery.textScalerOf(tester.element(find.byKey(_summaryKey)))
                  .scale(16),
              16 * device.scale,
            );
            expect(
              find.bySemanticsLabel(
                view == PlanView.day
                    ? 'Wednesday, September 30, 2026'
                    : 'Monday, September 28, 2026 through '
                          'Sunday, October 4, 2026',
              ),
              findsOneWidget,
            );

            for (final String tooltip in <String>[
              view == PlanView.day ? 'Previous day' : 'Previous week',
              view == PlanView.day ? 'Go to today' : 'Go to this week',
              view == PlanView.day ? 'Next day' : 'Next week',
              view == PlanView.day ? 'Copy this day to other days' : 'More',
            ]) {
              final Finder button = find.byTooltip(tooltip);
              expect(button.hitTestable(), findsOneWidget);
              final Rect bounds = tester.getRect(button);
              _expectInside(bounds, viewport);
              expect(bounds.width, greaterThanOrEqualTo(48));
              expect(bounds.height, greaterThanOrEqualTo(48));
            }
            if (view == PlanView.day) {
              await tester.tap(find.byTooltip('Copy this day to other days'));
              expect(copied, <DateTime>[DateTime(2026, 9, 30)]);
            } else {
              await tester.tap(find.byTooltip('More'));
              await tester.pumpAndSettle();
              final Finder save = find.text('Save this week to use again');
              expect(save.hitTestable(), findsOneWidget);
              await tester.tap(save);
              await tester.pumpAndSettle();
              expect(saved, <DateTime>[DateTime(2026, 9, 30)]);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'ordinary phone ${brightness.name}: long day headings stay whole '
      'beside reachable actions and content',
      (WidgetTester tester) async {
        await _pumpExample(
          tester,
          size: const Size(390, 844),
          scale: 1,
          brightness: brightness,
        );
        for (int day = 1; day <= 7; day++) {
          await tester.tap(find.byTooltip('Previous day'));
          await tester.pumpAndSettle();
          if (day != 1 && day != 7) continue;
          final String heading = day == 1 ? 'Yesterday' : 'Wednesday';
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(
                find.descendant(
                  of: find.text(heading),
                  matching: find.byType(RichText),
                ),
              );
          expect(
            paragraph
                .getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: heading.length),
                )
                .map((TextBox box) => box.top)
                .toSet()
                .length,
            1,
            reason: '$heading must not break inside a word to reserve actions',
          );
          final Rect viewport = tester.getRect(find.byKey(_scrollKey));
          _expectInside(tester.getRect(find.text(heading)), viewport);
          _expectInside(tester.getRect(find.byKey(_navigationKey)), viewport);
          _expectInside(tester.getRect(find.byKey(_summaryKey)), viewport);
          expect(
            find.byTooltip('Copy this day to other days').hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'small 3x ${brightness.name}: view menu names the current view and '
      'switches both ways',
      (WidgetTester tester) async {
        await _pumpExample(tester, brightness: brightness);
        expect(find.text('Day view'), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(_viewKey)).getSemanticsData().value,
          'Day',
        );

        await tester.tap(find.byKey(_viewKey));
        await tester.pumpAndSettle();
        for (final String name in <String>['Day', 'Week']) {
          final Finder item = find.byKey(
            ValueKey<String>('plan-view-${name.toLowerCase()}'),
          );
          // CheckedPopupMenuItem deliberately ignores pointers on its label;
          // the enclosing entry owns the action. Test that actual target and
          // separately require the full label to fit inside it.
          expect(item.hitTestable(), findsOneWidget);
          _expectInside(tester.getRect(find.text(name)), tester.getRect(item));
          _expectInside(
            tester.getRect(item),
            const Rect.fromLTWH(0, 0, 320, 568),
          );
        }
        await tester.tap(find.byKey(const ValueKey<String>('plan-view-week')));
        await tester.pumpAndSettle();
        expect(find.text('Week view'), findsOneWidget);
        expect(find.byTooltip('Next week'), findsOneWidget);
        expect(find.byTooltip('Copy this day to other days'), findsNothing);

        await tester.tap(find.byKey(_viewKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('plan-view-day')));
        await tester.pumpAndSettle();
        expect(find.text('Day view'), findsOneWidget);
        expect(find.byTooltip('Copy this day to other days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'small 3x ${brightness.name}: crossing New Year keeps date and copy '
      'identity together',
      (WidgetTester tester) async {
        final List<DateTime> copied = <DateTime>[];
        await _pumpExample(
          tester,
          brightness: brightness,
          date: DateTime(2026, 12, 31),
          onCopy: copied.add,
        );
        await tester.tap(find.byTooltip('Next day'));
        await tester.pumpAndSettle();
        expect(find.text('Fri, Jan 1, 2027'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Friday, January 1, 2027'),
          findsOneWidget,
        );
        _expectInside(
          tester.getRect(find.byKey(_dateKey)),
          tester.getRect(find.byKey(_scrollKey)),
        );
        await tester.tap(find.byTooltip('Copy this day to other days'));
        expect(copied, <DateTime>[DateTime(2027, 1, 1)]);
        await tester.tap(find.byTooltip('Previous day'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Thursday, December 31, 2026'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Previous day'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Go to today'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Thursday, December 31, 2026'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'small 3x ${brightness.name}: week across New Year names both years '
      'and leaves the first fact visible',
      (WidgetTester tester) async {
        final List<DateTime> saved = <DateTime>[];
        await _pumpExample(
          tester,
          brightness: brightness,
          date: DateTime(2026, 12, 31),
          initialView: PlanView.week,
          onSaveWeek: saved.add,
        );
        expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Monday, December 28, 2026 through Sunday, January 3, 2027',
          ),
          findsOneWidget,
        );
        final Rect viewport = tester.getRect(find.byKey(_scrollKey));
        _expectInside(tester.getRect(find.byKey(_dateKey)), viewport);
        _expectInside(tester.getRect(find.byKey(_summaryKey)), viewport);
        await tester.tap(find.byTooltip('Next week'));
        await tester.pumpAndSettle();
        expect(find.text('Jan 4–10, 2027'), findsOneWidget);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save this week to use again'));
        await tester.pumpAndSettle();
        expect(saved, <DateTime>[DateTime(2027, 1, 7)]);
        await tester.tap(find.byTooltip('Go to this week'));
        await tester.pumpAndSettle();
        expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact view menu and each date action work by keyboard', (
    WidgetTester tester,
  ) async {
    final List<DateTime> copied = <DateTime>[];
    await _pumpExample(tester, onCopy: copied.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Week'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Tuesday, September 29, 2026'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Wednesday, September 30, 2026'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Thursday, October 1, 2026'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(copied, <DateTime>[DateTime(2026, 10, 1)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary phone keeps direct Day and Week choices', (
    WidgetTester tester,
  ) async {
    await _pumpExample(tester, size: const Size(390, 844), scale: 1);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next week'), findsOneWidget);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _expectInside(Rect child, Rect viewport) {
  expect(child.left, greaterThanOrEqualTo(viewport.left - 1));
  expect(child.right, lessThanOrEqualTo(viewport.right + 1));
  expect(child.top, greaterThanOrEqualTo(viewport.top - 1));
  expect(child.bottom, lessThanOrEqualTo(viewport.bottom + 1));
}

Future<void> _pumpExample(
  WidgetTester tester, {
  Size size = const Size(320, 568),
  double scale = 3,
  Brightness brightness = Brightness.light,
  PlanView initialView = PlanView.day,
  DateTime? date,
  ValueChanged<DateTime>? onCopy,
  ValueChanged<DateTime>? onSaveWeek,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: HearthTheme.light(),
      darkTheme: HearthTheme.dark(),
      home: _HeaderExample(
        date: date ?? DateTime(2026, 9, 30),
        initialView: initialView,
        onCopy: onCopy,
        onSaveWeek: onSaveWeek,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A bounded screen with app chrome and useful content after the owned
/// components. It verifies the available reading space without depending on
/// the private Day/Week wrappers reserved for the next integration phase.
class _HeaderExample extends StatefulWidget {
  const _HeaderExample({
    required this.date,
    required this.initialView,
    this.onCopy,
    this.onSaveWeek,
  });

  final DateTime date;
  final PlanView initialView;
  final ValueChanged<DateTime>? onCopy;
  final ValueChanged<DateTime>? onSaveWeek;

  @override
  State<_HeaderExample> createState() => _HeaderExampleState();
}

class _HeaderExampleState extends State<_HeaderExample> {
  late DateTime date = widget.date;
  late PlanView view = widget.initialView;

  @override
  Widget build(BuildContext context) {
    void previous() => setState(() {
      date = addDays(date, view == PlanView.day ? -1 : -7);
    });
    void today() => setState(() => date = widget.date);
    void next() => setState(() {
      date = addDays(date, view == PlanView.day ? 1 : 7);
    });

    final List<DateTime> days = weekOf(date);
    final Widget header = view == PlanView.day
        ? PlanDateHeader.day(
            date: date,
            today: widget.date,
            onPrevious: previous,
            onToday: today,
            onNext: next,
            onCopy: () => widget.onCopy?.call(date),
          )
        : PlanDateHeader.week(
            firstDay: days.first,
            lastDay: days.last,
            today: widget.date,
            onPrevious: previous,
            onToday: today,
            onNext: next,
            trailingAction: PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (_) => widget.onSaveWeek?.call(date),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'save',
                  child: Text(
                    'Save this week to use again',
                    style: context.text.body,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'use',
                  child: Text('Use a saved week', style: context.text.body),
                ),
              ],
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Plan')),
      bottomNavigationBar: const SizedBox(height: 80),
      body: SafeArea(
        child: ReadingColumn(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: PlanViewControl(
                  value: view,
                  onChanged: (PlanView value) => setState(() => view = value),
                ),
              ),
              Expanded(
                child: ListView(
                  key: _scrollKey,
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  children: <Widget>[
                    header,
                    const SizedBox(height: HearthSpacing.lg),
                    Text(
                      '1,200 kcal',
                      key: _summaryKey,
                      style: context.text.label,
                    ),
                    const SizedBox(height: HearthSpacing.lg),
                    TextButton(onPressed: () {}, child: const Text('Add meal')),
                    const SizedBox(height: 600),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
