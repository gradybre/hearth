import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/recipes/recipe_scaler.dart';
import 'package:hearth/features/recipes/scale_control.dart';

Future<double?> pumpControl(
  WidgetTester tester, {
  double original = 4,
  double target = 4,
}) async {
  double? changed;
  await tester.pumpWidget(
    MaterialApp(
      theme: HearthTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => ScaleControl(
            originalServings: original,
            targetServings: changed ?? target,
            onChanged: (double value) => setState(() => changed = value),
          ),
        ),
      ),
    ),
  );
  return changed;
}

/// The yield the stepper is showing.
String yieldOf(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(ScaleControl),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              !(w.data ?? '').contains('×') &&
              w.data != 'Makes' &&
              w.data != 'Reset',
        ),
      ),
    )
    .data!;

void main() {
  group('target servings is the primary control', () {
    testWidgets('the stepper walks the yield up and down', (
      WidgetTester tester,
    ) async {
      await pumpControl(tester);
      expect(yieldOf(tester), '4');

      await tester.tap(find.byTooltip('One more serving'));
      await tester.pump();
      expect(yieldOf(tester), '5');

      await tester.tap(find.byTooltip('One fewer serving'));
      await tester.pump();
      expect(yieldOf(tester), '4');
    });

    testWidgets('cannot scale down to nothing', (WidgetTester tester) async {
      // A recipe that makes zero is not a scale, it is a mistake.
      await pumpControl(tester, original: 4, target: 1);

      // Found by icon, not by tooltip: a disabled IconButton drops its
      // tooltip, so byTooltip finds nothing at all here.
      final IconButton down = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove_circle_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(down.onPressed, isNull);
    });
  });

  group('multipliers', () {
    testWidgets('doubling sets the yield to twice the original', (
      WidgetTester tester,
    ) async {
      await pumpControl(tester);

      await tester.tap(find.text('2×'));
      await tester.pump();

      expect(yieldOf(tester), '8');
    });

    testWidgets('a half reads as a fraction, not a decimal', (
      WidgetTester tester,
    ) async {
      await pumpControl(tester);
      expect(find.text('½×'), findsOneWidget);

      await tester.tap(find.text('½×'));
      await tester.pump();
      expect(yieldOf(tester), '2');
    });

    testWidgets('the matching multiplier reads as selected', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpControl(tester, original: 4, target: 8);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Scale by 2×')),
        matchesSemantics(
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('reset', () {
    testWidgets('is offered only once something has been scaled', (
      WidgetTester tester,
    ) async {
      await pumpControl(tester);
      expect(find.text('Reset'), findsNothing);

      await tester.tap(find.text('2×'));
      await tester.pump();
      expect(find.text('Reset'), findsOneWidget);
    });

    testWidgets('puts the recipe back to how it was written', (
      WidgetTester tester,
    ) async {
      await pumpControl(tester);
      await tester.tap(find.text('3×'));
      await tester.pump();
      expect(yieldOf(tester), '12');

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(yieldOf(tester), '4');
      expect(find.text('Reset'), findsNothing);
    });
  });

  group('scaling notes (spec §5.2 — flagged, never auto-adjusted)', () {
    Future<void> pumpNotes(
      WidgetTester tester,
      List<ScalingWarning> warnings,
    ) => tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: Scaffold(body: ScalingNotes(warnings: warnings)),
      ),
    );

    testWidgets('say nothing when there is nothing to say', (
      WidgetTester tester,
    ) async {
      await pumpNotes(tester, const <ScalingWarning>[]);
      expect(find.text('Check these yourself'), findsNothing);
    });

    testWidgets('name the ingredient rather than warning in the abstract', (
      WidgetTester tester,
    ) async {
      await pumpNotes(tester, const <ScalingWarning>[
        ScalingWarning(kind: ScalingWarningKind.seasoning, subject: 'salt'),
        ScalingWarning(
          kind: ScalingWarningKind.leavening,
          subject: 'baking powder',
        ),
      ]);

      expect(find.textContaining('salt'), findsOneWidget);
      expect(find.textContaining('baking powder'), findsOneWidget);
    });

    testWidgets('say timings were left alone', (WidgetTester tester) async {
      await pumpNotes(tester, const <ScalingWarning>[
        ScalingWarning(
          kind: ScalingWarningKind.cookTime,
          subject: 'Bake for 40 minutes',
        ),
      ]);

      expect(find.textContaining('Timings are unchanged'), findsOneWidget);
    });
  });
}
