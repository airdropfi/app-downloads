import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'config.dart';
import 'policy.dart';
import 'ports.dart';
import 'status.dart';
import 'version.dart';

const _kLastCheck = 'app_update_prompt.lastCheckMs';
const _retryAfter = Duration(minutes: 30);
const _kPolicy = 'app_update_prompt.policy';
const _kDismissedVersion = 'app_update_prompt.dismissedVersion';
const _kDismissedAt = 'app_update_prompt.dismissedAtMs';

/// Decides whether to prompt, and runs the update.
///
/// - Checks on [start] and on every resume, at most once per
///   [UpdateConfig.throttle] (12 h). While the build is blocked it re-checks
///   on every resume so a relaxed `minSupportedBuild` unblocks at once.
/// - Fails open: any network or parse failure means "no prompt". A block that
///   was already fetched stays in force from the cached policy.
/// - Sends nothing but a plain GET (no ids, no body).
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({
    required this.config,
    required Future<InstalledApp> Function() installed,
    required JsonFetcher fetcher,
    required KeyValueStore store,
    required UrlOpener opener,
    PlayUpdater? play,
    DateTime Function()? clock,
    String? Function()? regionCode,
  }) : _installedLoader = installed,
       _fetcher = fetcher,
       _store = store,
       _opener = opener,
       _play = play,
       _clock = clock ?? DateTime.now,
       _region = regionCode ?? (() => null);

  final UpdateConfig config;
  final Future<InstalledApp> Function() _installedLoader;
  final JsonFetcher _fetcher;
  final KeyValueStore _store;
  final UrlOpener _opener;
  final PlayUpdater? _play;
  final DateTime Function() _clock;
  final String? Function() _region;

  UpdateStatus _status = UpdateStatus.none;
  InstalledApp? _app;
  PlayUpdateInfo? _playInfo;
  StreamSubscription<PlayInstallEvent>? _playSub;
  bool _started = false;
  bool _busy = false;
  bool _disposed = false;
  bool _dismissedNow = false;
  String? _flexibleOfferedFor;

  UpdateStatus get status => _status;
  InstalledApp? get installed => _app;

  /// The dismissible banner is visible.
  bool get showBanner =>
      _status.kind == UpdateKind.available &&
      _status.stage != UpdateStage.downloading &&
      !_dismissedNow;

  /// The blocking screen is up.
  bool get isRequired => _status.kind == UpdateKind.required;

  /// A Play flexible update is downloaded and waits for "Restart".
  bool get readyToRestart => _status.stage == UpdateStage.downloaded;

  /// Idempotent. Applies the cached policy at once (so a known-broken build is
  /// blocked offline too), then checks if the throttle allows.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      final app = await _loadApp();
      if (app.target == UpdateTarget.unsupported) return;
      _playSub = _play?.events.listen(_onPlayEvent, onError: (_) {});
      await _loadDismissal();
      final cached = await _cachedPolicy();
      if (cached != null) _apply(_statusFromPolicyOnly(cached, app));
    } catch (_) {
      return; // fail open
    }
    await check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// One check. [force] skips the throttle (tests, a "check now" button).
  Future<void> check({bool force = false}) async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final app = await _loadApp();
      if (app.target == UpdateTarget.unsupported ||
          app.target == UpdateTarget.androidOther) {
        return;
      }
      final nowMs = _clock().millisecondsSinceEpoch;
      final last = await _store.getInt(_kLastCheck);
      final due =
          last == null ||
          last > nowMs || // clock moved back
          nowMs - last >= config.throttle.inMilliseconds;
      if (!force && !due && !isRequired) return;

      final json = await _fetcher(Uri.parse(config.policyUrl));
      final UpdatePolicy policy;
      if (json != null) {
        policy = UpdatePolicy.fromJson(json, _platformKey(app.target));
        await _store.setString(_kPolicy, jsonEncode(json));
      } else {
        policy = await _cachedPolicy() ?? UpdatePolicy.empty;
      }

      if (_mustBlock(policy, app)) {
        _apply(
          UpdateStatus(
            kind: UpdateKind.required,
            latestVersion: policy.latestVersion,
            policy: policy,
            stage: _status.stage,
          ),
        );
      } else {
        _apply(await _softStatus(policy, app));
      }
      // A failed or missing policy (offline, 404 before the file exists) must
      // not turn every resume into a request: retry after 30 minutes.
      await _store.setInt(
        _kLastCheck,
        json != null
            ? nowMs
            : nowMs - (config.throttle - _retryAfter).inMilliseconds,
      );
      await _maybeStartFlexible();
    } catch (_) {
      // fail open: keep whatever status we had
    } finally {
      _busy = false;
    }
  }

  /// "Later": hides the banner for this version for [UpdateConfig.dismissFor].
  Future<void> dismiss() async {
    final now = _clock().millisecondsSinceEpoch;
    _dismissal = (_status.latestVersion ?? '', now);
    _recomputeDismissed();
    notifyListeners();
    await _store.setString(_kDismissedVersion, _dismissal.$1 ?? '');
    await _store.setInt(_kDismissedAt, now);
  }

  /// The Update button. Callers that need a parental gate run it BEFORE this.
  /// Returns false if nothing could be opened or started.
  Future<bool> performUpdate() async {
    final app = await _loadApp();
    switch (app.target) {
      case UpdateTarget.ios:
        final id = config.appStoreId;
        if (id == null) return false;
        return await _opener.open(
              Uri.parse('itms-apps://apps.apple.com/app/id$id'),
            ) ||
            await _opener.open(Uri.parse('https://apps.apple.com/app/id$id'));
      case UpdateTarget.macos:
        final macId = config.appStoreId;
        if (macId == null) return false;
        return _opener.open(Uri.parse('https://apps.apple.com/app/id$macId'));
      case UpdateTarget.androidDirect:
        final url = _status.policy.downloadUrl;
        if (url == null) return false;
        return _opener.open(Uri.parse(url));
      case UpdateTarget.androidPlay:
        return _performPlay();
      case UpdateTarget.androidOther:
      case UpdateTarget.unsupported:
        return false;
    }
  }

  /// "Restart" after a flexible download.
  Future<void> restartToUpdate() async => _play?.completeFlexible();

  Future<bool> _performPlay() async {
    final play = _play;
    if (play != null) {
      _playInfo ??= await play.check();
      final info = _playInfo;
      if (info != null && info.availability == PlayAvailability.available) {
        if (isRequired && info.immediateAllowed) {
          final r = await play.startImmediate();
          if (r == PlayStartResult.started) return true;
          if (r == PlayStartResult.declined) return false;
        } else if (info.flexibleAllowed) {
          final r = await play.startFlexible();
          if (r == PlayStartResult.started) {
            _apply(_status.copyWith(stage: UpdateStage.downloading));
            return true;
          }
          if (r == PlayStartResult.declined) return false;
        }
      }
    }
    return _openPlayListing();
  }

  Future<bool> _openPlayListing() async {
    final pkg = config.androidPackage;
    if (pkg == null) return false;
    return await _opener.open(Uri.parse('market://details?id=$pkg')) ||
        await _opener.open(
          Uri.parse('https://play.google.com/store/apps/details?id=$pkg'),
        );
  }

  /// A build is blocked only when the blocking screen has somewhere to send
  /// the user: a store page (Apple needs an id), the Play listing, or a
  /// published download link. Otherwise its only button would do nothing.
  bool _mustBlock(UpdatePolicy policy, InstalledApp app) {
    if (!isBlocked(policy, app)) return false;
    return switch (app.target) {
      UpdateTarget.ios || UpdateTarget.macos => config.appStoreId != null,
      UpdateTarget.androidDirect => policy.downloadUrl != null,
      UpdateTarget.androidPlay => true,
      _ => false,
    };
  }
  // ---- status evaluation --------------------------------------------------

  /// Status that needs no network: blocked or a direct-APK build gap.
  UpdateStatus _statusFromPolicyOnly(UpdatePolicy policy, InstalledApp app) {
    if (_mustBlock(policy, app)) {
      return UpdateStatus(
        kind: UpdateKind.required,
        latestVersion: policy.latestVersion,
        policy: policy,
      );
    }
    if (app.target == UpdateTarget.androidDirect && _policyNewer(policy, app)) {
      return UpdateStatus(
        kind: UpdateKind.available,
        latestVersion: policy.latestVersion,
        policy: policy,
      );
    }
    return UpdateStatus.none;
  }

  bool _policyNewer(UpdatePolicy policy, InstalledApp app) => isNewerRelease(
    latestVersion: policy.latestVersion,
    latestBuild: policy.latestBuild,
    installedVersion: app.version,
    installedBuild: app.build,
  );

  Future<UpdateStatus> _softStatus(
    UpdatePolicy policy,
    InstalledApp app,
  ) async {
    switch (app.target) {
      case UpdateTarget.ios:
      case UpdateTarget.macos:
        final id = config.appStoreId;
        if (id == null) return UpdateStatus.none;
        final store = await _lookupStoreVersion(id, app.target);
        if (store.reached) {
          final v = store.version;
          return v != null && isNewerVersion(v, app.version)
              ? UpdateStatus(
                kind: UpdateKind.available,
                latestVersion: v,
                policy: policy,
              )
              : UpdateStatus(policy: policy);
        }
        // Apple unreachable: the policy's own iOS/macOS section (published
        // only once that version is live) stands in.
        return policy.hasPlatformSection && _policyNewer(policy, app)
            ? UpdateStatus(
              kind: UpdateKind.available,
              latestVersion: policy.latestVersion,
              policy: policy,
            )
            : UpdateStatus(policy: policy);
      case UpdateTarget.androidDirect:
        return policy.downloadUrl != null && _policyNewer(policy, app)
            ? UpdateStatus(
              kind: UpdateKind.available,
              latestVersion: policy.latestVersion,
              policy: policy,
            )
            : UpdateStatus(policy: policy);
      case UpdateTarget.androidPlay:
        PlayUpdateInfo? info;
        try {
          info = await _play?.check();
        } catch (_) {
          info = null;
        }
        _playInfo = info;
        if (info == null) return UpdateStatus(policy: policy);
        if (info.downloaded) {
          return UpdateStatus(
            kind: UpdateKind.available,
            latestVersion: policy.latestVersion,
            policy: policy,
            stage: UpdateStage.downloaded,
          );
        }
        return info.availability == PlayAvailability.available
            ? UpdateStatus(
              kind: UpdateKind.available,
              latestVersion: policy.latestVersion,
              policy: policy,
              stage:
                  _status.stage == UpdateStage.downloading
                      ? UpdateStage.downloading
                      : UpdateStage.idle,
            )
            : UpdateStatus(policy: policy);
      case UpdateTarget.androidOther:
      case UpdateTarget.unsupported:
        return UpdateStatus.none;
    }
  }

  /// `reached` is false when Apple could not be asked; `version` is null when
  /// Apple answered but has no such listing in this storefront.
  Future<({bool reached, String? version})> _lookupStoreVersion(
    String id,
    UpdateTarget target,
  ) async {
    final country = (config.storefront ?? _region() ?? 'us').toLowerCase();
    final entity = target == UpdateTarget.macos ? '&entity=macSoftware' : '';
    final uri = Uri.parse(
      'https://itunes.apple.com/lookup?id=$id&country=$country$entity',
    );
    final json = await _fetcher(uri);
    if (json == null) return (reached: false, version: null);
    final results = json['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      final v = (results.first as Map)['version'];
      if (v is String && v.isNotEmpty) return (reached: true, version: v);
    }
    return (reached: true, version: null);
  }

  Future<void> _maybeStartFlexible() async {
    if (!config.autoStartFlexible) return;
    final app = _app;
    final play = _play;
    if (app == null || app.target != UpdateTarget.androidPlay || play == null) {
      return;
    }
    if (_status.kind != UpdateKind.available ||
        _status.stage != UpdateStage.idle ||
        _dismissedNow) {
      return;
    }
    final info = _playInfo;
    if (info == null || !info.flexibleAllowed) return;
    final offered = _status.latestVersion ?? '';
    if (_flexibleOfferedFor == offered) return; // once per version per run
    _flexibleOfferedFor = offered;
    final r = await play.startFlexible();
    if (r == PlayStartResult.started) {
      _apply(_status.copyWith(stage: UpdateStage.downloading));
    } else if (r == PlayStartResult.declined) {
      await dismiss();
    }
  }

  void _onPlayEvent(PlayInstallEvent e) {
    switch (e) {
      case PlayInstallEvent.downloading:
        _apply(_status.copyWith(stage: UpdateStage.downloading));
      case PlayInstallEvent.downloaded:
        _apply(
          UpdateStatus(
            kind: UpdateKind.available,
            latestVersion: _status.latestVersion,
            policy: _status.policy,
            stage: UpdateStage.downloaded,
          ),
        );
      case PlayInstallEvent.failed:
      case PlayInstallEvent.canceled:
        _apply(_status.copyWith(stage: UpdateStage.idle));
      case PlayInstallEvent.installed:
        break;
    }
  }

  // ---- plumbing -------------------------------------------------------------

  Future<InstalledApp> _loadApp() async => _app ??= await _installedLoader();

  Future<UpdatePolicy?> _cachedPolicy() async {
    final raw = await _store.getString(_kPolicy);
    final app = _app;
    if (raw == null || app == null) return null;
    try {
      return UpdatePolicy.fromJson(jsonDecode(raw), _platformKey(app.target));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDismissal() async {
    final v = await _store.getString(_kDismissedVersion);
    final at = await _store.getInt(_kDismissedAt);
    _dismissal = (v, at);
    _recomputeDismissed();
  }

  (String?, int?) _dismissal = (null, null);

  void _recomputeDismissed() {
    final (v, at) = _dismissal;
    _dismissedNow =
        at != null &&
        v == (_status.latestVersion ?? '') &&
        _clock().millisecondsSinceEpoch - at < config.dismissFor.inMilliseconds;
  }

  void _apply(UpdateStatus next) {
    if (_disposed) return;
    _status = next;
    // dismissal belongs to a version: a newer store version shows again
    _recomputeDismissed();
    notifyListeners();
  }

  static String _platformKey(UpdateTarget t) => switch (t) {
    UpdateTarget.ios => 'ios',
    UpdateTarget.macos => 'macos',
    _ => 'android',
  };

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playSub?.cancel());
    super.dispose();
  }
}
