import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/nutrient_contributors_screen.dart';

MealPlanEntry _entry({
  String id = 'saved',
  String name = 'Saved yoghurt name',
  double? fiber = 3,
  MinorCoverage coverage = MinorCoverage.complete,
  bool snapshot = true,
}) {
  final ServingOption serving = ServingOption(
    id: 'pot',
    label: '170 g pot',
    amount: Quantity.of(170, Units.gram),
    macros: const Macros(kcal: 900),
  );
  return MealPlanEntry(
    id: id,
    dayId: 'old-day',
    slot: MealSlot.lunch,
    refType: PlanRefType.food,
    refId: 'current-source',
    servings: 99,
    isLogged: true,
    macroSnapshot: snapshot
        ? MacroSnapshot(
            label: name,
            servings: 125 / 170,
            capturedAt: DateTime(2026, 9, 29, 12),
            macros: Macros(kcal: 125, fiberG: fiber),
            coverage: NutrientCoverage(<MinorNutrient, MinorCoverage>{
              MinorNutrient.fiber: coverage,
            }),
            loggedPortion: LoggedPortion.tryCapture(
              amount: 125,
              unit: const PortionUnit.raw(Units.gram),
              servings: 125 / 170,
              standard: serving,
            ),
          )
        : null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<MealPlanEntry> entries,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool sourceAvailable = true,
  bool Function(MealPlanEntry)? sourceAvailability,
  SupportedNutrient nutrient = SupportedNutrient.fiber,
  Future<void> Function(MealPlanEntry)? onDetails,
  Future<void> Function(MealPlanEntry)? onImprove,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final DailyNutrientContributors projection = DailyNutrientContributors(
    date: DateTime(2026, 9, 30),
    nutrient: nutrient,
    entries: entries,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? HearthTheme.light()
          : HearthTheme.dark(),
      home: NutrientContributorsScreen(
        contributors: projection,
        onOpenLoggedDetails: onDetails ?? (_) async {},
        onImproveFuture: onImprove ?? (_) async {},
        isSourceAvailable: sourceAvailability ?? (_) => sourceAvailable,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'uses saved names, portions and captured day without any repository',
    (WidgetTester tester) async {
      await _pump(tester, entries: <MealPlanEntry>[_entry()]);
      expect(find.byType(NutrientContributorsScreen), findsOneWidget);
      expect(find.text('Wednesday, September 30, 2026'), findsOneWidget);
      await _reveal(tester, find.text('Saved yoghurt name'));
      expect(find.text('125 g'), findsOneWidget);
      expect(find.text('99 servings'), findsNothing);
      expect(find.text('3 g'), findsWidgets);
      expect(find.text('100% of total'), findsOneWidget);
    },
  );

  testWidgets(
    'details and future editor run only after deliberate separate actions',
    (WidgetTester tester) async {
      final MealPlanEntry entry = _entry();
      final List<MealPlanEntry> details = <MealPlanEntry>[];
      final List<MealPlanEntry> improve = <MealPlanEntry>[];
      await _pump(
        tester,
        entries: <MealPlanEntry>[entry],
        onDetails: (MealPlanEntry selected) async {
          details.add(selected);
        },
        onImprove: (MealPlanEntry selected) async {
          improve.add(selected);
        },
      );
      expect(details, isEmpty);
      expect(improve, isEmpty);
      final Finder row = find.byKey(
        const ValueKey<String>('contributor-known-open-saved'),
      );
      await _reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(details.single, same(entry));
      expect(improve, isEmpty);
      final Finder edit = find.byKey(
        const ValueKey<String>('contributor-known-improve-saved'),
      );
      await _reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(improve.single, same(entry));
      expect(entry.macroSnapshot!.macros.fiberG, 3);
      expect(find.byType(NutrientContributorsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'partial known shares and nutrient-specific missing information stay distinct',
    (WidgetTester tester) async {
      await _pump(
        tester,
        entries: <MealPlanEntry>[
          _entry(id: 'complete', fiber: 3),
          _entry(
            id: 'partial',
            name: 'Saved oats',
            fiber: 2,
            coverage: MinorCoverage.partial,
          ),
          _entry(
            id: 'unknown',
            name: 'Saved soup',
            fiber: null,
            coverage: MinorCoverage.unknown,
          ),
        ],
      );
      await _reveal(tester, find.text('60% of known total'));
      await _reveal(tester, find.text('40% of known total'));
      await _reveal(tester, find.text('Missing information'));
      await _reveal(
        tester,
        find.text(
          'Some fibre information was missing when this meal was logged.',
        ),
      );
      await _reveal(
        tester,
        find.text('No fibre value was saved for this meal.'),
      );
    },
  );

  testWidgets('legacy coverage is qualified and has no percentages', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      entries: <MealPlanEntry>[_entry(coverage: MinorCoverage.notRecorded)],
    );
    await _reveal(
      tester,
      find.byKey(const ValueKey<String>('contributor-known-open-saved')),
    );
    expect(find.text('3 g'), findsWidgets);
    expect(find.textContaining('%'), findsNothing);
    await _reveal(
      tester,
      find.text('Fibre coverage was not recorded for this meal.'),
    );
  });

  testWidgets(
    'missing snapshot explains absence and does not fabricate a name or amount',
    (WidgetTester tester) async {
      await _pump(tester, entries: <MealPlanEntry>[_entry(snapshot: false)]);
      expect(find.text('No saved fibre values'), findsOneWidget);
      await _reveal(
        tester,
        find.text('Saved nutrition is unavailable for this meal.'),
      );
      expect(find.text('99 servings'), findsNothing);
      expect(find.text('0 g'), findsNothing);
      expect(find.text('Saved yoghurt name'), findsNothing);
    },
  );

  testWidgets(
    'known zero stays numeric while explicit unknown does not become zero',
    (WidgetTester tester) async {
      await _pump(tester, entries: <MealPlanEntry>[_entry(fiber: 0)]);
      expect(find.text('0 g'), findsWidgets);
      await _pump(
        tester,
        entries: <MealPlanEntry>[
          _entry(fiber: 0, coverage: MinorCoverage.unknown),
        ],
      );
      expect(find.text('No saved fibre values'), findsOneWidget);
      expect(find.text('0 g'), findsNothing);
    },
  );

  for (final ({double value, String text}) example
      in <({double value, String text})>[
        (value: 11.266666666666667, text: 'about 11.2667 g'),
        (value: -11.266666666666667, text: 'about -11.2667 g'),
        (value: 1.23456789e-12, text: 'about 1.23457e-12 g'),
        (value: 1e-12, text: '1e-12 g'),
        (value: double.minPositive, text: '5e-324 g'),
        (value: -2, text: '-2 g'),
        (value: 12, text: '12 g'),
        (value: 0, text: '0 g'),
      ]) {
    testWidgets(
      'saved amount reads ${example.text} without changing its value',
      (WidgetTester tester) async {
        final MealPlanEntry saved = _entry(fiber: example.value);
        await _pump(tester, entries: <MealPlanEntry>[saved]);
        await _reveal(tester, find.text(example.text).first);
        expect(find.text(example.text), findsWidgets);
        final NutrientContributorsScreen screen = tester.widget(
          find.byType(NutrientContributorsScreen),
        );
        expect(screen.contributors.knownTotal, example.value);
        expect(saved.macroSnapshot!.macros.fiberG, example.value);
        if (example.value != 0) expect(find.text('0 g'), findsNothing);
      },
    );
  }

  testWidgets(
    'summed binary tail is qualified while ordinary saved values stay exact',
    (WidgetTester tester) async {
      await _pump(
        tester,
        entries: <MealPlanEntry>[
          _entry(id: 'one', fiber: 0.1),
          _entry(id: 'two', fiber: 0.2),
        ],
      );
      expect(find.text('about 0.3 g'), findsOneWidget);
      expect(find.text('0.30000000000000004 g'), findsNothing);
      await _reveal(tester, find.text('0.1 g'));
      await _reveal(tester, find.text('0.2 g'));
      final NutrientContributorsScreen screen = tester.widget(
        find.byType(NutrientContributorsScreen),
      );
      expect(screen.contributors.knownTotal, 0.1 + 0.2);
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'fractional amount at 3x ${brightness.name} keeps its qualification and actions readable',
      (WidgetTester tester) async {
        await _pump(
          tester,
          entries: <MealPlanEntry>[_entry(fiber: 11.266666666666667)],
          scale: 3,
          brightness: brightness,
        );
        await _reveal(tester, find.text('about 11.2667 g').first);
        final RenderParagraph amount = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('about 11.2667 g').first,
            matching: find.byType(RichText),
          ),
        );
        expect(
          amount
              .getBoxesForSelection(
                const TextSelection(baseOffset: 6, extentOffset: 13),
              )
              .map((box) => box.top)
              .toSet(),
          hasLength(1),
          reason: 'The six-digit amount must not split across lines.',
        );
        expect(
          amount
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 5),
              )
              .map((box) => box.top)
              .toSet(),
          hasLength(1),
          reason: 'Keep the approximation qualifier readable as one word.',
        );
        final Finder action = find.byKey(
          const ValueKey<String>('contributor-known-improve-saved'),
        );
        await _reveal(tester, action);
        final Rect bounds = tester.getRect(action);
        expect(bounds.top, greaterThanOrEqualTo(24));
        expect(bounds.bottom, lessThanOrEqualTo(534));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty date states nothing logged instead of zero', (
    WidgetTester tester,
  ) async {
    await _pump(tester, entries: <MealPlanEntry>[]);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('0 g'), findsNothing);
    expect(find.text('Missing information'), findsNothing);
  });

  testWidgets(
    'missing source leaves saved details readable and explains unavailable editing',
    (WidgetTester tester) async {
      final List<MealPlanEntry> details = <MealPlanEntry>[];
      await _pump(
        tester,
        entries: <MealPlanEntry>[_entry()],
        sourceAvailable: false,
        onDetails: (MealPlanEntry entry) async {
          details.add(entry);
        },
      );
      await _reveal(
        tester,
        find.text(
          'The current food is unavailable. This saved log is unchanged.',
        ),
      );
      expect(find.text('Improve future logs'), findsNothing);
      final Finder row = find.byKey(
        const ValueKey<String>('contributor-known-open-saved'),
      );
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(details, hasLength(1));
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'all-unknown 3x ${brightness.name} reveals the final future-edit action',
      (WidgetTester tester) async {
        final List<MealPlanEntry> improved = <MealPlanEntry>[];
        await _pump(
          tester,
          entries: <MealPlanEntry>[
            _entry(
              id: 'unknown',
              name: 'Roasted vegetable bowl',
              fiber: null,
              coverage: MinorCoverage.unknown,
            ),
            _entry(id: 'absent', snapshot: false),
          ],
          scale: 3,
          brightness: brightness,
          nutrient: brightness == Brightness.dark
              ? SupportedNutrient.cholesterol
              : SupportedNutrient.fiber,
          sourceAvailability: (MealPlanEntry entry) => entry.id != 'unknown',
          onImprove: (MealPlanEntry entry) async {
            improved.add(entry);
          },
        );
        await _reveal(tester, find.text('Missing information'));
        await _reveal(
          tester,
          find.text(
            'The current food is unavailable. This saved log is unchanged.',
          ),
        );
        final Finder action = find.byKey(
          const ValueKey<String>('contributor-missing-improve-absent'),
        );
        await _reveal(tester, action);
        final Rect bounds = tester.getRect(action);
        expect(bounds.top, greaterThanOrEqualTo(24));
        expect(bounds.bottom, lessThanOrEqualTo(534));
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(improved.single.id, 'absent');
      },
    );
    testWidgets(
      '320x568 3x ${brightness.name} keeps every row and action reachable',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          final List<MealPlanEntry> details = <MealPlanEntry>[];
          final List<MealPlanEntry> improve = <MealPlanEntry>[];
          await _pump(
            tester,
            entries: <MealPlanEntry>[
              _entry(
                name: 'Saved yoghurt with oats and summer berries',
                coverage: MinorCoverage.partial,
              ),
            ],
            scale: 3,
            brightness: brightness,
            onDetails: (MealPlanEntry entry) async {
              details.add(entry);
            },
            onImprove: (MealPlanEntry entry) async {
              improve.add(entry);
            },
          );
          for (final String section in <String>['known', 'missing']) {
            final Finder open = find.byKey(
              ValueKey<String>('contributor-$section-open-saved'),
            );
            final Finder label = find.descendant(
              of: open,
              matching: find.text('View logged details'),
            );
            await _reveal(tester, label);
            await tester.tap(label);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          final Finder edit = find.byKey(
            const ValueKey<String>('contributor-missing-improve-saved'),
          );
          await _reveal(tester, edit);
          final Rect bounds = tester.getRect(edit);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(bounds.top, greaterThanOrEqualTo(24));
          expect(bounds.bottom, lessThanOrEqualTo(534));
          expect(bounds.height, greaterThanOrEqualTo(48));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await tester.tap(edit);
          await tester.pumpAndSettle();
          expect(details, hasLength(2));
          expect(improve, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
