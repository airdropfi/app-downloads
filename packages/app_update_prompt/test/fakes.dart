import 'dart:async';

import 'package:app_update_prompt/app_update_prompt.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, Object> data = {};
  @override
  Future<String?> getString(String key) async => data[key] as String?;
  @override
  Future<void> setString(String key, String value) async => data[key] = value;
  @override
  Future<int?> getInt(String key) async => data[key] as int?;
  @override
  Future<void> setInt(String key, int value) async => data[key] = value;
}

class FakeOpener implements UrlOpener {
  final List<Uri> opened = [];
  bool result = true;
  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

/// Routes by host: policy (raw.githubusercontent.com) and Apple lookup.
class FakeNet {
  Map<String, Object?>? policy = {};
  Map<String, Object?>? lookup;
  bool policyDown = false;
  bool lookupDown = false;
  final List<Uri> requests = [];

  Future<Map<String, Object?>?> fetch(Uri uri) async {
    requests.add(uri);
    if (uri.host == 'itunes.apple.com') return lookupDown ? null : lookup;
    return policyDown ? null : policy;
  }
}

class FakePlay implements PlayUpdater {
  PlayUpdateInfo? info;
  PlayStartResult flexible = PlayStartResult.started;
  PlayStartResult immediate = PlayStartResult.started;
  int flexibleCalls = 0;
  int immediateCalls = 0;
  int completeCalls = 0;
  final events$ = StreamController<PlayInstallEvent>.broadcast();

  @override
  Future<PlayUpdateInfo?> check() async => info;
  @override
  Future<PlayStartResult> startFlexible() async {
    flexibleCalls++;
    return flexible;
  }

  @override
  Future<PlayStartResult> startImmediate() async {
    immediateCalls++;
    return immediate;
  }

  @override
  Future<void> completeFlexible() async => completeCalls++;
  @override
  Stream<PlayInstallEvent> get events => events$.stream;
}

const policyUrl = 'https://example.test/app/min.json';

UpdateController makeController({
  required InstalledApp app,
  required FakeNet net,
  MemoryStore? store,
  FakeOpener? opener,
  FakePlay? play,
  DateTime Function()? clock,
  UpdateConfig? config,
}) {
  return UpdateController(
    config:
        config ?? const UpdateConfig(policyUrl: policyUrl, appStoreId: '123'),
    installed: () async => app,
    fetcher: net.fetch,
    store: store ?? MemoryStore(),
    opener: opener ?? FakeOpener(),
    play: play,
    clock: clock,
    regionCode: () => 'VN',
  );
}

const iosApp = InstalledApp(
  version: '1.0.5',
  build: 19,
  target: UpdateTarget.ios,
);
const playApp = InstalledApp(
  version: '1.0.5',
  build: 504,
  target: UpdateTarget.androidPlay,
);
const directApp = InstalledApp(
  version: '1.0.5',
  build: 504,
  target: UpdateTarget.androidDirect,
);

Map<String, Object?> storeAnswer(String version) => {
  'resultCount': 1,
  'results': [
    {'version': version},
  ],
};
