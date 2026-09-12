import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Getting back out of a room (spec §6.2).
///
/// A section fills the app once you are in one, so the way home has to be in
/// the same place whichever of its four screens you are looking at — and it has
/// to survive the window being resized from a phone to a desk, because that is
/// one of the two layouts the shell switches between.
void main() {
  const Size phone = Size(390, 844);
  const Size desktop = Size(1440, 900);

  /// The system back gesture, as the OS delivers it.
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (ByteData? _) {},
    );
    await pumpFrames(tester);
  }

  testWidgets('a phone-width section carries the way home above the content', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    expect(find.text('Home'), findsOneWidget);
    // And says which room you are in, so the tabs read as this section's.
    expect(find.text('Nutrition'), findsOneWidget);
  });

  testWidgets('and a desktop-width one carries it at the top of the sidebar', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: desktop);
    await pumpFrames(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
  });

  testWidgets('it is there from every tab, not only the one you land on', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    for (final String tab in <String>['Plan', 'Shopping', 'Foods']) {
      await tester.tap(find.text(tab).last);
      await pumpFrames(tester);
      expect(
        find.text('Home'),
        findsOneWidget,
        reason: 'lost the way out of $tab',
      );
    }
  });

  testWidgets('tapping it leaves the section', (WidgetTester tester) async {
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    await tester.tap(find.text('Home'));
    await pumpFrames(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Hearth'), findsOneWidget);
  });

  testWidgets('and it says out loud what it leaves, not just "Home"', (
    WidgetTester tester,
  ) async {
    // "Home" alone is ambiguous in an app whose sections are rooms (§6.3).
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    expect(
      find.bySemanticsLabel(
        'Home. Leave Nutrition and go back to all of Hearth.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the system back gesture goes home rather than closing the app', (
    WidgetTester tester,
  ) async {
    // Entering a section replaces the route rather than pushing onto it, so
    // there is nothing underneath to pop — without the shell catching it, back
    // from Recipes would put the user on their device's home screen.
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    await pressSystemBack(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Hearth'), findsOneWidget);
  });

  group('the paths the app already uses still resolve (spec §6.2)', () {
    testWidgets(
      'a recipe opens from inside the section, and comes back to it',
      (WidgetTester tester) async {
        // Detail routes were never nested under a section and still are not:
        // every `context.push('/recipe/…')` in the app depends on it.
        await pumpHearthApp(
          tester,
          size: phone,
          recipes: <Recipe>[
            aRecipe(
              id: 'ribs',
              title: 'Braised short ribs',
              sections: <RecipeSection>[aSection(id: 'sec-ribs')],
            ),
          ],
        );
        await pumpFrames(tester);

        await tester.tap(find.text('Braised short ribs').first);
        await pumpFrames(tester, frames: 10);
        expect(find.text('Braised short ribs'), findsWidgets);

        await tester.pageBack();
        await pumpFrames(tester, frames: 10);
        expect(find.byType(NavigationBar), findsOneWidget);
      },
    );

    testWidgets('a section tab reached from the home screen is the same route '
        'as before', (WidgetTester tester) async {
      await pumpHearthApp(tester, size: phone, launchTarget: LaunchTarget.home);
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);

      expect(find.text('Shopping for'), findsOneWidget);
    });
  });
}
