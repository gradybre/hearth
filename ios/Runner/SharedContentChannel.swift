import Flutter
import UIKit

/// Hands the app whatever the share extension left behind (spec §5.3).
///
/// The extension runs in its own process — often while Hearth is not running
/// at all — so it writes into the app group container and asks iOS to open
/// Hearth. This is the other half: it drains that container and passes the
/// payload over the channel.
///
/// Draining rather than reading is the point. A payload read twice opens the
/// import screen twice for one share; a payload never cleared reopens it on
/// every launch for ever.
enum SharedContentChannel {
  /// Must match `ShareViewController.appGroup` — the two processes have
  /// nothing else in common.
  static let appGroup = "group.com.hearth.hearth"
  static let name = "hearth/shared_content"

  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePending":
        result(take())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Pushes anything waiting to a Flutter side that is already running.
  ///
  /// For the warm case: Hearth is open, a share arrives, and iOS reopens the
  /// app by URL rather than launching it.
  static func deliverPending() {
    guard let payload = take() else { return }
    channel?.invokeMethod("shared", arguments: payload)
  }

  /// Everything in the inbox, merged, with the files removed as it goes.
  private static func take() -> [String: Any]? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    ) else { return nil }

    let inbox = container.appendingPathComponent("shared", isDirectory: true)
    guard let names = try? FileManager.default.contentsOfDirectory(
      atPath: inbox.path
    ) else { return nil }

    // Named by time, taken oldest first: two shares in quick succession are
    // two payloads, and the order they were made in is the order they mean.
    let manifests = names.filter { $0.hasSuffix(".json") }.sorted()
    guard !manifests.isEmpty else { return nil }

    var url = ""
    var text = ""
    var images: [FlutterStandardTypedData] = []

    for manifest in manifests {
      let path = inbox.appendingPathComponent(manifest)
      defer { try? FileManager.default.removeItem(at: path) }

      guard let data = try? Data(contentsOf: path),
            let payload = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any]
      else { continue }

      if url.isEmpty, let shared = payload["url"] as? String, !shared.isEmpty {
        url = shared
      }
      if let shared = payload["text"] as? String, !shared.isEmpty {
        text = text.isEmpty ? shared : text + "\n\n" + shared
      }
      for name in (payload["images"] as? [String]) ?? [] {
        let file = inbox.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: file) }
        if let bytes = try? Data(contentsOf: file) {
          images.append(FlutterStandardTypedData(bytes: bytes))
        }
      }
    }

    if url.isEmpty && text.isEmpty && images.isEmpty { return nil }
    return ["url": url, "text": text, "images": images]
  }
}
