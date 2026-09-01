import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

/// Takes a share from any app and hands it to Hearth (spec §5.3).
///
/// This runs in its own process, usually while Hearth itself is not running,
/// so it cannot pass anything over directly. It writes the payload into the
/// app group container both processes can see, then asks iOS to open Hearth,
/// which drains it on the way in.
///
/// There is no UI on purpose. Everything shared here is reviewed in the app
/// before it is saved (CLAUDE.md rule 4), and a second confirmation sheet in
/// front of that would be a step that decides nothing.
class ShareViewController: UIViewController {
  /// Shared with the app. Must match `AppGroup.identifier` in the Runner
  /// target — the two processes have nothing else in common.
  private static let appGroup = "group.com.hearth.hearth"

  /// The same cap the photo import applies: a recipe spans as many screens as
  /// it spans, and ten covers a long one.
  private static let maxImages = 10

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { await collect() }
  }

  private func collect() async {
    var urlString = ""
    var text = ""
    var images: [Data] = []

    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          if let url: URL = await load(provider, UTType.url.identifier) {
            // A file URL here is a shared image that arrived by reference
            // rather than a link to a page.
            if url.isFileURL {
              if images.count < Self.maxImages,
                 let data = try? Data(contentsOf: url) {
                images.append(data)
              }
            } else if urlString.isEmpty {
              urlString = url.absoluteString
            }
          }
        } else if provider.hasItemConformingToTypeIdentifier(
          UTType.image.identifier
        ) {
          if images.count < Self.maxImages, let data = await imageData(provider) {
            images.append(data)
          }
        } else if provider.hasItemConformingToTypeIdentifier(
          UTType.plainText.identifier
        ) {
          if let shared: String = await load(provider, UTType.plainText.identifier) {
            text = text.isEmpty ? shared : text + "\n\n" + shared
          }
        }
      }
    }

    write(urlString: urlString, text: text, images: images)
    openHost()
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func load<T>(_ provider: NSItemProvider, _ type: String) async -> T? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
        continuation.resume(returning: value as? T)
      }
    }
  }

  /// Image attachments arrive as a URL, a UIImage, or raw Data depending on
  /// which app is sharing. Asking for all three is cheaper than guessing.
  private func imageData(_ provider: NSItemProvider) async -> Data? {
    if let data: Data = await load(provider, UTType.image.identifier) {
      return data
    }
    if let url: URL = await load(provider, UTType.image.identifier) {
      return try? Data(contentsOf: url)
    }
    if let image: UIImage = await load(provider, UTType.image.identifier) {
      return image.pngData()
    }
    return nil
  }

  /// Writes the payload where the app can find it.
  ///
  /// Each share gets its own file, so two in quick succession do not overwrite
  /// each other — the app takes them oldest first and deletes as it goes.
  private func write(urlString: String, text: String, images: [Data]) {
    guard !urlString.isEmpty || !text.isEmpty || !images.isEmpty,
          let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroup
          )
    else { return }

    let inbox = container.appendingPathComponent("shared", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: inbox, withIntermediateDirectories: true
    )

    var names: [String] = []
    for (index, data) in images.enumerated() {
      let name = "\(UUID().uuidString)-\(index).img"
      try? data.write(to: inbox.appendingPathComponent(name))
      names.append(name)
    }

    let payload: [String: Any] = [
      "url": urlString, "text": text, "images": names,
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload)
    else { return }
    // Written last, and named by time: the app looks for these, so a payload
    // is never seen before the images it refers to are on disk.
    try? json.write(
      to: inbox.appendingPathComponent(
        "\(Date().timeIntervalSince1970)-\(UUID().uuidString).json"
      )
    )
  }

  /// Brings Hearth forward so the share lands somewhere visible.
  ///
  /// An extension has no `UIApplication` of its own, so this walks the
  /// responder chain for one. Long-standing and widely used, but not formally
  /// sanctioned — and deliberately not load-bearing: if it stops working the
  /// payload is still on disk and is picked up the next time Hearth opens.
  private func openHost() {
    guard let url = URL(string: "hearth://shared") else { return }
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return
      }
      responder = current.next
    }
  }
}
