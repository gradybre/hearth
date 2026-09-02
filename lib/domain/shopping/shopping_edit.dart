import 'package:meta/meta.dart';

import '../text/text_normaliser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'shopping_line.dart';
import 'shopping_list_builder.dart';

/// One change to the list, as asked for in words (spec §5.7).
///
/// Operations rather than a rewritten list, deliberately. A model handed the
/// whole list back would be free to drop a line by forgetting it, and a
/// shopping list that quietly loses an item is worse than one that refuses an
/// instruction — you find out about the refusal in the app and about the loss
/// in the shop.
enum ShoppingEditKind { add, remove, setAmount, setOnHand, check, uncheck }

@immutable
class ShoppingEdit {
  const ShoppingEdit({
    required this.kind,
    required this.name,
    this.amount,
    this.unitId,
    this.storeTag,
  });

  final ShoppingEditKind kind;

  /// Which line this is about, by name. Matched leniently — see [applyTo].
  final String name;

  final double? amount;
  final String? unitId;
  final String? storeTag;

  Quantity? get quantity {
    final double? value = amount;
    if (value == null) return null;
    final Unit unit =
        (unitId == null ? null : Units.byId(unitId!)) ?? Units.item;
    return Quantity.of(value, unit);
  }
}

/// Applying what was asked to the list that was on screen.
///
/// Pure, and the whole reason the chat is testable: everything about *what a
/// sentence does* is decided here rather than in a screen or a prompt.
abstract final class ShoppingEdits {
  /// [lines] with [edits] applied, in order.
  ///
  /// Unknown lines are not an error. "Remove the beef" when there is no beef
  /// simply does nothing, because the alternative — inventing a line to
  /// delete, or failing the whole batch — is worse than a sentence quietly
  /// having no effect that the reply then fails to explain.
  static List<ShoppingLine> apply(
    List<ShoppingLine> lines,
    List<ShoppingEdit> edits,
  ) {
    List<ShoppingLine> next = <ShoppingLine>[...lines];
    for (final ShoppingEdit edit in edits) {
      next = _one(next, edit);
    }
    return next;
  }

  static List<ShoppingLine> _one(List<ShoppingLine> lines, ShoppingEdit edit) {
    final int at = _find(lines, edit.name);

    if (edit.kind == ShoppingEditKind.add) {
      // Adding something already there sets its amount instead of listing it
      // twice — "add another two pounds of beef" is about the beef.
      if (at >= 0) {
        return _replace(lines, at, _withAmount(lines[at], edit));
      }
      return <ShoppingLine>[
        ...lines,
        ShoppingLine.manual(
          key: ShoppingListBuilder.keyFor(name: edit.name),
          name: edit.name,
          planned: <Quantity>[if (edit.quantity case final Quantity q) q],
          storeTag: edit.storeTag,
          sortOrder: lines.length,
        ),
      ];
    }

    if (at < 0) return lines;
    final ShoppingLine line = lines[at];

    return switch (edit.kind) {
      ShoppingEditKind.remove => <ShoppingLine>[
        for (int i = 0; i < lines.length; i++)
          if (i != at) lines[i],
      ],
      ShoppingEditKind.setAmount => _replace(
        lines,
        at,
        _withAmount(line, edit),
      ),
      ShoppingEditKind.setOnHand => _replace(
        lines,
        at,
        line.copyWith(
          onHand: edit.quantity,
          clearOnHand: edit.quantity == null,
        ),
      ),
      ShoppingEditKind.check => _replace(lines, at, line.ticked(true)),
      ShoppingEditKind.uncheck => _replace(lines, at, line.ticked(false)),
      ShoppingEditKind.add => lines,
    };
  }

  /// An amount asked for in words becomes the line's own decision, not the
  /// recipes'. A manual line has no recipe behind it, so it becomes its
  /// planned amount instead and is not marked as edited.
  static ShoppingLine _withAmount(ShoppingLine line, ShoppingEdit edit) {
    final Quantity? quantity = edit.quantity;
    if (quantity == null) return line;
    if (line.isManual && line.planned.isEmpty) {
      return line.copyWith(planned: <Quantity>[quantity]);
    }
    return line.copyWith(wanted: quantity);
  }

  static List<ShoppingLine> _replace(
    List<ShoppingLine> lines,
    int at,
    ShoppingLine line,
  ) => <ShoppingLine>[
    for (int i = 0; i < lines.length; i++)
      if (i == at) line else lines[i],
  ];

  /// Which line a name means.
  ///
  /// By key, then by name, then word by word — because the model repeats the
  /// sentence rather than quoting the list. Asked "I already have a pound of
  /// the beef", it names the line `the beef`, which shares no substring in
  /// either direction with `ground beef`; the instruction used to land on
  /// nothing and the reply still said it had been done.
  static int _find(List<ShoppingLine> lines, String name) {
    final String key = ShoppingListBuilder.keyFor(name: name);
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].key == key) return i;
    }

    final String wanted = _withoutFiller(name);
    // Nothing left to go on. "Remove that" names no line, and picking one
    // anyway is how a shopping list quietly loses an item.
    if (wanted.isEmpty) return -1;

    for (int i = 0; i < lines.length; i++) {
      final String candidate = lines[i].name.toLowerCase().trim();
      if (candidate == wanted ||
          candidate.contains(wanted) ||
          wanted.contains(candidate)) {
        return i;
      }
    }

    // Every word accounted for, plurals included — the same rule the food
    // picker uses, so "apples" finds "Honeycrisp Apple" here too.
    for (int i = 0; i < lines.length; i++) {
      if (wordCoverage(wanted, lines[i].name) == 1.0) return i;
    }
    return -1;
  }

  /// Words that carry no name, dropped before matching.
  ///
  /// Deliberately short: every word removed is a word that can no longer tell
  /// two lines apart.
  static const Set<String> _filler = <String>{
    'the',
    'a',
    'an',
    'my',
    'some',
    'that',
    'this',
    'of',
    'more',
  };

  static String _withoutFiller(String name) => <String>[
    for (final String word in name.toLowerCase().trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty && !_filler.contains(word)) word,
  ].join(' ');
}
