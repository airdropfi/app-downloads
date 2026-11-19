/// The seams the controller talks through. Real implementations are in
/// `adapters.dart`; tests inject fakes.
library;

/// Where the installed copy came from, which decides how it gets updated.
enum UpdateTarget {
  /// App Store (iPhone, iPad).
  ios,

  /// Mac App Store.
  macos,

  /// Installed from Google Play: Play In-App Updates.
  androidPlay,

  /// APK installed by hand: link to the downloads page.
  androidDirect,

  /// Another Android store (Samsung, Amazon, ...): never prompted.
  androidOther,

  /// Web, desktop other than macOS: never prompted.
  unsupported,
}

class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.build,
    required this.target,
  });

  /// "1.0.5".
  final String version;

  /// iOS CFBundleVersion or Android versionCode with the ABI offset already
  /// stripped; null when the platform reported something unparsable.
  final int? build;
  final UpdateTarget target;
}

/// Small persistent key-value store.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
}

/// GET a JSON object; null on ANY failure (offline, timeout, non-200, not a
/// JSON object). Callers fail open on null.
typedef JsonFetcher = Future<Map<String, Object?>?> Function(Uri uri);

abstract class UrlOpener {
  /// Opens [uri] outside the app. True if something handled it.
  Future<bool> open(Uri uri);
}

enum PlayAvailability { none, available }

class PlayUpdateInfo {
  const PlayUpdateInfo({
    required this.availability,
    this.flexibleAllowed = false,
    this.immediateAllowed = false,
    this.downloaded = false,
  });

  final PlayAvailability availability;
  final bool flexibleAllowed;
  final bool immediateAllowed;

  /// A flexible update is already downloaded and waits for a restart.
  final bool downloaded;
}

enum PlayStartResult { started, declined, failed }

enum PlayInstallEvent { downloading, downloaded, failed, canceled, installed }

/// Google Play In-App Updates.
abstract class PlayUpdater {
  /// Null when Play cannot answer (not installed from Play, no Play
  /// services, error).
  Future<PlayUpdateInfo?> check();
  Future<PlayStartResult> startFlexible();
  Future<PlayStartResult> startImmediate();
  Future<void> completeFlexible();
  Stream<PlayInstallEvent> get events;
}
