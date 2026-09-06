import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/recipe_ai.dart';

import '../../data/adapters/shopping_assistant.dart';
import '../../data/local/shopping_store.dart';
import '../../domain/shopping/shopping_edit.dart';
import '../../domain/shopping/shopping_line.dart';

/// A line of the conversation about the list.
@immutable
class ShoppingMessage {
  const ShoppingMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

@immutable
sealed class ShoppingChatState {
  const ShoppingChatState({this.messages = const <ShoppingMessage>[]});

  final List<ShoppingMessage> messages;

  bool get isBusy => this is ShoppingChatThinking;
}

class ShoppingChatIdle extends ShoppingChatState {
  const ShoppingChatIdle({super.messages});
}

class ShoppingChatThinking extends ShoppingChatState {
  const ShoppingChatThinking({super.messages});
}

/// It did not work, and the list is untouched.
class ShoppingChatFailed extends ShoppingChatState {
  const ShoppingChatFailed(
    this.message, {
    required this.canRetry,
    super.messages,
  });

  final String message;
  final bool canRetry;
}

/// Changing the list by asking (spec §5.7).
///
/// The list is passed in on every question rather than held, because it goes
/// on changing between them — ticked in the shop, rebuilt from a new range —
/// and an answer about a stale copy would undo whatever happened in between.
/// What an undo did, and what it deliberately left alone.
class ShoppingUndo {
  const ShoppingUndo({required this.lines, required this.kept});

  final List<ShoppingLine> lines;

  /// Lines the answer had touched that somebody has changed since, so undo
  /// left them as they are. Reported rather than silently overwritten: the
  /// newer edit is the one somebody meant.
  final int kept;
}

/// One line's part in an answer, so undoing can reverse that and nothing else.
class _Change {
  const _Change({
    required this.key,
    required this.before,
    required this.after,
    required this.index,
  });

  final String key;

  /// Null when the answer added this line.
  final ShoppingLine? before;

  /// Null when the answer removed it.
  final ShoppingLine? after;

  /// Where it sat before, so putting it back returns it to its place in the
  /// shop rather than to the bottom.
  final int index;
}

/// What an answer did, and to which list.
class _Journal {
  const _Journal({
    required this.listId,
    required this.from,
    required this.to,
    required this.changes,
  });

  final String listId;
  final DateTime from;
  final DateTime to;
  final List<_Change> changes;
}

class ShoppingChatController extends Notifier<ShoppingChatState> {
  @override
  ShoppingChatState build() => const ShoppingChatIdle();

  final List<ShoppingMessage> _messages = <ShoppingMessage>[];
  int _run = 0;

  /// What the last answer changed, line by line, for [undo].
  ///
  /// One step. Applying straight to the list is what makes this quick; this is
  /// what makes it safe, and a chat that can be undone twice is a history
  /// nobody is keeping track of.
  ///
  /// A journal rather than a copy of the whole list. The copy was simpler and
  /// wrong: restoring it put back every line as it stood before the answer,
  /// so a tick made in the aisle afterwards was undone along with the answer
  /// nobody had complained about.
  _Journal? _journal;

  bool get canUndo => _journal != null;

  Future<List<ShoppingLine>?> send(
    String text,
    List<ShoppingLine> lines,
  ) async {
    final String said = text.trim();
    if (said.isEmpty) return null;

    _messages.add(ShoppingMessage(fromUser: true, text: said));
    return _ask(lines);
  }

  Future<List<ShoppingLine>?> retry(List<ShoppingLine> lines) async {
    if (_messages.isEmpty) return null;
    return _ask(lines);
  }

  /// Takes back the last answer, and only the last answer.
  ///
  /// A line the answer touched that has been changed since is left as it is
  /// and counted in [ShoppingUndo.kept]: the newer edit is the one somebody
  /// meant, and quietly reverting it would be the same fault this exists to
  /// fix, in the other direction.
  Future<ShoppingUndo?> undo() async {
    final _Journal? journal = _journal;
    _journal = null;
    if (journal == null) return null;

    final ShoppingListSnapshot? now = await ref
        .read(shoppingRepositoryProvider)
        .current();
    if (now == null || now.id != journal.listId) return null;

    final List<ShoppingLine> lines = <ShoppingLine>[...now.lines];
    int kept = 0;

    for (final _Change change in journal.changes) {
      final int at = lines.indexWhere(
        (ShoppingLine line) => line.key == change.key,
      );
      final ShoppingLine? present = at >= 0 ? lines[at] : null;

      // Changed since the answer: leave it, and say so.
      if (present != change.after) {
        kept++;
        continue;
      }

      if (change.before == null) {
        if (at >= 0) lines.removeAt(at);
      } else if (at >= 0) {
        lines[at] = change.before!;
      } else {
        lines.insert(change.index.clamp(0, lines.length), change.before!);
      }
    }

    return ShoppingUndo(lines: lines, kept: kept);
  }

  Future<List<ShoppingLine>?> _ask(List<ShoppingLine> lines) async {
    final int run = ++_run;
    final ShoppingAssistant? assistant = ref.read(shoppingAssistantProvider);

    if (assistant == null) {
      state = ShoppingChatFailed(
        'Changing the list this way needs a connection to Hearth\'s server, '
        'and this build has none configured.',
        canRetry: false,
        messages: messages,
      );
      return null;
    }

    state = ShoppingChatThinking(messages: messages);

    // Which shop this question is about, taken before it is asked.
    final ShoppingListSnapshot? asked = await ref
        .read(shoppingRepositoryProvider)
        .current();

    try {
      final ShoppingAnswer answer = await assistant.edit(
        turns: <ShoppingTurn>[
          for (final ShoppingMessage message in _messages)
            ShoppingTurn(fromUser: message.fromUser, text: message.text),
        ],
        lines: lines,
      );
      if (_run != run) return null;

      _messages.add(
        ShoppingMessage(
          fromUser: false,
          text: answer.reply?.trim().isNotEmpty ?? false
              ? answer.reply!.trim()
              : 'Done.',
        ),
      );
      // Nothing asked for means nothing to undo: an answer that changed the
      // list is the only kind worth being able to take back.
      if (answer.edits.isEmpty) {
        state = ShoppingChatIdle(messages: messages);
        return null;
      }

      // Applied to the list as it stands, not as it stood when the question
      // went out. Somebody ticks a line off in the aisle while this is
      // thinking; applying to the older copy would write over that with a
      // list that predates it.
      final ShoppingListSnapshot? now = await ref
          .read(shoppingRepositoryProvider)
          .current();

      if (asked == null ||
          now == null ||
          now.id != asked.id ||
          now.from != asked.from ||
          now.to != asked.to) {
        // A different shop: the list was rebuilt for another range, or
        // replaced. Names in the answer mean things about the old one, and
        // there is no honest way to map them onto this.
        state = ShoppingChatFailed(
          'The list changed while I was working that out, so I have left it '
          'alone. Ask again and I will use the list as it is now.',
          canRetry: true,
          messages: messages,
        );
        return null;
      }

      state = ShoppingChatIdle(messages: messages);

      final List<ShoppingLine> next = ShoppingEdits.apply(
        now.lines,
        answer.edits,
      );
      _journal = _journalOf(now, next);
      return next;
    } on RecipeAiException catch (error) {
      if (_run != run) return null;
      state = ShoppingChatFailed(
        error.message,
        canRetry: error.isRetryable,
        messages: messages,
      );
      return null;
    } on Object {
      if (_run != run) return null;
      state = ShoppingChatFailed(
        'That did not go through. Your list is untouched.',
        canRetry: true,
        messages: messages,
      );
      return null;
    }
  }

  /// What changed between [snapshot] and [after], line by line.
  static _Journal _journalOf(
    ShoppingListSnapshot snapshot,
    List<ShoppingLine> after,
  ) {
    final Map<String, ShoppingLine> was = <String, ShoppingLine>{
      for (final ShoppingLine line in snapshot.lines) line.key: line,
    };
    final Map<String, ShoppingLine> now = <String, ShoppingLine>{
      for (final ShoppingLine line in after) line.key: line,
    };

    return _Journal(
      listId: snapshot.id,
      from: snapshot.from,
      to: snapshot.to,
      changes: <_Change>[
        for (final String key in <String>{...was.keys, ...now.keys})
          if (was[key] != now[key])
            _Change(
              key: key,
              before: was[key],
              after: now[key],
              index: snapshot.lines.indexWhere(
                (ShoppingLine line) => line.key == key,
              ),
            ),
      ],
    );
  }

  void reset() {
    _run++;
    _messages.clear();
    _journal = null;
    state = const ShoppingChatIdle();
  }

  List<ShoppingMessage> get messages =>
      List<ShoppingMessage>.unmodifiable(_messages);
}

final NotifierProvider<ShoppingChatController, ShoppingChatState>
shoppingChatProvider =
    NotifierProvider<ShoppingChatController, ShoppingChatState>(
      ShoppingChatController.new,
      isAutoDispose: true,
    );
