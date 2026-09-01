import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/planning/day_progress.dart';

import '../../support/app_harness.dart';

/// What is left, and what it is left *of* (spec §5.6).
///
/// The tiles said "142 protein left" and never said left of what. On its own
/// that number cannot tell you whether the day is going well — 142 left of 180
/// at breakfast is fine and 142 left of 180 at nine at night is not — and the
/// figure that settles it was behind a tap into the targets sheet.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2400,
    proteinG: 180,
    carbG: 220,
    fatG: 70,
  );

  Future<void> openToday(WidgetTester tester) async {
    await pumpHearthApp(tester, targets: targets);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
  }

  testWidgets('each tile says what its target is', (WidgetTester tester) async {
    await openToday(tester);

    expect(find.text('of 2400 kcal'), findsOneWidget);
    expect(find.text('of 180 g'), findsOneWidget);
    expect(find.text('of 220 g'), findsOneWidget);
    expect(find.text('of 70 g'), findsOneWidget);
  });

  testWidgets('the remainder is still the headline', (
    WidgetTester tester,
  ) async {
    // Nothing eaten yet, so everything is still to come. The big number stays
    // the remainder and the target sits under the bar — adding the target must
    // not turn the tile into a pair of equal numbers.
    await openToday(tester);

    expect(find.text('2400'), findsOneWidget);
    expect(find.textContaining('kcal left'), findsOneWidget);
  });

  testWidgets('a screen reader hears the target too', (
    WidgetTester tester,
  ) async {
    // The label is assembled by hand here, so it does not gain the new line on
    // its own — and half a readout is worse than none (§6.3).
    await openToday(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'protein:.*of 180 g')),
      findsOneWidget,
    );
  });
}
