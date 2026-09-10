import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Which day and meal a portion is about to be logged to (review F05's
/// "Today cleanup").
///
/// The sheet named the food and its macros and never once said where the
/// meal was going. On today that is merely unstated; on a day you have
/// scrolled back to it is the whole question, because the header that names
/// the date is the only thing that knew — and the sheet covers it.
///
/// Asserted as one whole line rather than as two `textContaining` calls: the
/// day screen behind the sheet says "Today" and "Breakfast" itself, so a
/// looser finder passes on the screen underneath and proves nothing about
/// the sheet. The first version of this test did exactly that.
void main() {
  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      aServing(
        amount: 170,
        unit: Units.gram,
        macros: const Macros(kcal: 281, proteinG: 17),
      ),
    ],
  );

  /// Opens the logging sheet on [date], through breakfast.
  Future<void> openSheetOn(WidgetTester tester, DateTime date) async {
    _FixedDate.date = dayKey(date);
    await pumpHearthApp(
      tester,
      foods: <Food>[yoghurt()],
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
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('a backdated meal says which day it is going to', (
    WidgetTester tester,
  ) async {
    // The one that matters: three days back, nothing else on screen says the
    // meal is not going on today.
    final DateTime past = addDays(dayKey(DateTime.now()), -3);
    await openSheetOn(tester, past);

    expect(
      find.text('Breakfast · ${weekdayName(past)} ${shortDate(past)}'),
      findsOneWidget,
      reason: 'the sheet never named the day it was logging to',
    );
  });

  testWidgets('and today says so in words, not a date to decode', (
    WidgetTester tester,
  ) async {
    await openSheetOn(tester, DateTime.now());

    expect(find.text('Breakfast · Today'), findsOneWidget);
  });

  /// The colour of the destination line.
  ///
  /// Read against the palette rather than against a second pump of the app.
  /// Pumping twice in one test leaves the first app's widgets standing for
  /// the finder to read — the trap #55 hit — and "is it the same colour as
  /// today's" is a weaker statement than "is it the accent" anyway.
  Color lineColour(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  final HearthColors palette = HearthColors.light();

  testWidgets('planning tomorrow is not flagged like a mistake', (
    WidgetTester tester,
  ) async {
    // The accent is there so backdating is visible before it is read.
    // Planning tomorrow's dinner is not backdating — it is what a planner is
    // for — and marking the two the same way spends the signal on the wrong
    // day, leaving the case worth noticing no louder than the routine one.
    await openSheetOn(tester, addDays(dayKey(DateTime.now()), 1));

    expect(lineColour(tester, 'Breakfast · Tomorrow'), palette.textMuted);
  });

  testWidgets('and today is not either', (WidgetTester tester) async {
    await openSheetOn(tester, dayKey(DateTime.now()));

    expect(lineColour(tester, 'Breakfast · Today'), palette.textMuted);
  });

  testWidgets('but a day behind you is', (WidgetTester tester) async {
    await openSheetOn(tester, addDays(dayKey(DateTime.now()), -1));

    expect(lineColour(tester, 'Breakfast · Yesterday'), palette.accent);
  });

  testWidgets('yesterday is named rather than dated', (
    WidgetTester tester,
  ) async {
    await openSheetOn(tester, addDays(dayKey(DateTime.now()), -1));

    expect(find.text('Breakfast · Yesterday'), findsOneWidget);
  });
}

/// A [SelectedDate] the test puts where it needs it.
class _FixedDate extends SelectedDate {
  static DateTime date = dayKey(DateTime.now());

  @override
  DateTime build() => date;
}
