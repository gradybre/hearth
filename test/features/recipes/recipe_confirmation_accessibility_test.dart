import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/widgets/undo_snackbar.dart';

const String _message = 'Added to My plan · Dinner · Wed, Sep 30';

Future<void> _showConfirmation(
  WidgetTester tester, {
  required VoidCallback onUndo,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: HearthTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(3)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () => showUndoSnackBar(
                ScaffoldMessenger.of(context),
                message: _message,
                onUndo: onUndo,
                stackedAction: true,
              ),
              child: const Text('Confirm'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('stacked Undo is readable at 3x and expires after six seconds', (
    WidgetTester tester,
  ) async {
    await _showConfirmation(tester, onUndo: () {});
    final SnackBar bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 6));
    expect(bar.persist, isFalse);
    final Rect message = tester.getRect(find.text(_message));
    expect(message.width, greaterThanOrEqualTo(256));
    expect(message.top, greaterThanOrEqualTo(0));
    expect(message.bottom, lessThanOrEqualTo(534));
    expect(find.text('Undo').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(undoWindow + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text(_message), findsNothing);
  });

  testWidgets('stacked Undo calls the action and dismisses immediately', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await _showConfirmation(tester, onUndo: () => calls++);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text(_message), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
