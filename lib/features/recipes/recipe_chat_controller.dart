import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/models/food_profile.dart';

/// One line of the conversation, as the screen shows it (spec §5.4).
@immutable
class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text, this.recipe});

  final bool fromUser;
  final String text;

  /// The recipe this reply came with, when there is one. Kept on the message
  /// rather than only as "the current recipe" so that asking for a change and
  /// disliking it leaves the earlier version still on screen to go back to.
  final AiRecipe? recipe;
}

@immutable
sealed class RecipeChatState {
  const RecipeChatState({this.messages = const <ChatMessage>[]});

  final List<ChatMessage> messages;

  /// The most recent recipe offered, which is the one "Save" means.
  AiRecipe? get latestRecipe {
    for (final ChatMessage message in messages.reversed) {
      if (message.recipe != null) return message.recipe;
    }
    return null;
  }
}

class RecipeChatIdle extends RecipeChatState {
  const RecipeChatIdle({super.messages});
}

class RecipeChatThinking extends RecipeChatState {
  const RecipeChatThinking({super.messages});
}

/// It did not work, and the conversation is untouched.
///
/// §5.4's fail-soft: "the chat and any in-progress recipe are preserved with a
/// retry — no lost work". The failed turn stays in [messages], so retrying
/// asks the same question rather than making the user type it again.
class RecipeChatFailed extends RecipeChatState {
  const RecipeChatFailed(
    this.message, {
    required this.canRetry,
    super.messages,
  });

  final String message;
  final bool canRetry;
}

/// Writing a recipe by talking about it (spec §5.4).
///
/// Private to the user (§4, §8.2) — the conversation is never a household
/// surface, even though the recipe that comes out of it is shared like any
/// other once saved.
///
/// Held in memory for now, deliberately: closing the app loses the
/// conversation and keeps the saved recipe. §4 lists the chat as a table, so
/// this is a known gap rather than an oversight.
class RecipeChatController extends Notifier<RecipeChatState> {
  @override
  RecipeChatState build() => const RecipeChatIdle();

  final List<ChatMessage> _messages = <ChatMessage>[];
  int _run = 0;

  Future<void> send(String text) async {
    final String said = text.trim();
    if (said.isEmpty) return;

    _messages.add(ChatMessage(fromUser: true, text: said));
    await _ask();
  }

  /// Asks again after a failure, without repeating the question.
  Future<void> retry() async {
    if (_messages.isEmpty) return;
    await _ask();
  }

  Future<void> _ask() async {
    final int run = ++_run;
    final RecipeAiSource? ai = ref.read(recipeAiProvider);

    if (ai == null) {
      state = RecipeChatFailed(
        'Writing a recipe needs a connection to Hearth\'s server, and this '
        'build has none configured.',
        canRetry: false,
        messages: messages,
      );
      return;
    }

    state = RecipeChatThinking(messages: messages);

    // Read rather than watched: the profile that was true when the question
    // was asked is the one the answer should honour.
    final FoodProfile profile =
        ref.read(foodProfileProvider).value ??
        FoodProfile.empty(ref.read(currentUserIdProvider));

    try {
      final AiRecipe recipe = await ai.generate(
        turns: <AiTurn>[
          for (final ChatMessage message in _messages)
            AiTurn(fromUser: message.fromUser, text: message.text),
        ],
        profile: profile.toPrompt(),
      );

      if (_run != run) return;

      _messages.add(
        ChatMessage(
          fromUser: false,
          text: recipe.reply?.trim().isNotEmpty ?? false
              ? recipe.reply!.trim()
              : 'Here is ${recipe.title}.',
          recipe: recipe,
        ),
      );
      state = RecipeChatIdle(messages: messages);
    } on RecipeAiException catch (error) {
      if (_run != run) return;
      state = RecipeChatFailed(
        error.message,
        canRetry: error.isRetryable,
        messages: messages,
      );
    } on Object {
      if (_run != run) return;
      state = RecipeChatFailed(
        'That did not go through. Nothing you have said is lost.',
        canRetry: true,
        messages: messages,
      );
    }
  }

  void reset() {
    _run++;
    _messages.clear();
    state = const RecipeChatIdle();
  }

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
}

final NotifierProvider<RecipeChatController, RecipeChatState>
recipeChatProvider = NotifierProvider<RecipeChatController, RecipeChatState>(
  RecipeChatController.new,
);
