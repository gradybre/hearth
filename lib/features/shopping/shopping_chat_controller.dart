import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../data/adapters/shopping_assistant.dart';
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
class ShoppingChatController extends Notifier<ShoppingChatState> {
  @override
  ShoppingChatState build() => const ShoppingChatIdle();

  final List<ShoppingMessage> _messages = <ShoppingMessage>[];
  int _run = 0;

  /// The list as it was before the last answer, for [undo].
  ///
  /// One step. Applying straight to the list is what makes this quick; this is
  /// what makes it safe, and a chat that can be undone twice is a history
  /// nobody is keeping track of.
  List<ShoppingLine>? _previous;

  bool get canUndo => _previous != null;

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

  List<ShoppingLine>? undo() {
    final List<ShoppingLine>? before = _previous;
    _previous = null;
    return before;
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
      state = ShoppingChatIdle(messages: messages);

      // Nothing asked for means nothing to undo: an answer that changed the
      // list is the only kind worth being able to take back.
      if (answer.edits.isEmpty) return null;
      _previous = lines;
      return ShoppingEdits.apply(lines, answer.edits);
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

  void reset() {
    _run++;
    _messages.clear();
    _previous = null;
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
