import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'shared_content.dart';

/// What the iOS share extension left in the app group container.
///
/// The extension runs in its own process, often while Hearth is not running at
/// all, so it cannot hand anything over directly. It writes the payload into
/// the container both processes can see and asks iOS to open Hearth; this
/// drains the container on the way in and whenever the app is reopened.
///
/// Draining rather than reading is the point: a payload picked up twice would
/// open the import screen twice for one share, and a payload never cleared
/// would reopen it on every launch for ever.
class PlatformSharedContent implements SharedContentSource {
  PlatformSharedContent({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handle);
  }

  static const String channelName = 'hearth/shared_content';

  /// Whether this platform has a share sheet Hearth is part of.
  ///
  /// Only iOS does. Everywhere else the honest answer is that nothing will
  /// ever arrive, and saying so beats a channel that silently never fires.
  static bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  final MethodChannel _channel;
  final StreamController<SharedContent> _incoming =
      StreamController<SharedContent>.broadcast();

  @override
  Stream<SharedContent> get incoming => _incoming.stream;

  @override
  Future<SharedContent?> pending() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('takePending');
      return _parse(raw);
    } on Object {
      // A channel that is not there is not an error worth surfacing: it means
      // nothing was shared, which is the ordinary case.
      return null;
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'shared') return null;
    final SharedContent? content = _parse(call.arguments);
    if (content != null) _incoming.add(content);
    return null;
  }

  static SharedContent? _parse(Object? raw) {
    if (raw is! Map) return null;

    final Object? images = raw['images'];
    final SharedContent content = SharedContent(
      images: <Uint8List>[
        if (images is List)
          for (final Object? image in images)
            if (image is Uint8List)
              image
            else if (image is List<int>)
              Uint8List.fromList(image)
            else if (image is String)
              // Base64 is the fallback when the channel codec flattens the
              // bytes; cheaper to accept both than to depend on which.
              Uint8List.fromList(base64Decode(image)),
      ],
      url: '${raw['url'] ?? ''}',
      text: '${raw['text'] ?? ''}',
    );
    return content.isEmpty ? null : content;
  }
}

/// The implementation for platforms with no share sheet to speak of.
///
/// A real object rather than a null provider, so nothing above has to ask
/// which platform it is on before listening.
class NoSharedContent implements SharedContentSource {
  const NoSharedContent();

  @override
  Stream<SharedContent> get incoming => const Stream<SharedContent>.empty();

  @override
  Future<SharedContent?> pending() async => null;
}
