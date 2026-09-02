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
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 20);
  }

  Future<void> ask(WidgetTester tester, String what) async {
    await tester.scrollUntilVisible(
      find.text('Ask for a change'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
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
    // Applying straight to the list is what makes this quick; undo is what
    // makes it safe when it guesses wrong.
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

    await tester.scrollUntilVisible(
      find.text('Build from the plan'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Coffee'), findsOneWidget);
  });
}
