import 'dart:ui' show CheckedState, SemanticsFlags, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Every node that announces itself as a control must also be operable.
///
/// The trap this guards is `Semantics(button: true, excludeSemantics: true)`
/// wrapped around an `InkWell`: excluding descendants drops the InkWell's tap
/// action, so the node tells a screen-reader user "button" and then does
/// nothing when they activate it. Announcing a control you cannot press is
/// worse than not announcing it — the user has no way to know the difference
/// between a broken control and their own mistake (spec §6.3).
List<String> unactivatable(SemanticsNode root) {
  final List<String> offenders = <String>[];

  void visit(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    final SemanticsFlags flags = data.flagsCollection;
    final bool claimsControl =
        flags.isButton ||
        flags.isChecked != CheckedState.none ||
        flags.isSelected != Tristate.none;
    final bool operable =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.increase) ||
        data.hasAction(SemanticsAction.decrease);

    if (claimsControl && !operable) {
      offenders.add('"${data.label}"');
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return offenders;
}

void main() {
  testWidgets(
    'every announced control on the recipe library can be activated',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(
            id: 'ribs',
            title: 'Braised short ribs',
            cuisine: 'French',
            tags: <String>['sunday'],
            sections: <RecipeSection>[aSection(id: 'sec-ribs')],
          ),
        ],
      );
      await pumpFrames(tester);

      expect(
        unactivatable(tester.getSemantics(find.byType(MaterialApp))),
        isEmpty,
      );
      handle.dispose();
    },
  );

  testWidgets('every announced control on the planner can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('every announced control on the week summary can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);
    await tester.tap(find.text('Week'));
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('every announced control on the settings screen can be '
      'activated', (WidgetTester tester) async {
    // The densest use of the pattern in the app: every settings row and every
    // theme option announces itself as a button — and the theme options as a
    // selected one — with their descendants excluded. Six wrappers, none of
    // them guarded until now.
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester, size: const Size(500, 2400));
    await tester.tap(find.byTooltip('Household'));
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('every announced control in the log sheet can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(
      tester,
      recipes: <Recipe>[
        aRecipe(
          id: 'ribs',
          title: 'Braised short ribs',
          sections: <RecipeSection>[aSection(id: 'sec-ribs')],
        ),
      ],
    );
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.add).first);
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });
}
