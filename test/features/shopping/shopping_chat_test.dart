import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/shopping_assistant.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/shopping_edit.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

/// Changing the list by asking (spec §5.7).
class FakeAssistant implements ShoppingAssistant {
  FakeAssistant({this.answer, this.error});

  final ShoppingAnswer? answer;
  final Object? error;

  /// The list as the assistant was shown it, for asserting what it was told.
  String? sawList;
  int calls = 0;

  @override
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  }) async {
    calls++;
    sawList = shoppingListAsText(lines);
    if (error case final Object thrown) throw thrown;
    return answer!;
  }
}

class DeferredAssistant implements ShoppingAssistant {
  final Completer<ShoppingAnswer> response = Completer<ShoppingAnswer>();

  @override
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  }) => response.future;
}

void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Chilli',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'ground beef',
            amount: 2,
            unit: Units.pound,
            sectionId: 's1',
          ),
        ],
      ),
    ],
  );

  MealPlanEntry tonight() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 4,
  );

  Future<void> openWithList(
    WidgetTester tester, {
    ShoppingAssistant? assistant,
  }) async {
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[chilli()],
      entries: <MealPlanEntry>[tonight()],
      shoppingAssistant: assistant,
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    // Two taps: the empty card's `Build from the plan` opens the sheet that
    // carries the days it covers, and the sheet's own button commits it
    // (spec §5.7, as amended). `.last` is the sheet's — the card underneath
    // the modal wears the same words.
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Build from the plan').last);
    await pumpFrames(tester, frames: 24);
  }

  Future<void> ask(WidgetTester tester, String what) async {
    await tester.tap(find.text('More'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Ask for a change'));
    await pumpFrames(tester, frames: 12);
    await tester.enterText(
      find.widgetWithText(TextField, 'What should change?'),
      what,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await pumpFrames(tester, frames: 20);
  }

  ShoppingAnswer answer(List<ShoppingEdit> edits, {String? reply}) =>
      ShoppingAnswer(edits: edits, reply: reply);

  testWidgets('a build with no backend does not offer the chat', (
    WidgetTester tester,
  ) async {
    // Null is the honest state of a build with no Edge Function, and a button
    // that can only fail is worse than no button.
    await openWithList(tester);
    await tester.tap(find.text('More'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Ask for a change'), findsNothing);
  });

  testWidgets('an item asked for is added to the list', (
    WidgetTester tester,
  ) async {
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(<ShoppingEdit>[
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      ], reply: 'Added coffee.'),
    );
    await openWithList(tester, assistant: assistant);

    await ask(tester, 'add coffee');

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Added coffee.'), findsOneWidget);
  });

  testWidgets('and it goes away again on undo', (WidgetTester tester) async {
    // Preserve the existing apply/undo behavior while moving its entry.
    // A before/after proposal review remains the separate UX-063 scope.
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(<ShoppingEdit>[
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      ]),
    );
    await openWithList(tester, assistant: assistant);
    await ask(tester, 'add coffee');
    expect(find.text('Coffee'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Coffee'), findsNothing);
  });

  testWidgets('saying what you have already changes what to buy', (
    WidgetTester tester,
  ) async {
    // Brendan's case, and the one the live model got right: "I have a pound"
    // is not a tick, it is a subtraction.
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(<ShoppingEdit>[
        const ShoppingEdit(
          kind: ShoppingEditKind.setOnHand,
          name: 'the beef',
          amount: 1,
          unitId: 'lb',
        ),
      ]),
    );
    await openWithList(tester, assistant: assistant);

    await ask(tester, 'I already have a pound of the beef');

    expect(find.text('1 lb'), findsOneWidget);
    expect(find.textContaining('have 1 lb'), findsOneWidget);
  });

  testWidgets(
    'undo explains kept newer rows inside the active assistant sheet',
    (WidgetTester tester) async {
      final FakeAssistant assistant = FakeAssistant(
        answer: answer(<ShoppingEdit>[
          const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
        ], reply: 'Added coffee.'),
      );
      await openWithList(tester, assistant: assistant);
      await ask(tester, 'add coffee');
      await tester.tapAt(const Offset(200, 40));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Coffee'));
      await pumpFrames(tester, frames: 20);
      expect(find.text('Bought 1'), findsOneWidget);
      await tester.tap(find.text('More'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Ask for a change'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await pumpFrames(tester, frames: 20);

      final Finder notice = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(
          'Undone. One line you changed since was left as it is.',
        ),
      );
      expect(
        notice,
        findsOneWidget,
        reason: 'a snackbar behind the modal is invisible',
      );
      expect(notice.hitTestable(), findsOneWidget);
      expect(
        find.ancestor(
          of: notice,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Bought 1'), findsOneWidget);
    },
  );

  testWidgets('the question carries the list it is about', (
    WidgetTester tester,
  ) async {
    // "I have the beef" cannot mean anything without it.
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(const <ShoppingEdit>[]),
    );
    await openWithList(tester, assistant: assistant);

    await ask(tester, 'what is on here?');

    expect(assistant.sawList, contains('ground beef'));
  });

  testWidgets('the kept-row Undo notice comes into view at 320pt and 3x', (
    WidgetTester tester,
  ) async {
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(<ShoppingEdit>[
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      ], reply: 'Added coffee.'),
    );
    await pumpHearthApp(
      tester,
      size: const Size(320, 568),
      textScale: 3,
      viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
      shoppingLines: <ShoppingLine>[
        ShoppingLine.manual(key: 'bread', name: 'Bread'),
      ],
      shoppingAssistant: assistant,
    );
    final SweepTools tools = SweepTools(tester);
    await tools.tab('Shopping');
    await tools.reach(find.text('More'));
    await tools.reach(find.text('Ask for a change'));
    final Finder question = find.widgetWithText(
      TextField,
      'What should change?',
    );
    await tools.bring(question);
    await tester.enterText(question, 'add coffee');
    await tools.reach(find.widgetWithText(FilledButton, 'Ask'));
    await pumpFrames(tester, frames: 20);
    Navigator.of(tester.element(question)).pop();
    await pumpFrames(tester, frames: 12);
    await tools.reach(find.text('Coffee'));
    await tools.reach(find.text('More'));
    await tools.reach(find.text('Ask for a change'));
    await tools.reach(find.widgetWithText(TextButton, 'Undo'));
    await pumpFrames(tester, frames: 20);

    final Finder notice = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(
        'Undone. One line you changed since was left as it is.',
      ),
    );
    expect(notice.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(assistant.calls, 1);
  });

  testWidgets('a failure says the list is untouched, and offers another go', (
    WidgetTester tester,
  ) async {
    final FakeAssistant assistant = FakeAssistant(
      error: const RecipeAiException('Could not reach the list assistant.'),
    );
    await openWithList(tester, assistant: assistant);

    await ask(tester, 'add coffee');

    expect(find.textContaining('Could not reach'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Nothing was applied.
    expect(find.text('Coffee'), findsNothing);
  });

  testWidgets('a refusal offers no retry, because asking again cannot help', (
    WidgetTester tester,
  ) async {
    // The monthly ceiling being the case that matters (§8).
    final FakeAssistant assistant = FakeAssistant(
      error: const RecipeAiException(
        'Hearth has reached its monthly AI limit.',
        isRetryable: false,
      ),
    );
    await openWithList(tester, assistant: assistant);

    await ask(tester, 'add coffee');

    expect(find.textContaining('monthly AI limit'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a change that survives a rebuild is one you made', (
    WidgetTester tester,
  ) async {
    // Asked-for edits are Brendan's edits: the plan gets no vote on them.
    final FakeAssistant assistant = FakeAssistant(
      answer: answer(<ShoppingEdit>[
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      ]),
    );
    await openWithList(tester, assistant: assistant);
    await ask(tester, 'add coffee');

    // Dismiss the assistant and open the separate list-management flow.
    await tester.tapAt(const Offset(200, 40));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('More'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Manage list'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('closing the assistant while it thinks preserves the answer', (
    WidgetTester tester,
  ) async {
    final DeferredAssistant assistant = DeferredAssistant();
    await openWithList(tester, assistant: assistant);
    await ask(tester, 'add coffee');
    await tester.tapAt(const Offset(200, 40));
    await pumpFrames(tester, frames: 20);
    expect(find.widgetWithText(TextField, 'What should change?'), findsNothing);

    assistant.response.complete(
      answer(<ShoppingEdit>[
        const ShoppingEdit(kind: ShoppingEditKind.add, name: 'Coffee'),
      ], reply: 'Added coffee.'),
    );
    await pumpFrames(tester, frames: 24);

    expect(tester.takeException(), isNull);
    expect(find.text('Coffee'), findsOneWidget);
    await tester.tap(find.text('More'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Ask for a change'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('Added coffee.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await pumpFrames(tester, frames: 20);
    expect(find.text('Coffee'), findsNothing);
  });

  for (final Size size in <Size>[const Size(390, 844), const Size(320, 568)]) {
    for (final double scale in <double>[1, 3]) {
      testWidgets('the assistant remains reachable at $size and ${scale}x', (
        WidgetTester tester,
      ) async {
        final FakeAssistant assistant = FakeAssistant(
          answer: answer(const <ShoppingEdit>[]),
        );
        await pumpHearthApp(
          tester,
          size: size,
          textScale: scale,
          viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          shoppingLines: const <ShoppingLine>[
            ShoppingLine(
              key: 'coffee',
              name: 'Coffee',
              planned: [],
              isManual: true,
            ),
          ],
          shoppingAssistant: assistant,
        );
        final SweepTools tools = SweepTools(tester);
        await tools.tab('Shopping');
        await tools.reach(find.text('More'));
        await tools.reach(find.text('Ask for a change'));
        expect(find.text('Ask for a change'), findsOneWidget);
        await tools.bring(
          find.widgetWithText(TextField, 'What should change?'),
        );
        expect(tester.takeException(), isNull);
        await tools.bring(find.widgetWithText(FilledButton, 'Ask'));
        expect(
          find.widgetWithText(FilledButton, 'Ask').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(
          assistant.calls,
          0,
          reason: 'opening the assistant costs nothing',
        );
      });
    }
  }
}
