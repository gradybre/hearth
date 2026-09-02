import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/models/food_profile.dart';
import 'ai_recipe_mapper.dart';
import 'recipe_chat_controller.dart' show ChatMessage;
import 'recipe_draft.dart';

/// Asking for a change to the recipe on screen (spec §5.4).
///
/// A separate controller from [RecipeChatController] rather than a reuse of
/// it. That one is a singleton owned by the generate screen, and the two would
/// overwrite each other's conversation: you would open the editor's chat and
/// find yesterday's "write me something with chicken" in it, or worse, revise
/// a recipe and have the answer land in the other screen.
///
/// The conversation is in memory and goes when the screen does. That is the
/// same known gap §4 records for the generate chat, and it matters less here:
/// a revision is a single question about a draft you are already looking at.
@immutable
sealed class ReviseState {
  const ReviseState({this.messages = const <ChatMessage>[]});

  final List<ChatMessage> messages;

  bool get isBusy => this is ReviseThinking;
}

class ReviseIdle extends ReviseState {
  const ReviseIdle({super.messages});
}

class ReviseThinking extends ReviseState {
  const ReviseThinking({super.messages});
}

/// It did not work, and nothing was changed.
///
/// §5.4's fail-soft, and here it is stronger than usual: a failed revision
/// must leave the draft exactly as it was, because the user is looking at it.
class ReviseFailed extends ReviseState {
  const ReviseFailed(this.message, {required this.canRetry, super.messages});

  final String message;
  final bool canRetry;
}

class RecipeReviseController extends Notifier<ReviseState> {
  @override
  ReviseState build() => const ReviseIdle();

  final List<ChatMessage> _messages = <ChatMessage>[];
  int _run = 0;

  /// The draft as it was before the last answer landed, for [undo].
  ///
  /// One step, not a stack. The chat is for a correction or two, and a full
  /// history would be a second undo system sitting beside the editor's own
  /// fields.
  RecipeDraft? _previous;

  bool get canUndo => _previous != null;

  /// Asks for a change to [current], and returns the revised draft.
  ///
  /// Returns null when nothing changed — a failure, an empty question, or no
  /// backend — so the caller can leave the fields alone. The draft is passed
  /// in on every call rather than held, because the user goes on typing
  /// between questions and the answer has to be about what is on screen.
  Future<RecipeDraft?> send(String text, RecipeDraft current) async {
    final String said = text.trim();
    if (said.isEmpty) return null;

    _messages.add(ChatMessage(fromUser: true, text: said));
    return _ask(current);
  }

  /// Asks again after a failure, without making anyone retype the question.
  Future<RecipeDraft?> retry(RecipeDraft current) async {
    if (_messages.isEmpty) return null;
    return _ask(current);
  }

  /// The draft as it was before the last answer.
  ///
  /// The revision applied straight into the fields, which is what makes it
  /// quick — so this is what makes it safe. Clears afterwards: undoing twice
  /// would be undoing something nobody remembers.
  RecipeDraft? undo() {
    final RecipeDraft? before = _previous;
    _previous = null;
    return before;
  }

  Future<RecipeDraft?> _ask(RecipeDraft current) async {
    final int run = ++_run;
    final RecipeAiSource? ai = ref.read(recipeAiProvider);

    if (ai == null) {
      state = ReviseFailed(
        'Changing a recipe this way needs a connection to Hearth\'s server, '
        'and this build has none configured.',
        canRetry: false,
        messages: messages,
      );
      return null;
    }

    state = ReviseThinking(messages: messages);

    final FoodProfile profile =
        ref.read(foodProfileProvider).value ??
        FoodProfile.empty(ref.read(currentUserIdProvider));

    try {
      final AiRecipe answer = await ai.generate(
        turns: <AiTurn>[
          for (final ChatMessage message in _messages)
            AiTurn(fromUser: message.fromUser, text: message.text),
        ],
        profile: profile.toPrompt(),
        // The draft as it stands, hand edits included — see
        // [RecipeDraft.toPrompt].
        recipe: current.toPrompt(),
      );

      // A later question already asked; this answer is about a recipe that
      // has moved on.
      if (_run != run) return null;

      _messages.add(
        ChatMessage(
          fromUser: false,
          text: answer.reply?.trim().isNotEmpty ?? false
              ? answer.reply!.trim()
              : 'Done.',
          recipe: answer,
        ),
      );
      state = ReviseIdle(messages: messages);

      _previous = current;
      return current.revisedWith(AiRecipeMapper.toDraft(answer));
    } on RecipeAiException catch (error) {
      if (_run != run) return null;
      state = ReviseFailed(
        error.message,
        canRetry: error.isRetryable,
        messages: messages,
      );
      return null;
    } on Object {
      if (_run != run) return null;
      state = ReviseFailed(
        'That did not go through. Your recipe is untouched.',
        canRetry: true,
        messages: messages,
      );
      return null;
    }
  }

  /// The month's AI budget as of the last answer, when it is worth saying.
  ///
  /// Null unless the function asked for it to be shown — the threshold lives
  /// server-side so it is in one place rather than in every screen (§3, §8.1).
  AiUsage? get warning {
    for (final ChatMessage message in _messages.reversed) {
      final AiUsage? usage = message.recipe?.usage;
      if (usage != null) return usage.warn ? usage : null;
    }
    return null;
  }

  void reset() {
    _run++;
    _messages.clear();
    _previous = null;
    state = const ReviseIdle();
  }

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
}

/// Auto-disposed: a conversation belongs to the editor that opened it, and
/// leaving it behind would show yesterday's questions on tomorrow's recipe.
final NotifierProvider<RecipeReviseController, ReviseState>
recipeReviseProvider = NotifierProvider<RecipeReviseController, ReviseState>(
  RecipeReviseController.new,
  isAutoDispose: true,
);
