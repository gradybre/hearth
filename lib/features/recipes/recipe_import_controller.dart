import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../data/adapters/shared_content.dart';
import '../../domain/recipes/shared_link.dart';
import 'recipe_draft.dart';

/// What the import produced, on its way to the editor.
///
/// The draft and the doubts travel together: §5.3 wants the uncertain fields
/// pointed at on the review screen, and the review screen is the editor.
@immutable
class RecipeImportResult {
  const RecipeImportResult({
    required this.draft,
    required this.uncertain,
    this.estimates = const <AiEstimate>[],
  });

  final RecipeDraft draft;
  final List<AiUncertainty> uncertain;

  /// The model's own numbers, carried only so the match review can offer them
  /// where real data cannot be found (spec §5.4). Empty for an import.
  final List<AiEstimate> estimates;
}

/// What the import is doing, and what it has to work with (spec §5.3).
///
/// The queued pictures live *in* the state rather than beside it. They were in
/// the notifier at first, and picking a photo then changed nothing Riverpod
/// could see — `const RecipeImportIdle()` is the same instance every time, so
/// no rebuild happened and the pictures never appeared. State that the screen
/// renders belongs in the state.
@immutable
sealed class RecipeImportState {
  const RecipeImportState({
    this.images = const <PickedPhoto>[],
    this.url = '',
    this.text = '',
    this.notes = '',
  });

  final List<PickedPhoto> images;
  final String url;

  /// A recipe shared as words rather than as a page — the usual shape of an
  /// Instagram DM, where the whole thing arrives as a message.
  final String text;

  /// What the reader could not work out from the source alone (spec §5.3):
  /// which end of a range to take, that the stated yield is wrong, that half
  /// the screenshot is an advert. Instructions, not content — they override
  /// what the source appears to say.
  final String notes;

  /// Why a shared link cannot be read, when that is known before trying.
  ///
  /// Instagram and TikTok serve a login wall to anything that is not a
  /// signed-in browser, so the fetch would come back with no caption in it.
  /// Saying so up front beats spending a round trip to find out (see
  /// [SharedLink]).
  String? get linkProblem => SharedLink.of(url).unreadableBecause;

  bool get hasSomethingToRead =>
      images.isNotEmpty ||
      text.trim().isNotEmpty ||
      (url.trim().isNotEmpty && linkProblem == null);
}

/// Waiting on the user — nothing chosen yet, or something chosen and not sent.
class RecipeImportIdle extends RecipeImportState {
  const RecipeImportIdle({super.images, super.url, super.text, super.notes});
}

class RecipeImportReading extends RecipeImportState {
  const RecipeImportReading(
    this.what, {
    super.images,
    super.url,
    super.text,
    super.notes,
  });

  /// What is being read, for something honest to put on screen.
  final String what;
}

class RecipeImportDone extends RecipeImportState {
  const RecipeImportDone(this.recipe);
  final AiRecipe recipe;
}

/// It did not work, and what the user can do about it.
///
/// §5.3 requires failing soft: the chosen images and typed link are carried
/// through, so [RecipeImportController.retry] asks again without making anyone
/// re-pick.
class RecipeImportFailed extends RecipeImportState {
  const RecipeImportFailed(
    this.message, {
    required this.canRetry,
    super.images,
    super.url,
    super.text,
    // Carried through a failure like everything else: §5.3's fail-soft is
    // "nothing the user entered is lost", and a note is something they
    // entered.
    super.notes,
  });

  final String message;
  final bool canRetry;
}

/// Reading a recipe out of screenshots, a photo, or a link (spec §5.3).
///
/// The images live here and nowhere else — never written to disk, dropped as
/// soon as an extraction succeeds ("originals are discarded after successful
/// extraction"). They are kept through a *failure* on purpose, because that is
/// the whole of what fail-soft means here.
class RecipeImportController extends Notifier<RecipeImportState> {
  @override
  RecipeImportState build() => const RecipeImportIdle();

  final List<PickedPhoto> _images = <PickedPhoto>[];
  String _url = '';
  String _text = '';
  String _notes = '';
  int _run = 0;

  /// Beyond this an image is not a screenshot, and the function will refuse it
  /// anyway. Caught here so the user is told before waiting on an upload.
  static const int maxImageBytes = 5 * 1024 * 1024;

  /// A recipe spans as many screens as it spans. Three covered a short one
  /// and quietly truncated a long one — the pages past the third were simply
  /// not picked, and nothing said so.
  static const int maxImages = 10;

  Future<void> addPhotos(PhotoOrigin origin) async {
    final PhotoPicker picker = ref.read(photoPickerProvider);
    final List<PickedPhoto> picked = origin == PhotoOrigin.camera
        ? <PickedPhoto>[
            if (await picker.pick(origin) case final PickedPhoto photo) photo,
          ]
        : await picker.pickMultiple(max: maxImages - _images.length);

    if (picked.isEmpty) return;

    for (final PickedPhoto photo in picked) {
      if (_images.length >= maxImages) break;
      if (photo.bytes.lengthInBytes > maxImageBytes) {
        // Desktop pickers ignore the downscaling the mobile ones apply, so a
        // full-resolution photo can arrive intact. Better to say so than to
        // spend a minute uploading it and fail at the far end.
        state = _failed(
          'That image is too big to send. A screenshot or a photo from your '
          'phone will be fine.',
          canRetry: false,
        );
        return;
      }
      _images.add(photo);
    }

    state = _idle();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= _images.length) return;
    _images.removeAt(index);
    state = _idle();
  }

  void setUrl(String value) {
    _url = value;
    state = _idle();
  }

  void setText(String value) {
    _text = value;
    state = _idle();
  }

  void setNotes(String value) {
    _notes = value;
    state = _idle();
  }

  /// Takes what another app handed over (spec §5.3).
  ///
  /// Added to whatever is already queued rather than replacing it: sharing a
  /// second screenshot of the same recipe is the point of the ten-image
  /// limit, and a share that wiped the first one would make that impossible.
  void addShared(SharedContent content) {
    for (final Uint8List bytes in content.images) {
      if (_images.length >= maxImages) break;
      if (bytes.lengthInBytes > maxImageBytes) continue;
      _images.add(PickedPhoto(bytes: bytes, extension: _extensionOf(bytes)));
    }
    if (content.url.trim().isNotEmpty) _url = content.url.trim();
    if (content.text.trim().isNotEmpty) {
      _text = _text.trim().isEmpty
          ? content.text.trim()
          : '${_text.trim()}\n\n${content.text.trim()}';
    }
    state = _idle();
  }

  /// What the bytes are, read from their own first few bytes.
  ///
  /// A share extension hands over data, not a filename, and the media type is
  /// what the API is told — guessing jpg for a PNG makes the whole request
  /// fail at the far end for a reason nobody could see.
  static String _extensionOf(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'heic';
    }
    return 'jpg';
  }

  Future<void> read() async {
    if (!state.hasSomethingToRead) return;

    final int run = ++_run;
    final RecipeAiSource? ai = ref.read(recipeAiProvider);
    if (ai == null) {
      state = _failed(
        'Importing needs a connection to Hearth\'s server, and this build has '
        'none configured.',
        canRetry: false,
      );
      return;
    }

    state = RecipeImportReading(
      _describeWork(),
      images: images,
      url: _url,
      text: _text,
      notes: _notes,
    );

    try {
      final AiRecipe recipe = await ai.extract(
        images: <AiImage>[
          for (final PickedPhoto photo in _images)
            AiImage(bytes: photo.bytes, mediaType: _mediaTypeOf(photo)),
        ],
        url: _url.trim().isEmpty ? null : _url.trim(),
        text: _text.trim().isEmpty ? null : _text.trim(),
        notes: _notes.trim().isEmpty ? null : _notes.trim(),
      );

      if (_run != run) return;

      // The originals have done their job and are not kept (spec §5.3).
      _images.clear();
      state = RecipeImportDone(recipe);
    } on RecipeAiException catch (error) {
      if (_run != run) return;
      state = _failed(error.message, canRetry: error.isRetryable);
    } on Object {
      if (_run != run) return;
      state = _failed(
        'That did not go through. Your pictures are still here.',
        canRetry: true,
      );
    }
  }

  /// Asks again with exactly what was already chosen.
  Future<void> retry() => read();

  /// Drops the finished reading but keeps what was chosen.
  ///
  /// For backing out of the review: the pictures are still the ones you meant,
  /// and making you pick them again would be a punishment for looking.
  void clearResult() {
    _run++;
    state = _idle();
  }

  void reset() {
    _run++;
    _images.clear();
    _url = '';
    _text = '';
    _notes = '';
    state = _idle();
  }

  /// A fresh instance every time, carrying the current queue.
  RecipeImportIdle _idle() =>
      RecipeImportIdle(images: images, url: _url, text: _text, notes: _notes);

  RecipeImportFailed _failed(String message, {required bool canRetry}) =>
      RecipeImportFailed(
        message,
        canRetry: canRetry,
        images: images,
        url: _url,
        text: _text,
        notes: _notes,
      );

  /// What the user has queued up.
  List<PickedPhoto> get images => List<PickedPhoto>.unmodifiable(_images);

  String _describeWork() {
    if (_images.isEmpty) return 'that page';
    return _images.length == 1
        ? 'your picture'
        : 'your ${_images.length} pictures';
  }

  /// Claude accepts jpeg, png, gif and webp; anything else is sent as jpeg and
  /// left to fail loudly rather than be guessed at here.
  static String _mediaTypeOf(PickedPhoto photo) => switch (photo.extension) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

final NotifierProvider<RecipeImportController, RecipeImportState>
recipeImportProvider =
    NotifierProvider<RecipeImportController, RecipeImportState>(
      RecipeImportController.new,
    );
