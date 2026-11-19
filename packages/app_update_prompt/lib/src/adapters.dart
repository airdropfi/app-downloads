import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart' as iau;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'controller.dart';
import 'ports.dart';
import 'version.dart';

/// Real wiring: the one call an app makes.
UpdateController createUpdateController(UpdateConfig config) {
  return UpdateController(
    config: config,
    installed: loadInstalledApp,
    fetcher: httpJsonFetcher(),
    store: PrefsKeyValueStore(),
    opener: UrlLauncherOpener(),
    play:
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? InAppUpdatePlayUpdater()
            : null,
    regionCode: () => PlatformDispatcher.instance.locale.countryCode,
  );
}

const _playInstaller = 'com.android.vending';

/// Other Android stores: they update the app themselves; never prompt.
const _otherStoreInstallers = {
  'com.sec.android.app.samsungapps',
  'com.amazon.venezia',
  'com.huawei.appmarket',
  'com.xiaomi.mipicks',
  'com.xiaomi.market',
  'com.heytap.market',
  'com.oppo.market',
  'com.vivo.appstore',
};

/// Classifies an install by platform and (Android) installer package.
UpdateTarget detectTarget({
  required bool isWeb,
  required TargetPlatform platform,
  String? installerStore,
}) {
  if (isWeb) return UpdateTarget.unsupported;
  switch (platform) {
    case TargetPlatform.iOS:
      return UpdateTarget.ios;
    case TargetPlatform.macOS:
      return UpdateTarget.macos;
    case TargetPlatform.android:
      if (installerStore == _playInstaller) return UpdateTarget.androidPlay;
      if (_otherStoreInstallers.contains(installerStore)) {
        return UpdateTarget.androidOther;
      }
      return UpdateTarget.androidDirect;
    default:
      return UpdateTarget.unsupported;
  }
}

Future<InstalledApp> loadInstalledApp() async {
  final info = await PackageInfo.fromPlatform();
  final target = detectTarget(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    installerStore: info.installerStore,
  );
  var build = parseBuild(info.buildNumber);
  final android =
      target == UpdateTarget.androidPlay ||
      target == UpdateTarget.androidDirect ||
      target == UpdateTarget.androidOther;
  if (build != null && android) build = normalizeAndroidBuild(build);
  return InstalledApp(version: info.version, build: build, target: target);
}

/// Plain GET, 8 s timeout, 64 KB cap, no cookies, no body, no custom headers.
JsonFetcher httpJsonFetcher({http.Client? client}) {
  return (Uri uri) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || res.bodyBytes.length > 64 * 1024) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  };
}

class PrefsKeyValueStore implements KeyValueStore {
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async => (await _p).getString(key);
  @override
  Future<void> setString(String key, String value) async =>
      (await _p).setString(key, value);
  @override
  Future<int?> getInt(String key) async => (await _p).getInt(key);
  @override
  Future<void> setInt(String key, int value) async =>
      (await _p).setInt(key, value);
}

class UrlLauncherOpener implements UrlOpener {
  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Google Play In-App Updates through the `in_app_update` plugin.
class InAppUpdatePlayUpdater implements PlayUpdater {
  @override
  Future<PlayUpdateInfo?> check() async {
    try {
      final i = await iau.InAppUpdate.checkForUpdate();
      return PlayUpdateInfo(
        availability:
            i.updateAvailability == iau.UpdateAvailability.updateAvailable
                ? PlayAvailability.available
                : PlayAvailability.none,
        flexibleAllowed: i.flexibleUpdateAllowed,
        immediateAllowed: i.immediateUpdateAllowed,
        downloaded: i.installStatus == iau.InstallStatus.downloaded,
      );
    } catch (_) {
      return null; // not from Play, no Play services, ...
    }
  }

  PlayStartResult _map(iau.AppUpdateResult r) => switch (r) {
    iau.AppUpdateResult.success => PlayStartResult.started,
    iau.AppUpdateResult.userDeniedUpdate => PlayStartResult.declined,
    iau.AppUpdateResult.inAppUpdateFailed => PlayStartResult.failed,
  };

  @override
  Future<PlayStartResult> startFlexible() async {
    try {
      return _map(await iau.InAppUpdate.startFlexibleUpdate());
    } catch (_) {
      return PlayStartResult.failed;
    }
  }

  @override
  Future<PlayStartResult> startImmediate() async {
    try {
      return _map(await iau.InAppUpdate.performImmediateUpdate());
    } catch (_) {
      return PlayStartResult.failed;
    }
  }

  @override
  Future<void> completeFlexible() async {
    try {
      await iau.InAppUpdate.completeFlexibleUpdate();
    } catch (_) {}
  }

  @override
  Stream<PlayInstallEvent> get events =>
      iau.InAppUpdate.installUpdateListener.map(
        (s) => switch (s) {
          iau.InstallStatus.downloading => PlayInstallEvent.downloading,
          iau.InstallStatus.downloaded => PlayInstallEvent.downloaded,
          iau.InstallStatus.failed => PlayInstallEvent.failed,
          iau.InstallStatus.canceled => PlayInstallEvent.canceled,
          iau.InstallStatus.installed => PlayInstallEvent.installed,
          _ => PlayInstallEvent.downloading,
        },
      );
}
