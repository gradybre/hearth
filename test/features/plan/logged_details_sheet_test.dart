import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/logged_details_sheet.dart';

const Macros _allSeven = Macros(
  kcal: 250.987654321,
  proteinG: 17.555555,
  carbG: 21.234567,
  fatG: 8.000000001,
  fiberG: 3.555555,
  sodiumMg: 1234.56789,
  cholesterolMg: 17.777777,
);

ServingOption _pot() => ServingOption(
  id: 'saved-pot',
  label: '170 g pot',
  amount: Quantity.of(170, Units.gram),
  macros: const Macros(kcal: 9999),
);

LoggedPortion _grams([double amount = 125.123456789]) =>
    LoggedPortion.tryCapture(
      amount: amount,
      unit: const PortionUnit.raw(Units.gram),
      servings: amount / 170,
      standard: _pot(),
    )!;

MacroSnapshot _snapshot({
  LoggedPortion? portion,
  double? servings,
  Macros macros = _allSeven,
  String label = 'Saved yogurt name',
  NutrientCoverage coverage = const NutrientCoverage.allComplete(),
  bool approximate = false,
  DateTime? capturedAt,
}) => MacroSnapshot(
  macros: macros,
  servings: servings ?? portion?.servings ?? 1.5,
  capturedAt: capturedAt ?? DateTime.utc(2026, 6, 2, 10, 35),
  label: label,
  coverage: coverage,
  usesApproximatePackageNutrition: approximate,
  loggedPortion: portion,
);

MealPlanEntry _entry({
  MacroSnapshot? snapshot,
  PlanRefType type = PlanRefType.food,
  bool logged = true,
}) => MealPlanEntry(
  id: 'saved-meal',
  dayId: 'saved-day',
  slot: MealSlot.lunch,
  refType: type,
  refId: 'current-source-must-not-be-read',
  // Deliberately different: the historical sheet must answer from snapshot.
  servings: 99,
  isLogged: logged,
  loggedAt: DateTime.utc(2026, 10, 1, 21),
  macroSnapshot: snapshot,
);

Future<List<LoggedDetailsAction?>> _openDetails(
  WidgetTester tester, {
  required MealPlanEntry entry,
  bool sourceAvailable = true,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.padding = FakeViewPadding(top: 24, bottom: keyboard > 0 ? 0 : 34);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final List<LoggedDetailsAction?> results = <LoggedDetailsAction?>[];
  // No ProviderScope or repository. This must work from frozen evidence alone;
  // a live-library lookup or write would have no provider to obtain it from.
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? HearthTheme.light()
          : HearthTheme.dark(),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                results.add(
                  await showLoggedDetailsSheet(
                    context,
                    entry: entry,
                    sourceAvailable: sourceAvailable,
                  ),
                );
              },
              child: const Text('Read saved meal'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Read saved meal'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  try {
    await tester.scrollUntilVisible(
      finder,
      160,
      maxScrolls: 70,
      scrollable: find.descendant(
        of: find.byType(LoggedDetailsSheet),
        matching: find.byType(Scrollable),
      ),
    );
  } on StateError {
    expect(
      finder,
      findsOneWidget,
      reason: 'The saved detail must be reachable.',
    );
    rethrow;
  }
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  await _reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('raw entered amount retains all parsed digits, independent of editor rounding', () {
    final LoggedPortion portion = _grams();
    expect(portion.enteredUnit.format(portion.enteredAmount), '125.1');
    expect(loggedPortionLabel(_snapshot(portion: portion)), '125.123456789 g');
  });

  for (final double count in <double>[1.5, 1.5000000001]) {
    test(
      'named serving uses a multiplier without changing parsed amount $count',
      () {
        final ServingOption scoop = ServingOption(
          id: 'saved-scoop',
          label: '100 g scoop',
          amount: Quantity.of(100, Units.gram),
          macros: Macros.zero,
        );
        final LoggedPortion portion = LoggedPortion.tryCapture(
          amount: count,
          unit: PortionUnit.serving(scoop),
          servings: count * 100 / 170,
          standard: _pot(),
        )!;
        expect(
          loggedPortionLabel(_snapshot(portion: portion)),
          '${count == 1.5 ? '1 1/2' : '1.5000000001'} × 100 g scoop',
        );
      },
    );
  }

  testWidgets(
    'saved name, amount, serving basis and all seven nutrients read only the snapshot',
    (WidgetTester tester) async {
      final MacroSnapshot snapshot = _snapshot(portion: _grams());
      final Map<String, Object?> before = PlanMapper.snapshotToJson(snapshot);
      final List<LoggedDetailsAction?> results = await _openDetails(
        tester,
        entry: _entry(snapshot: snapshot),
      );
      await _reveal(tester, find.text('Saved yogurt name'));
      await _reveal(tester, find.text('125.123456789 g'));
      await _reveal(
        tester,
        find.text('Equivalent to about 0.736 × 170 g pot at log time.'),
      );
      for (final String reading in <String>[
        'Calories: 251 kcal',
        'Protein: 17.6 g',
        'Carbohydrate: 21.2 g',
        'Fat: 8 g',
        'Fibre: 3.6 g',
        'Sodium: 1235 mg',
        'Cholesterol: 18 mg',
      ]) {
        await _reveal(tester, find.text(reading));
        expect(find.text(reading).hitTestable(), findsOneWidget);
      }
      expect(find.textContaining('9999'), findsNothing);
      await _reveal(tester, find.textContaining('Recorded on'));
      expect(find.textContaining('June 2, 2026'), findsOneWidget);
      expect(find.textContaining('October'), findsNothing);
      await _press(tester, 'Close');
      expect(results, <LoggedDetailsAction?>[null]);
      expect(PlanMapper.snapshotToJson(snapshot), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'minor unknown, partial and unrecorded coverage remain distinct',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await _openDetails(
          tester,
          entry: _entry(
            snapshot: _snapshot(
              macros: const Macros(kcal: 100, fiberG: 2.789, cholesterolMg: 0),
              coverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
                MinorNutrient.fiber: MinorCoverage.partial,
                MinorNutrient.sodium: MinorCoverage.unknown,
                MinorNutrient.cholesterol: MinorCoverage.notRecorded,
              }),
              approximate: true,
            ),
          ),
        );
        await _reveal(tester, find.text('Uses approximate package servings'));
        await _reveal(tester, find.text('Fibre: At least 2.7 g'));
        expect(
          find.bySemanticsLabel(
            'Fibre: At least 2.7 g. Partial nutrition recorded',
          ),
          findsOneWidget,
        );
        await _reveal(tester, find.text('Sodium: Unknown'));
        expect(
          find.bySemanticsLabel('Sodium: Unknown. No value was available'),
          findsOneWidget,
        );
        await _reveal(tester, find.text('Cholesterol: 0 mg'));
        expect(
          find.bySemanticsLabel('Cholesterol: 0 mg. Coverage was not recorded'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('old coverage cannot turn missing nutrients into zero', (
    WidgetTester tester,
  ) async {
    await _openDetails(
      tester,
      entry: _entry(
        snapshot: _snapshot(
          macros: const Macros(kcal: 100),
          coverage: const NutrientCoverage.notRecorded(),
        ),
      ),
    );
    for (final String nutrient in <String>['Fibre', 'Sodium', 'Cholesterol']) {
      await _reveal(tester, find.text('$nutrient: Unknown'));
      expect(find.textContaining('$nutrient: 0'), findsNothing);
    }
    expect(find.text('Coverage was not recorded'), findsWidgets);
  });

  testWidgets(
    'stored unknown coverage does not make a placeholder zero a known nutrient',
    (WidgetTester tester) async {
      await _openDetails(
        tester,
        entry: _entry(
          snapshot: _snapshot(
            macros: const Macros(kcal: 100, sodiumMg: 0),
            coverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
              MinorNutrient.sodium: MinorCoverage.unknown,
            }),
          ),
        ),
      );
      await _reveal(tester, find.text('Sodium: Unknown'));
      expect(find.text('Sodium: 0 mg'), findsNothing);
    },
  );

  final Map<String, Object?> ignoredEvidence = <String, Object?>{
    'older record': null,
    'explicitly absent evidence': null,
    'malformed record': 'not a portion',
    'unknown version': <String, Object?>{..._grams().toJson(), 'version': 99},
    'stale evidence': _grams().toJson(),
  };
  for (final MapEntry<String, Object?> evidence in ignoredEvidence.entries) {
    testWidgets(
      '${evidence.key} uses frozen servings and admits the missing original amount',
      (WidgetTester tester) async {
        final MacroSnapshot snapshot = PlanMapper.snapshotFromJson(
          jsonEncode(<String, Object?>{
            ...PlanMapper.snapshotToJson(_snapshot(servings: 1.5)),
            if (evidence.key != 'older record')
              'logged_portion': evidence.value,
          }),
        )!;
        final Map<String, Object?> before = PlanMapper.snapshotToJson(snapshot);
        expect(snapshot.usableLoggedPortion, isNull);
        await _openDetails(tester, entry: _entry(snapshot: snapshot));
        await _reveal(tester, find.text('1 1/2 servings'));
        await _reveal(
          tester,
          find.text(
            evidence.value == null
                ? 'The original amount wasn’t recorded. These are the saved servings.'
                : 'The original amount is unavailable. These are the saved servings.',
          ),
        );
        if (evidence.value != null) {
          expect(find.textContaining('wasn’t recorded'), findsNothing);
        }
        expect(find.text('125.123456789 g'), findsNothing);
        expect(find.textContaining('170 g pot'), findsNothing);
        await _press(tester, 'Close');
        expect(PlanMapper.snapshotToJson(snapshot), before);
      },
    );
  }

  testWidgets(
    'a recipe retains its frozen servings without guessing a food quantity',
    (WidgetTester tester) async {
      await _openDetails(
        tester,
        entry: _entry(
          type: PlanRefType.recipe,
          snapshot: _snapshot(servings: 1),
        ),
      );
      await _reveal(tester, find.text('1 serving'));
      expect(
        find.textContaining('original amount wasn’t recorded'),
        findsNothing,
      );
      expect(find.textContaining('170 g'), findsNothing);
    },
  );

  testWidgets('blank name and epoch timestamp do not invent historical facts', (
    WidgetTester tester,
  ) async {
    await _openDetails(
      tester,
      entry: _entry(
        snapshot: _snapshot(
          label: '   ',
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ),
    );
    await _reveal(tester, find.text('Name not recorded'));
    await _reveal(tester, find.text('Recorded time not available'));
    expect(find.textContaining('1970'), findsNothing);
    expect(find.textContaining('current-source'), findsNothing);
  });

  for (final PlanRefType type in PlanRefType.values) {
    testWidgets('${type.name} source action only returns navigation intent', (
      WidgetTester tester,
    ) async {
      final List<LoggedDetailsAction?> results = await _openDetails(
        tester,
        entry: _entry(
          type: type,
          snapshot: _snapshot(portion: _grams()),
        ),
      );
      await _press(
        tester,
        type == PlanRefType.food ? 'View current food' : 'View current recipe',
      );
      expect(results, <LoggedDetailsAction?>[LoggedDetailsAction.viewCurrent]);
      expect(find.byType(LoggedDetailsSheet), findsNothing);
    });
  }

  for (final PlanRefType type in PlanRefType.values) {
    testWidgets(
      '3x ${type.name} action text stays inside its painted outline',
      (WidgetTester tester) async {
        final String label = type == PlanRefType.food
            ? 'View current food'
            : 'View current recipe';
        await _openDetails(
          tester,
          entry: _entry(
            type: type,
            snapshot: _snapshot(portion: _grams()),
          ),
          textScale: 3,
        );
        await _reveal(tester, find.text(label));
        final Finder button = find.widgetWithText(OutlinedButton, label);
        final Finder material = find.descendant(
          of: button,
          matching: find.byType(Material),
        );
        final Material surface = tester.widget<Material>(material);
        final RenderBox surfaceBox = tester.renderObject<RenderBox>(material);
        final RenderParagraph text = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final Path interior = surface.shape!.getInnerPath(
          Offset.zero & surfaceBox.size,
          textDirection: TextDirection.ltr,
        );
        // The bundled production font is loaded by flutter_test_config.dart.
        // Measure each painted line's glyph bounds in the actual button shape,
        // not the larger Text widget rectangle or the declared text alignment.
        final List<TextBox> lines = text.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(
          lines.length,
          greaterThan(1),
          reason: 'Exercise a wrapped label.',
        );
        for (final TextBox line in lines) {
          final Rect bounds = MatrixUtils.transformRect(
            text.getTransformTo(surfaceBox),
            line.toRect(),
          );
          for (final Offset corner in <Offset>[
            bounds.topLeft,
            bounds.topRight,
            bounds.bottomLeft,
            bounds.bottomRight,
          ]) {
            expect(
              interior.contains(corner),
              isTrue,
              reason:
                  '$label glyph bounds $bounds cross the button outline '
                  'at $corner (button size ${surfaceBox.size}).',
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'deleted source leaves saved details and portion correction available',
    (WidgetTester tester) async {
      final MacroSnapshot snapshot = _snapshot(portion: _grams());
      final Map<String, Object?> before = PlanMapper.snapshotToJson(snapshot);
      final List<LoggedDetailsAction?> results = await _openDetails(
        tester,
        entry: _entry(snapshot: snapshot),
        sourceAvailable: false,
      );
      await _reveal(tester, find.text('125.123456789 g'));
      await _reveal(
        tester,
        find.text(
          'The current library item is unavailable. Your saved log is still here.',
        ),
      );
      expect(find.textContaining('View current'), findsNothing);
      // Return upward to the editor action after reading the unavailable notice.
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      await _press(tester, 'Edit portion');
      expect(results, <LoggedDetailsAction?>[LoggedDetailsAction.editPortion]);
      expect(PlanMapper.snapshotToJson(snapshot), before);
    },
  );

  for (final bool logged in <bool>[false, true]) {
    testWidgets(
      '${logged ? 'missing snapshot' : 'planned meal'} has no invented saved details',
      (WidgetTester tester) async {
        await _openDetails(
          tester,
          entry: _entry(
            snapshot: logged ? null : _snapshot(portion: _grams()),
            logged: logged,
          ),
        );
        expect(
          find.text('Saved nutrition is unavailable for this meal.'),
          findsOneWidget,
        );
        expect(find.text('Edit portion'), findsNothing);
        expect(find.textContaining('View current'), findsNothing);
        await _press(tester, 'Close');
      },
    );
  }

  for (final Brightness brightness in Brightness.values) {
    for (final String action in <String>[
      'Edit portion',
      'View current food',
      'Close',
    ]) {
      testWidgets(
        '320pt 3x ${brightness.name} keeps $action above the keyboard',
        (WidgetTester tester) async {
          const double keyboard = 180;
          final SemanticsHandle semantics = tester.ensureSemantics();
          try {
            final List<LoggedDetailsAction?> results = await _openDetails(
              tester,
              entry: _entry(snapshot: _snapshot(portion: _grams())),
              textScale: 3,
              brightness: brightness,
              keyboard: keyboard,
            );
            await _reveal(tester, find.text(action));
            final Finder button = find.ancestor(
              of: find.text(action),
              matching: find.byWidgetPredicate(
                (Widget widget) => widget is ButtonStyleButton,
              ),
            );
            final Rect bounds = tester.getRect(button);
            expect(bounds.bottom, lessThanOrEqualTo(568 - keyboard));
            expect(bounds.top, greaterThanOrEqualTo(24));
            expect(bounds.height, greaterThanOrEqualTo(44));
            expect(bounds.width, greaterThanOrEqualTo(44));
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await tester.tap(find.text(action));
            await tester.pumpAndSettle();
            expect(results, <LoggedDetailsAction?>[
              switch (action) {
                'Edit portion' => LoggedDetailsAction.editPortion,
                'View current food' => LoggedDetailsAction.viewCurrent,
                _ => null,
              },
            ]);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
