/// The wire to Home Assistant, and the one seam that fakes it
/// (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
///
/// Two types live here and the split is the point. [HaSocket] is a port: four
/// operations, no protocol, no Home Assistant. [HaSession] above it speaks the
/// protocol and knows nothing about sockets. That is what lets the whole of
/// §6.1 — the handshake, the snapshot/subscription race, the generation guard,
/// the reconnect policy — be tested at full speed with no server, no ports and
/// no flake, which is the only way the race is testable at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A duplex JSON connection. Anything that can carry maps both ways.
abstract interface class HaSocket {
  /// Frames from the server, decoded. Closes when the connection does.
  Stream<Map<String, Object?>> get incoming;

  /// Sends one frame.
  void send(Map<String, Object?> frame);

  /// Closes the connection and the [incoming] stream.
  Future<void> close();
}

/// Opens a real one.
///
/// A function rather than a class so a test can pass a closure, and so the
/// session never holds a reference to anything that knows a URL — the session's
/// job is the protocol, and a protocol that can also dial is a protocol that
/// can dial somewhere unintended.
typedef HaSocketOpener = Future<HaSocket> Function(Uri url);

/// The real connection, over `web_socket_channel`.
class WebSocketHaSocket implements HaSocket {
  WebSocketHaSocket(this._channel);

  /// Connects to [url], which must already have been validated by
  /// `HaEndpoint` — this type does no checking of its own, deliberately, so
  /// there is exactly one place in the app that decides where a credential may
  /// be sent.
  static Future<HaSocket> connect(Uri url) async {
    final WebSocketChannel channel = WebSocketChannel.connect(url);
    await channel.ready;
    return WebSocketHaSocket(channel);
  }

  final WebSocketChannel _channel;

  @override
  Stream<Map<String, Object?>> get incoming => _channel.stream
      .map((Object? frame) => frame is String ? frame : '')
      .map<Map<String, Object?>?>((String text) {
        if (text.isEmpty) return null;
        try {
          final Object? decoded = jsonDecode(text);
          return decoded is Map<String, Object?> ? decoded : null;
        } on FormatException {
          // §6.1: handle malformed messages without crashing the whole
          // screen. One unreadable frame is one dropped frame.
          return null;
        }
      })
      .where((Map<String, Object?>? frame) => frame != null)
      .cast<Map<String, Object?>>();

  @override
  void send(Map<String, Object?> frame) => _channel.sink.add(jsonEncode(frame));

  @override
  Future<void> close() => _channel.sink.close();
}
