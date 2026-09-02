import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_shopping_assistant.dart';
import 'package:hearth/data/adapters/shopping_assistant.dart';
import 'package:hearth/domain/shopping/shopping_edit.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// The seam between the model's answer and the list (spec §5.7, §9.4).
void main() {
  ShoppingLine beef() => ShoppingLine(
    key: 'ground-beef',
    name: 'ground beef',
    planned: <Quantity>[Quantity.of(2, Units.pound)],
    sortOrder: 0,
  );

  group('the list as words', () {
    test('untagged items get no heading', () {
      // The screen calls them "Anywhere"; the model, told that, invented a
      // shop of that name and tagged new items with it.
      final String text = shoppingListAsText(<ShoppingLine>[beef()]);

      expect(text, isNot(contains('Anywhere')));
      expect(text, contains('- 2 lb ground beef'));
    });

    test('a store tag becomes a heading', () {
      final String text = shoppingListAsText(<ShoppingLine>[
        beef().copyWith(storeTag: 'Costco'),
      ]);

      expect(text, startsWith('Costco\n'));
    });

    test('what you already have goes with the line', () {
      // Otherwise "I have a pound" gets answered twice.
      final String text = shoppingListAsText(<ShoppingLine>[
        beef().copyWith(onHand: Quantity.of(1, Units.pound)),
      ]);

      expect(text, contains('1 lb ground beef (have 1 lb)'));
    });

    test('and so does a tick', () {
      final String text = shoppingListAsText(<ShoppingLine>[
        beef().ticked(true),
      ]);

      expect(text, contains('already got it'));
    });
  });

  group('store tags coming back', () {
    test('a real shop is kept', () => expect(storeTagFrom('Costco'), 'Costco'));

    test('Hearth\'s word for "no shop" is not one', () {
      // Measured behaviour, not a hypothetical: a live call came back with
      // store_tag "Anywhere" after being shown a list written that way.
      for (final String word in <String>[
        'Anywhere',
        'anywhere',
        'none',
        'N/A',
      ]) {
        expect(storeTagFrom(word), isNull, reason: word);
      }
    });

    test('and neither is empty or missing', () {
      expect(storeTagFrom(''), isNull);
      expect(storeTagFrom(null), isNull);
    });
  });

  group('reading the answer', () {
    ShoppingAnswer parse(Map<String, Object?> json) =>
        EdgeFunctionShoppingAssistant.answerFrom(json);

    test('every operation the function can send', () {
      final ShoppingAnswer answer = parse(<String, Object?>{
        'reply': 'Done.',
        'operations': <Object?>[
          <String, Object?>{'op': 'add', 'name': 'Coffee'},
          <String, Object?>{'op': 'remove', 'name': 'kale'},
          <String, Object?>{
            'op': 'set_amount',
            'name': 'ground beef',
            'amount': 2,
            'unit': 'lb',
          },
          <String, Object?>{
            'op': 'set_on_hand',
            'name': 'ground beef',
            'amount': 1,
            'unit': 'lb',
          },
          <String, Object?>{'op': 'check', 'name': 'milk'},
          <String, Object?>{'op': 'uncheck', 'name': 'milk'},
        ],
      });

      expect(answer.reply, 'Done.');
      expect(answer.edits.map((ShoppingEdit e) => e.kind), <ShoppingEditKind>[
        ShoppingEditKind.add,
        ShoppingEditKind.remove,
        ShoppingEditKind.setAmount,
        ShoppingEditKind.setOnHand,
        ShoppingEditKind.check,
        ShoppingEditKind.uncheck,
      ]);
      expect(answer.edits[2].quantity, Quantity.of(2, Units.pound));
    });

    test('an operation Hearth does not know is dropped, not fatal', () {
      // The rest of a good answer is worth more than the whole of it is worth
      // refusing over one line.
      final ShoppingAnswer answer = parse(<String, Object?>{
        'operations': <Object?>[
          <String, Object?>{'op': 'reorder', 'name': 'milk'},
          <String, Object?>{'op': 'add', 'name': 'Coffee'},
        ],
      });

      expect(answer.edits, hasLength(1));
      expect(answer.edits.single.name, 'Coffee');
    });

    test('a nameless operation is dropped', () {
      // Nothing to apply it to.
      final ShoppingAnswer answer = parse(<String, Object?>{
        'operations': <Object?>[
          <String, Object?>{'op': 'remove', 'name': '  '},
        ],
      });

      expect(answer.edits, isEmpty);
    });

    test('no operations at all is an answer, not a failure', () {
      // "What is on the list?" is a fair question about a shopping list.
      final ShoppingAnswer answer = parse(<String, Object?>{
        'reply': 'Beef and coffee.',
      });

      expect(answer.edits, isEmpty);
      expect(answer.reply, 'Beef and coffee.');
    });

    test('"Anywhere" coming back does not become a store', () {
      final ShoppingAnswer answer = parse(<String, Object?>{
        'operations': <Object?>[
          <String, Object?>{
            'op': 'add',
            'name': 'Coffee',
            'store_tag': 'Anywhere',
          },
        ],
      });

      expect(answer.edits.single.storeTag, isNull);
    });
  });
}
