import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/undo_snackbar.dart';

/// The "Deleted X · Undo" pattern every delete in Hearth shares.
///
/// Brendan's report: it stayed on screen until swiped away. The two things
/// worth pinning down are exactly the two things that would produce that —
/// an unset (so platform-default) duration, and an Undo that fires the
/// callback but leaves the snackbar counting down the rest of it regardless.
Future<void> pumpScaffold(
  WidgetTester tester, {
  required VoidCallback onUndo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showUndoSnackBar(
                ScaffoldMessenger.of(context),
                message: 'Deleted 1 food',
                onUndo: onUndo,
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('has a deliberate, finite duration', (WidgetTester tester) async {
    await pumpScaffold(tester, onUndo: () {});
    await tester.tap(find.text('trigger'));
    await tester.pump();

    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, undoWindow);
  });

  testWidgets('auto-dismisses once the window elapses', (
    WidgetTester tester,
  ) async {
    await pumpScaffold(tester, onUndo: () {});
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted 1 food'), findsOneWidget);

    await tester.pump(undoWindow + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Deleted 1 food'), findsNothing);
  });

  testWidgets('tapping Undo removes it immediately, not after the window', (
    WidgetTester tester,
  ) async {
    // The other half of the report: the callback firing is not enough if the
    // snackbar then sits there for the rest of undoWindow regardless.
    bool undone = false;
    await pumpScaffold(tester, onUndo: () => undone = true);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('Deleted 1 food'), findsNothing);
  });

  testWidgets('a second delete replaces the first rather than queuing', (
    WidgetTester tester,
  ) async {
    await pumpScaffold(tester, onUndo: () {});
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted 1 food'), findsOneWidget);
  });
}
