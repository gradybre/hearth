import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

/// What survives a trip out to Home and back (spec §6.2, U08).
///
/// The shell reads its tab from the route and keeps the four alive in an
/// IndexedStack. Going Home leaves the shell route entirely, so the stack is
/// disposed — and coming back lands on the section's first destination, which
/// is the recipe library, whatever you were looking at when you left.
void main() {
  List<Recipe> library() => <Recipe>[
    aRecipe(id: 'r1', title: 'Slow chilli'),
    aRecipe(id: 'r2', title: 'Butter beans'),
  ];

  /// The way out of a section: a chevron in the section bar, labelled for a
  /// screen reader rather than carrying a tooltip.
  ///
  /// Found by that label, not by its icon. The day header has a chevron of
  /// its own for the previous day, and tapping that one goes nowhere — which
  /// is how the first version of this test round-tripped without ever leaving
  /// the section, and then asserted happily about the screen it had not left.
  Future<void> goHome(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Home\. Leave ')));
    await pumpFrames(tester, frames: 16);

    expect(
      find.byType(NavigationBar),
      findsNothing,
      reason: 'still inside the section, so this proves nothing',
    );
  }

  Future<void> backToNutrition(WidgetTester tester) async {
    await tester.tap(find.text('Nutrition').last);
    await pumpFrames(tester, frames: 16);
  }

  testWidgets('the tab you were on', (WidgetTester tester) async {
    await pumpHearthApp(tester, recipes: library());
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    expect(find.text('Day'), findsWidgets);

    await goHome(tester);
    await backToNutrition(tester);

    expect(
      find.text('Day'),
      findsWidgets,
      reason: 'it went back to the recipe library rather than the plan',
    );
  });

  testWidgets('and the search you had typed', (WidgetTester tester) async {
    await pumpHearthApp(tester, recipes: library());
    await tester.enterText(find.byType(TextField).first, 'chilli');
    await pumpFrames(tester, frames: 12);
    expect(find.text('Butter beans'), findsNothing);

    await goHome(tester);
    await backToNutrition(tester);

    expect(
      find.text('Butter beans'),
      findsNothing,
      reason: 'the search was forgotten on the way out',
    );
  });

  test('and a different account does not inherit where you were', () async {
    // Claimed in the doc comment and asserted nowhere, which is how a
    // sentence becomes untrue. Which screen someone was reading is theirs.
    String who = 'user-a';
    final ProviderContainer container = ProviderContainer(
      overrides: [currentUserIdProvider.overrideWith((Ref ref) => who)],
    );
    addTearDown(container.dispose);

    final BuiltSection nutrition = builtSections.first;
    container
        .read(lastDestinationProvider.notifier)
        .remember(section: nutrition.id, path: '/plan');
    expect(
      container.read(lastDestinationProvider.notifier).pathFor(nutrition),
      '/plan',
    );

    who = 'user-b';
    container.invalidate(currentUserIdProvider);

    expect(
      container.read(lastDestinationProvider.notifier).pathFor(nutrition),
      nutrition.path,
      reason: "the next account opened on the last one's screen",
    );
  });
}
