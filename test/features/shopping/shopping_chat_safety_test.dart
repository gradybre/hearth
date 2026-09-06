import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/shopping_assistant.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/shopping_edit.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/features/shopping/shopping_chat_controller.dart';

/// Asking for a change must not undo one you made while it was thinking
/// (spec §5.7, R10).
///
/// The answer used to be applied to the list *as it was when the request went
/// out*, and the result replaced the whole list. Anything done in between — a
/// line ticked in the aisle, an amount corrected, your partner's change
/// arriving — was written over by a list that predated it. Undo then restored
/// that same stale snapshot, so it lost the newer work a second time.
void main() {
  late HearthDatabase db;
  late _ScriptedAssistant assistant;
  late ProviderContainer container;

  ShoppingLine line(String name, {bool checked = false, int sortOrder = 0}) =>
      ShoppingLine.manual(
        key: name,
        name: name,
        sortOrder: sortOrder,
      ).copyWith(checked: checked);

  Future<void> seed(List<ShoppingLine> lines) =>
      container.read(shoppingRepositoryProvider).replace(lines);

  Future<List<ShoppingLine>> stored() async =>
      (await container.read(shoppingRepositoryProvider).current())!.lines;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    assistant = _ScriptedAssistant();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentHouseholdIdProvider.overrideWithValue('house-1'),
        shoppingAssistantProvider.overrideWithValue(assistant),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('a line ticked while it was thinking stays ticked', () async {
    await seed(<ShoppingLine>[line('milk'), line('bread')]);
    final List<ShoppingLine> asAsked = await stored();

    // The answer is in flight. Meanwhile the shopper ticks the bread off.
    assistant.onEdit = () async {
      await seed(<ShoppingLine>[
        for (final ShoppingLine l in await stored())
          if (l.key == 'bread') l.copyWith(checked: true) else l,
      ]);
    };
    assistant.reply = const ShoppingAnswer(
      reply: 'Added eggs.',
      edits: <ShoppingEdit>[
        ShoppingEdit(kind: ShoppingEditKind.add, name: 'eggs'),
      ],
    );

    final List<ShoppingLine>? next = await container
        .read(shoppingChatProvider.notifier)
        .send('add eggs', asAsked);

    expect(next, isNotNull);
    final ShoppingLine bread = next!.firstWhere((l) => l.key == 'bread');
    expect(
      bread.checked,
      isTrue,
      reason: 'the answer was applied to a list from before the tick',
    );
    expect(next.any((l) => l.key == 'eggs'), isTrue);
  });

  test('undo takes back the answer, not everything since', () async {
    await seed(<ShoppingLine>[line('milk'), line('bread')]);
    final List<ShoppingLine> asAsked = await stored();

    assistant.reply = const ShoppingAnswer(
      reply: 'Added eggs.',
      edits: <ShoppingEdit>[
        ShoppingEdit(kind: ShoppingEditKind.add, name: 'eggs'),
      ],
    );
    final List<ShoppingLine>? applied = await container
        .read(shoppingChatProvider.notifier)
        .send('add eggs', asAsked);
    await container.read(shoppingRepositoryProvider).replace(applied!);

    // Afterwards, the shopper ticks the milk off.
    await seed(<ShoppingLine>[
      for (final ShoppingLine l in await stored())
        if (l.key == 'milk') l.copyWith(checked: true) else l,
    ]);

    final ShoppingUndo? undone = await container
        .read(shoppingChatProvider.notifier)
        .undo();

    expect(undone, isNotNull);
    expect(
      undone!.lines.any((l) => l.key == 'eggs'),
      isFalse,
      reason: 'undo did not take back what the answer added',
    );
    expect(
      undone.lines.firstWhere((l) => l.key == 'milk').checked,
      isTrue,
      reason: 'undo restored a snapshot from before the tick',
    );
  });

  test('and keeps a newer change to the very line it touched', () async {
    await seed(<ShoppingLine>[line('milk')]);
    final List<ShoppingLine> asAsked = await stored();

    assistant.reply = const ShoppingAnswer(
      reply: 'Removed the milk.',
      edits: <ShoppingEdit>[
        ShoppingEdit(kind: ShoppingEditKind.remove, name: 'milk'),
      ],
    );
    final List<ShoppingLine>? applied = await container
        .read(shoppingChatProvider.notifier)
        .send('remove the milk', asAsked);
    await container.read(shoppingRepositoryProvider).replace(applied!);

    // The shopper adds milk back by hand, differently.
    await seed(<ShoppingLine>[
      ...await stored(),
      line('milk').copyWith(checked: true),
    ]);

    final ShoppingUndo? undone = await container
        .read(shoppingChatProvider.notifier)
        .undo();

    expect(undone, isNotNull);
    expect(
      undone!.lines.where((l) => l.key == 'milk'),
      hasLength(1),
      reason: 'undo put back a line the shopper had already re-added',
    );
    expect(undone.lines.single.checked, isTrue);
    expect(undone.kept, 1, reason: 'the newer change was not reported');
  });

  test(
    'an answer for a list that has since been rebuilt does nothing',
    () async {
      await seed(<ShoppingLine>[line('milk')]);
      final List<ShoppingLine> asAsked = await stored();

      // The range is rebuilt while the answer is in flight, which makes a new
      // list: applying to it would move lines between two different shops.
      assistant.onEdit = () async {
        await container
            .read(shoppingRepositoryProvider)
            .rebuild(
              from: DateTime(2026, 10, 1),
              to: DateTime(2026, 10, 7),
              entriesByDay: const <DateTime, List<MealPlanEntry>>{},
              recipes: const <String, Recipe>{},
              foods: const <String, Food>{},
            );
      };
      assistant.reply = const ShoppingAnswer(
        reply: 'Added eggs.',
        edits: <ShoppingEdit>[
          ShoppingEdit(kind: ShoppingEditKind.add, name: 'eggs'),
        ],
      );

      final List<ShoppingLine>? next = await container
          .read(shoppingChatProvider.notifier)
          .send('add eggs', asAsked);

      expect(next, isNull);
    },
  );
}

class _ScriptedAssistant implements ShoppingAssistant {
  ShoppingAnswer reply = const ShoppingAnswer(
    reply: 'Done.',
    edits: <ShoppingEdit>[],
  );
  Future<void> Function()? onEdit;

  @override
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  }) async {
    await onEdit?.call();
    return reply;
  }
}
