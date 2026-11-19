import 'package:flutter/foundation.dart';

import 'config.dart';
import 'controller.dart';
import 'ports.dart';

/// Debug-only: a controller that shows the prompt with no store, so a
/// simulator screenshot can be taken. Pass "available" or "required".
/// Never wired in release builds (callers guard with `kDebugMode`).
UpdateController demoUpdateController(String mode, UpdateConfig config) {
  assert(kDebugMode, 'demo prompts are debug-only');
  return UpdateController(
    config: config,
    installed: () async => const InstalledApp(
      version: '1.0.5',
      build: 19,
      target: UpdateTarget.ios,
    ),
    fetcher: (uri) async => uri.host == 'itunes.apple.com'
        ? {
            'results': [
              {'version': '99.0.0'},
            ],
          }
        : {
            'latestVersion': '99.0.0',
            if (mode == 'required') 'minSupportedBuild': 9999,
          },
    store: _MemoryStore(),
    opener: _LogOpener(),
  );
}

class _MemoryStore implements KeyValueStore {
  final Map<String, Object> _d = {};
  @override
  Future<String?> getString(String key) async => _d[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _d[key] = value;
  @override
  Future<int?> getInt(String key) async => _d[key] as int?;
  @override
  Future<void> setInt(String key, int value) async => _d[key] = value;
}

class _LogOpener implements UrlOpener {
  @override
  Future<bool> open(Uri uri) async {
    debugPrint('[update demo] would open $uri');
    return true;
  }
}
