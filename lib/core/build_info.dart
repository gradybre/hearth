/// What build this is, for the diagnostics panel (handoff §12.3).
///
/// A constant with a test holding it to `pubspec.yaml`, rather than a plugin.
/// `package_info_plus` is the usual answer and it is a platform dependency on
/// three platforms to read a string this repository already knows — and a
/// version that has to be fetched asynchronously is a version the panel shows
/// as blank on the frame somebody screenshots.
///
/// The obvious risk of a hand-copied constant is that it drifts from the real
/// one and quietly reports the wrong build, which is worse than no version at
/// all: a diagnostic that lies is a diagnostic that sends somebody looking in
/// the wrong release. So `test/architecture/build_info_test.dart` reads
/// `pubspec.yaml` and fails the suite when the two disagree. Bumping the
/// version is two lines in one commit, and forgetting the second is a red
/// suite rather than a wrong answer.
abstract final class BuildInfo {
  /// Exactly as `pubspec.yaml` spells it, `major.minor.patch+build`.
  static const String appVersion = '1.0.0+1';

  /// The local database's schema version.
  ///
  /// Worth showing beside the app version rather than instead of it: the two
  /// come apart. A build that failed to migrate is the same app on an older
  /// schema, and that is precisely the state somebody would be reporting.
  static const int schemaVersion = 26;

  /// The version an export would be written as (spec §7.4).
  ///
  /// Here because "what would I get if I exported right now" is a question
  /// about this build, and because a file's own manifest is no help to
  /// somebody deciding whether to take one.
  static const int exportFormatVersion = 2;
}
