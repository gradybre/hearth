import 'package:meta/meta.dart';

import '../../domain/format/quantity_format.dart';
import '../../domain/shopping/shopping_edit.dart';
import '../../domain/shopping/shopping_line.dart';

/// What was asked of the list, and what to say back.
@immutable
class ShoppingAnswer {
  const ShoppingAnswer({required this.edits, this.reply});

  final List<ShoppingEdit> edits;
  final String? reply;
}

/// Editing the shopping list by asking, behind an interface (rule 7).
///
/// Operations rather than a rewritten list — see [ShoppingEdit] for why — and
/// nothing here writes anything. It returns what to do; the screen applies it,
/// with an undo, and the list is still the review surface it always was.
abstract interface class ShoppingAssistant {
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  });
}

@immutable
class ShoppingTurn {
  const ShoppingTurn({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

/// The list as words, for handing to the model.
///
/// Grouped by store, as it reads on screen. Untagged items get **no heading**
/// rather than the screen's "Anywhere": asked to add paper towels to a list
/// written that way, the model dutifully came back with `store_tag:
/// "Anywhere"` — a shop of that name, invented out of a word Hearth uses to
/// mean the absence of one.
String shoppingListAsText(List<ShoppingLine> lines) {
  final Map<String, List<ShoppingLine>> byStore =
      <String, List<ShoppingLine>>{};
  for (final ShoppingLine line in lines) {
    byStore.putIfAbsent(line.storeTag ?? '', () => <ShoppingLine>[]).add(line);
  }

  final List<String> stores = byStore.keys.toList()
    ..sort((String a, String b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return a.compareTo(b);
    });

  final StringBuffer out = StringBuffer();
  for (final String store in stores) {
    if (store.isNotEmpty) {
      if (out.isNotEmpty) out.writeln();
      out.writeln(store);
    }
    for (final ShoppingLine line in byStore[store]!) {
      out.writeln(_describe(line));
    }
  }
  return out.toString().trimRight();
}

String _describe(ShoppingLine line) {
  final StringBuffer out = StringBuffer('- ');
  if (line.toBuy case final buy?) {
    if (!buy.isZero) out.write('${QuantityFormat.format(buy)} ');
  }
  out.write(line.name);

  final List<String> notes = <String>[
    if (line.onHand != null) 'have ${QuantityFormat.format(line.onHand!)}',
    if (line.isChecked) 'already got it',
  ];
  if (notes.isNotEmpty) out.write(' (${notes.join(', ')})');
  return out.toString();
}

/// Words Hearth uses to mean "no store", which must never come back as one.
const Set<String> _notAStore = <String>{'anywhere', 'none', 'no store', 'n/a'};

/// A store tag from an answer, or null when it is not really a shop.
String? storeTagFrom(Object? raw) {
  final String tag = '${raw ?? ''}'.trim();
  if (tag.isEmpty) return null;
  return _notAStore.contains(tag.toLowerCase()) ? null : tag;
}
