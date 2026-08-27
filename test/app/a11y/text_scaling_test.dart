import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/a11y/accessibility.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/features/recipes/type_specimen_screen.dart';

Future<void> _pumpAtScale(
  WidgetTester tester,
  double scale, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? HearthTheme.light()
          : HearthTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const Scaffold(body: TypeSpecimenScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('dynamic type is honoured, not capped (spec §6.3)', () {
    // Regression: the macro tiles were laid out on a fixed aspect ratio, which
    // clipped the readout at 63pt of height. Tiles must size to content.
    for (final double scale in <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
      testWidgets('macro tiles do not overflow at ${scale}x text', (
        WidgetTester tester,
      ) async {
        await _pumpAtScale(tester, scale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout overflowed at ${scale}x text scale',
        );
      });
    }

    testWidgets('text really does grow with the scale factor', (
      WidgetTester tester,
    ) async {
      await _pumpAtScale(tester, 1.0);
      final Size small = tester.getSize(find.text('1,847'));

      await _pumpAtScale(tester, 2.0);
      final Size large = tester.getSize(find.text('1,847'));

      expect(
        large.height,
        greaterThan(small.height * 1.5),
        reason: 'the macro readout must scale, not stay fixed',
      );
    });

    testWidgets('the specimen renders in dark mode too', (
      WidgetTester tester,
    ) async {
      await _pumpAtScale(tester, 1.0, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Braised Short Ribs'), findsOneWidget);
    });
  });

  group('macro column reflow', () {
    Future<int> columnsAt(
      WidgetTester tester,
      double scale, {
      double width = 800,
    }) async {
      late int columns;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (BuildContext context) {
                columns = A11y.macroColumns(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return columns;
    }

    testWidgets('a wide window steps 4 to 2 to 1 as text grows', (
      WidgetTester tester,
    ) async {
      expect(await columnsAt(tester, 1.0), 4);
      expect(await columnsAt(tester, 1.3), 4);
      expect(await columnsAt(tester, 1.5), 2);
      expect(await columnsAt(tester, 2.5), 1);
    });

    testWidgets('a phone starts at two columns, not four', (
      WidgetTester tester,
    ) async {
      // Regression: four 36pt readouts across 390pt wrapped "1,847" onto two
      // lines at default text size.
      expect(await columnsAt(tester, 1.0, width: 390), 2);
      expect(await columnsAt(tester, 1.5, width: 390), 1);
    });
  });

  group('reduced motion (spec §6.3)', () {
    testWidgets('animation durations collapse to zero when asked', (
      WidgetTester tester,
    ) async {
      late Duration normal;
      late Duration reduced;

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              MediaQuery(
                data: const MediaQueryData(),
                child: Builder(
                  builder: (BuildContext context) {
                    normal = A11y.motion(
                      context,
                      const Duration(milliseconds: 200),
                    );
                    return const SizedBox();
                  },
                ),
              ),
              MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Builder(
                  builder: (BuildContext context) {
                    reduced = A11y.motion(
                      context,
                      const Duration(milliseconds: 200),
                    );
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(normal, const Duration(milliseconds: 200));
      expect(reduced, Duration.zero);
    });
  });

  group('over/under never relies on colour alone (spec §6.3)', () {
    test('each state carries a distinct icon and spoken label', () {
      final Set<IconData> icons = <IconData>{};
      final Set<String> labels = <String>{};
      for (final TargetState state in TargetState.values) {
        final TargetIndicator indicator = TargetIndicator.forState(state);
        icons.add(indicator.icon);
        labels.add(indicator.semanticLabel);
        expect(indicator.shortLabel, isNotEmpty);
      }
      expect(icons, hasLength(TargetState.values.length));
      expect(labels, hasLength(TargetState.values.length));
    });

    test('an amount is woven into the spoken label when known', () {
      expect(
        TargetIndicator.forState(
          TargetState.under,
          amount: '142 g',
        ).semanticLabel,
        'Under target, 142 g left.',
      );
      expect(
        TargetIndicator.forState(
          TargetState.over,
          amount: '20 g',
        ).semanticLabel,
        'Over target by 20 g.',
      );
    });
  });
}
