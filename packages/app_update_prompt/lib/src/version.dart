/// Version and build comparison for the update prompt.
///
/// Pure functions, no platform access, so they are cheap to test.
library;

/// Splits "1.0.5", "v1.0.5+19" or "1.0.5-beta" into its numeric parts.
/// Anything that is not a number counts as 0, so a bad string never throws.
List<int> versionParts(String version) {
  var v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final cut = v.indexOf(RegExp(r'[+\-]'));
  if (cut >= 0) v = v.substring(0, cut);
  if (v.isEmpty) return const [0];
  return v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
}

/// Negative if [a] < [b], 0 if equal, positive if [a] > [b]. Missing parts
/// count as 0, so "1.0" == "1.0.0".
int compareVersions(String a, String b) {
  final pa = versionParts(a);
  final pb = versionParts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// True when [store] is a strictly newer version name than [installed].
bool isNewerVersion(String store, String installed) =>
    compareVersions(store, installed) > 0;

/// True when a release ([latestVersion], [latestBuild]) is newer than the
/// installed one. The version name decides; on the same version name the
/// build number decides (only when both are known).
bool isNewerRelease({
  required String? latestVersion,
  required int? latestBuild,
  required String installedVersion,
  required int? installedBuild,
}) {
  if (latestVersion != null && latestVersion.isNotEmpty) {
    final c = compareVersions(latestVersion, installedVersion);
    if (c != 0) return c > 0;
  }
  if (latestBuild != null && installedBuild != null) {
    return latestBuild > installedBuild;
  }
  return false;
}

/// Flutter builds one APK per ABI with versionCode = abiOffset + build
/// (armeabi-v7a +1000, arm64-v8a +2000, x86_64 +4000), so the installed
/// build reads 2504 for build 504. Strip the offset. Build numbers must stay
/// below 1000 (the published numbers are the universal APK's versionCode).
int normalizeAndroidBuild(int versionCode) =>
    versionCode >= 1000 ? versionCode % 1000 : versionCode;

/// Parses the build number the platform reports ("19", "" or garbage).
int? parseBuild(String? raw) => int.tryParse((raw ?? '').trim());
