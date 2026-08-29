import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
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
  const RecipeImportState({this.images = const <PickedPhoto>[], this.url = ''});

  final List<PickedPhoto> images;
  final String url;

  bool get hasSomethingToRead => images.isNotEmpty || url.trim().isNotEmpty;
}

/// Waiting on the user — nothing chosen yet, or something chosen and not sent.
class RecipeImportIdle extends RecipeImportState {
  const RecipeImportIdle({super.images, super.url});
}

class RecipeImportReading extends RecipeImportState {
  const RecipeImportReading(this.what, {super.images, super.url});

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
  int _run = 0;

  /// Beyond this an image is not a screenshot, and the function will refuse it
  /// anyway. Caught here so the user is told before waiting on an upload.
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int maxImages = 3;

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

  Future<void> read() async {
    if (_images.isEmpty && _url.trim().isEmpty) return;

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

    state = RecipeImportReading(_describeWork(), images: images, url: _url);

    try {
      final AiRecipe recipe = await ai.extract(
        images: <AiImage>[
          for (final PickedPhoto photo in _images)
            AiImage(bytes: photo.bytes, mediaType: _mediaTypeOf(photo)),
        ],
        url: _url.trim().isEmpty ? null : _url.trim(),
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

  void reset() {
    _run++;
    _images.clear();
    _url = '';
    state = _idle();
  }

  /// A fresh instance every time, carrying the current queue.
  RecipeImportIdle _idle() => RecipeImportIdle(images: images, url: _url);

  RecipeImportFailed _failed(String message, {required bool canRetry}) =>
      RecipeImportFailed(
        message,
        canRetry: canRetry,
        images: images,
        url: _url,
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
