/// The tiny server-controlled JSON (`<app>/min.json`).
///
/// ```json
/// {
///   "latestVersion": "1.0.5", "latestBuild": 504, "minSupportedBuild": 0,
///   "message_en": "...", "message_vi": "...",
///   "downloadUrl": "https://github.com/airdropfi/app-downloads/releases/...",
///   "ios": {"latestVersion": "1.0.5", "latestBuild": 19}
/// }
/// ```
///
/// A platform section (`ios`, `macos`, `android`) overrides the top-level
/// fields, because iOS and Android build numbers differ.
library;

class UpdatePolicy {
  const UpdatePolicy({
    this.latestVersion,
    this.latestBuild,
    this.minSupportedBuild = 0,
    this.messageEn,
    this.messageVi,
    this.downloadUrl,
    this.hasPlatformSection = false,
  });

  final String? latestVersion;
  final int? latestBuild;

  /// Builds strictly below this are blocked. 0 (default) blocks nothing.
  final int minSupportedBuild;
  final String? messageEn;
  final String? messageVi;

  /// Direct-APK landing page (non-Play Android installs only).
  final String? downloadUrl;

  /// The platform's own section (`ios`, `macos`, `android`) publishes its own
  /// latest version or build. Apple builds only trust the file's "latest" when
  /// this is true, because a top-level version is the Android one (a section
  /// that only sets `minSupportedBuild` does not count).
  final bool hasPlatformSection;

  static const empty = UpdatePolicy();

  /// Never throws: a malformed document yields [empty] (fail-open).
  factory UpdatePolicy.fromJson(Object? json, String platformKey) {
    if (json is! Map) return empty;
    final merged = <String, Object?>{};
    for (final e in json.entries) {
      if (e.key is String) merged[e.key as String] = e.value;
    }
    final section = merged[platformKey];
    if (section is Map) {
      for (final e in section.entries) {
        if (e.key is String) merged[e.key as String] = e.value;
      }
    }
    return UpdatePolicy(
      latestVersion: _str(merged['latestVersion']),
      latestBuild: _int(merged['latestBuild']),
      minSupportedBuild: _int(merged['minSupportedBuild']) ?? 0,
      messageEn: _str(merged['message_en']),
      messageVi: _str(merged['message_vi']),
      downloadUrl: _str(merged['downloadUrl']),
      hasPlatformSection:
          section is Map &&
          (section.containsKey('latestVersion') ||
              section.containsKey('latestBuild')),
    );
  }

  /// The server message for [languageCode]; only en and vi are authored on
  /// the server, other languages use the built-in copy (null here).
  String? messageFor(String languageCode) {
    if (languageCode == 'vi') return messageVi ?? messageEn;
    if (languageCode == 'en') return messageEn;
    return null;
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
