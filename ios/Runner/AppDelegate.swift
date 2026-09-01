import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The share extension opens `hearth://shared` to bring the app forward.
  ///
  /// A cold launch needs nothing here — Flutter asks for what is waiting as
  /// soon as it starts. This is the warm case, where the app is already
  /// running and iOS merely reopens it.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "hearth" {
      SharedContentChannel.deliverPending()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    SharedContentChannel.register(
      with: engineBridge.applicationRegistrar.messenger()
    )
  }
}
