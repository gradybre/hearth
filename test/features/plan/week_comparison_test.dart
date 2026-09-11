import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week.dart';

import '../../support/app_harness.dart';

/// The week as a comparison rather than a day selector (review §7.2).
///
/// Measured before any of this was written, with a populated week on a
/// 390x844 phone: 290 points went to one day's rings and 116 to all seven,
/// and `Daily average` — the week's only aggregate — was not built into the
/// tree at all. At twice the text on a 320-point phone the words "This week"
/// alone were 490 points tall in a 380-point viewport: no day, no number.
///
/// Nothing here could be written until `pumpHearthApp` could feed the screen
/// a week. It overrode `weekEntriesProvider` with an empty map, so the one
/// screen whose whole job is comparing seven days had never been drawn with
/// anything on it.
void main() {
  final DateTime monday = DateTime(2026, 9, 7);
  final DateTime thursday = DateTime(2026, 9, 10);

  MealPlanEntry logged(DateTime day, String id, Macros macros) => MealPlanEntry(
    id: '$id-${day.day}',
    dayId: 'day-${day.day}',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'f-1',
    servings: 1,
    isPlanned: false,
    isLogged: true,
    loggedAt: day,
    macroSnapshot: MacroSnapshot(
      macros: macros,
      servings: 1,
      capturedAt: day,
      label: '1 serving',
    ),
  );

  /// Four days at 2,000 kcal, one day logged as nothing, two untouched.
  ///
  /// The fast is the case the whole of §7.2's "distinguish" clause is about:
  /// somebody ate nothing on Saturday and said so.
  Map<DateTime, List<MealPlanEntry>> weekWithAFast() {
    final List<DateTime> days = weekOf(monday);
    return <DateTime, List<MealPlanEntry>>{
      for (int i = 0; i < 4; i++)
        days[i]: <MealPlanEntry>[
          logged(
            days[i],
            'e',
            const Macros(kcal: 2000, proteinG: 150, carbG: 200, fatG: 70),
          ),
        ],
      days[5]: <MealPlanEntry>[logged(days[5], 'e-fast', Macros.zero)],
      days[6]: const <MealPlanEntry>[],
    };
  }

  Future<void> openWeek(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    Map<DateTime, List<MealPlanEntry>>? week,
  }) async {
    await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      launchTarget: LaunchTarget.today,
      weekEntries: week ?? weekWithAFast(),
      targets: const MacroTargets(
        kcal: 2200,
        proteinG: 150,
        carbG: 250,
        fatG: 70,
      ),
      selectedDate: thursday,
    );
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Week').last);
    await pumpFrames(tester, frames: 12);
  }

  group('a day logged as nothing is a logged day', () {
    testWidgets('it counts in the denominator', (WidgetTester tester) async {
      // The defect: `_WeekTotals` dropped days with `!m.isZero`, so a fast
      // was indistinguishable from a day nobody touched. Four days at 2,000
      // and one at nothing is five logged days averaging 1,600 — not four
      // averaging 2,000, which is 400 kcal a day of food nobody ate.
      await openWeek(tester);

      expect(find.textContaining('over 5 logged days'), findsOneWidget);
    });

    testWidgets('and the average is the one you actually ate', (
      WidgetTester tester,
    ) async {
      await openWeek(tester);

      expect(find.textContaining('1600'), findsOneWidget);
    });

    testWidgets('and the days nobody touched are disclosed, not hidden', (
      WidgetTester tester,
    ) async {
      // §7.2: averages "disclose missing days". Two of this week's seven have
      // nothing on them, and an average over five that does not say so reads
      // as an average over seven.
      await openWeek(tester);

      expect(find.textContaining('2 not logged'), findsOneWidget);
    });

    testWidgets('the row for a fast says which kind of nothing it is', (
      WidgetTester tester,
    ) async {
      await openWeek(tester);

      expect(find.textContaining('logged as nothing'), findsOneWidget);
      expect(find.textContaining('nothing logged'), findsWidgets);
    });
  });

  group('seven days, side by side', () {
    testWidgets('every day\'s calories are on screen at once', (
      WidgetTester tester,
    ) async {
      // The complaint: comparing seven days took repeated selection and
      // scrolling, because six of them were 30-point rings with a date in
      // them.
      //
      // The figures, not just the dates. An earlier draft of this asked only
      // where each day's *label* sat, and passed against the old screen —
      // the strip's seven circles are all above the fold and carry the date
      // in their semantics. They carry no number, which is the entire point.
      // And `findsOneWidget` is not "on screen" either: a ListView builds
      // past its viewport, so position is the only honest question.
      await openWeek(tester);

      final double fold = tester.getTopLeft(find.text('Recipes').last).dy;

      for (final DateTime day in weekOf(monday)) {
        final Finder row = find.bySemanticsLabel(
          RegExp('${day.month}/${day.day}[.,]'),
        );
        expect(row, findsWidgets, reason: 'no row for ${day.day}');
        expect(
          tester.getTopLeft(row.first).dy,
          lessThan(fold),
          reason: '${day.day} sits below the fold',
        );
      }

      // Four days at 2,000, and all four figures readable without scrolling.
      final Finder eaten = find.textContaining('2000');
      expect(eaten, findsNWidgets(4));
      for (final Element e in eaten.evaluate()) {
        expect(
          tester.getTopLeft(find.byWidget(e.widget)).dy,
          lessThan(fold),
          reason: 'a day total sits below the fold',
        );
      }
      expect(find.textContaining('2200'), findsWidgets);
    });

    testWidgets('a planned day reads as a projection, not as a result', (
      WidgetTester tester,
    ) async {
      final List<DateTime> days = weekOf(monday);
      await openWeek(
        tester,
        week: <DateTime, List<MealPlanEntry>>{
          days[4]: <MealPlanEntry>[
            MealPlanEntry(
              id: 'e-planned',
              dayId: 'day-${days[4].day}',
              slot: MealSlot.dinner,
              refType: PlanRefType.food,
              refId: 'f-1',
              servings: 1,
            ),
          ],
        },
      );

      expect(find.textContaining('nothing logged yet'), findsOneWidget);
    });

    testWidgets('and a projection that cannot be computed claims nothing', (
      WidgetTester tester,
    ) async {
      // A planned meal whose food is not matched projects no calories. That
      // is not the same fact as a plan that comes to none, and "planned 0
      // kcal" states the second — on the row next to four days that really
      // do have figures.
      final List<DateTime> days = weekOf(monday);
      await openWeek(
        tester,
        week: <DateTime, List<MealPlanEntry>>{
          days[4]: <MealPlanEntry>[
            MealPlanEntry(
              id: 'e-unmatched',
              dayId: 'day-${days[4].day}',
              slot: MealSlot.dinner,
              refType: PlanRefType.recipe,
              refId: 'r-nobody-has',
              servings: 1,
            ),
          ],
        },
      );

      expect(find.textContaining('planned 0'), findsNothing);
      expect(find.textContaining('nothing logged yet'), findsOneWidget);
    });
  });

  group('the screen fits a small phone at large text', () {
    testWidgets('the page title no longer eats the viewport', (
      WidgetTester tester,
    ) async {
      // "This week" was 490 points at 2x on a 320-point phone, in a 380-point
      // viewport: the toggle above it already says Week and the range says
      // which one (review §6.2.1).
      await openWeek(tester, size: const Size(320, 568), scale: 2);

      expect(find.text('This week'), findsNothing);
      expect(find.textContaining('7–13 Sep'), findsWidgets);
    });

    testWidgets('and a day is on screen before any scrolling', (
      WidgetTester tester,
    ) async {
      // The measurable half of the same defect, and the one that matters. It
      // is not that the week is long — seven days of four figures at double
      // text genuinely need the height — it is that 490 points of chrome came
      // first, so the first thing on a screen about food was the word "This".
      await openWeek(tester, size: const Size(320, 568), scale: 2);

      // Against the fold, not against the range line. An earlier draft
      // measured from "7–13 Sep" down, which sat *below* the 490-point title
      // — so it passed on the screen it was written to catch. Where the first
      // day actually is on the screen is the only honest question.
      final double fold = tester.getTopLeft(find.text('Recipes').last).dy;
      final double firstRow = tester
          .getTopLeft(find.bySemanticsLabel(RegExp('9/7[.,]')).first)
          .dy;

      expect(
        firstRow,
        lessThan(fold),
        reason: 'the first day starts $firstRow points down, the fold is $fold',
      );
      expect(
        find.textContaining('2000'),
        findsWidgets,
        reason: 'not one day of figures is built at all',
      );
    });
  });

  testWidgets('an opened row opens its own day, not whichever is selected', (
    WidgetTester tester,
  ) async {
    // Reachable, and the expansion is what makes it so: the open row is
    // remembered across a change of week, and the *selected* day is not.
    //
    // Open Wednesday. Step to next week — nothing matches, so nothing is
    // expanded. Step back with the today button, which selects today rather
    // than Wednesday: Wednesday's row re-opens, showing Wednesday's rings,
    // above a button that would have opened Thursday.
    await openWeek(tester);

    await tester.tap(find.bySemanticsLabel(RegExp('Wednesday 9/9[.,]')));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Next week'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Go to this week'));
    await pumpFrames(tester, frames: 12);

    expect(
      find.text('Open this day'),
      findsOneWidget,
      reason: 'the row did not re-open, so this proves nothing',
    );
    await tester.ensureVisible(find.text('Open this day'));
    await pumpFrames(tester);
    await tester.tap(find.text('Open this day'));
    await pumpFrames(tester, frames: 12);

    // The day screen names the day it is showing (#55).
    expect(
      find.textContaining('Wednesday'),
      findsWidgets,
      reason: 'the button under Wednesday opened a different day',
    );
  });

  testWidgets('the week template actions say what they do in words', (
    WidgetTester tester,
  ) async {
    // Two icon-only buttons with tooltips, which is a hover on a device with
    // no pointer (spec §6.3) — the same complaint Foods answered in #64.
    await openWeek(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Save this week to use again'), findsOneWidget);
    expect(find.text('Use a saved week'), findsOneWidget);
  });
}
