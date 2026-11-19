import 'package:app_update_prompt/app_update_prompt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Apple: store lookup', () {
    test(
      'prompts only when the store version is newer than installed',
      () async {
        final net = FakeNet()..lookup = storeAnswer('1.0.6');
        final c = makeController(app: iosApp, net: net);
        await c.check(force: true);
        expect(c.status.kind, UpdateKind.available);
        expect(c.status.latestVersion, '1.0.6');
        expect(c.showBanner, isTrue);
      },
    );

    test(
      'lookup lag: store not newer yet means no prompt even if the policy says so',
      () async {
        final net =
            FakeNet()
              ..lookup = storeAnswer('1.0.5')
              ..policy = {'latestVersion': '1.0.6', 'latestBuild': 20};
        final c = makeController(app: iosApp, net: net);
        await c.check(force: true);
        expect(c.status.kind, UpdateKind.none);
      },
    );

    test('same version, older store, empty results: no prompt', () async {
      final net = FakeNet()..lookup = {'resultCount': 0, 'results': []};
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('sends no personal data: country only, plain GET', () async {
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      final u = net.requests.firstWhere((r) => r.host == 'itunes.apple.com');
      expect(u.path, '/lookup');
      expect(u.queryParameters, {'id': '123', 'country': 'vn'});
    });

    test('macOS asks for macSoftware', () async {
      final net = FakeNet()..lookup = storeAnswer('1.0.6');
      final c = makeController(
        app: const InstalledApp(
          version: '1.0.5',
          build: 5,
          target: UpdateTarget.macos,
        ),
        net: net,
      );
      await c.check(force: true);
      expect(
        net.requests
            .firstWhere((r) => r.host == 'itunes.apple.com')
            .queryParameters['entity'],
        'macSoftware',
      );
      expect(c.status.kind, UpdateKind.available);
    });

    test('Apple unreachable: the live-published policy stands in', () async {
      final net =
          FakeNet()
            ..lookupDown = true
            ..policy = {
              'latestVersion': '1.0.6',
              'ios': {'latestBuild': 20},
            };
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.available);
    });

    test(
      'Apple unreachable and no iOS section: the Android numbers are not trusted',
      () async {
        final net =
            FakeNet()
              ..lookupDown = true
              ..policy = {'latestVersion': '1.0.6', 'latestBuild': 505};
        final c = makeController(app: iosApp, net: net);
        await c.check(force: true);
        expect(c.status.kind, UpdateKind.none);
      },
    );

    test('no App Store id: never prompts', () async {
      final net = FakeNet()..lookup = storeAnswer('9.9.9');
      final c = makeController(
        app: iosApp,
        net: net,
        config: const UpdateConfig(policyUrl: policyUrl),
      );
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('Update opens the App Store product page', () async {
      final net = FakeNet()..lookup = storeAnswer('1.0.6');
      final opener = FakeOpener();
      final c = makeController(app: iosApp, net: net, opener: opener);
      await c.check(force: true);
      expect(await c.performUpdate(), isTrue);
      expect(
        opener.opened.single.toString(),
        'itms-apps://apps.apple.com/app/id123',
      );
    });

    test('itms-apps refused: falls back to the https product page', () async {
      final opener = FakeOpener()..result = false;
      final c = makeController(app: iosApp, net: FakeNet(), opener: opener);
      await c.performUpdate();
      expect(opener.opened.map((u) => u.scheme), ['itms-apps', 'https']);
    });
  });

  group('throttle', () {
    test('a second check inside 12 h does not touch the network', () async {
      var now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net, clock: () => now);
      await c.check();
      final first = net.requests.length;
      expect(first, 2); // policy + lookup
      now = now.add(const Duration(hours: 11, minutes: 59));
      await c.check();
      expect(net.requests.length, first);
      now = now.add(const Duration(minutes: 2));
      await c.check();
      expect(net.requests.length, first * 2);
    });

    test('the throttle survives a restart (stored)', () async {
      final store = MemoryStore();
      final now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      await makeController(
        app: iosApp,
        net: net,
        store: store,
        clock: () => now,
      ).check();
      final n = net.requests.length;
      await makeController(
        app: iosApp,
        net: net,
        store: store,
        clock: () => now,
      ).check();
      expect(net.requests.length, n);
    });

    test(
      'a failed fetch is retried after 30 minutes, not on every resume',
      () async {
        var now = DateTime(2026, 11, 19, 8);
        final net =
            FakeNet()
              ..policyDown = true
              ..lookupDown = true;
        final c = makeController(app: iosApp, net: net, clock: () => now);
        await c.check();
        final n = net.requests.length;
        net.policyDown = false;
        net.lookupDown = false;
        net.lookup = storeAnswer('1.0.6');
        now = now.add(const Duration(minutes: 10));
        await c.check();
        expect(net.requests.length, n, reason: 'inside the 30 minute backoff');
        now = now.add(const Duration(minutes: 21));
        await c.check();
        expect(c.status.kind, UpdateKind.available);
      },
    );

    test('force skips the throttle', () async {
      final now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net, clock: () => now);
      await c.check();
      final n = net.requests.length;
      await c.check(force: true);
      expect(net.requests.length, n * 2);
    });

    test('a clock moved back counts as due', () async {
      var now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net, clock: () => now);
      await c.check();
      final n = net.requests.length;
      now = now.subtract(const Duration(days: 2));
      await c.check();
      expect(net.requests.length, n * 2);
    });

    test('resume triggers a check (throttled)', () async {
      var now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net, clock: () => now);
      await c.start();
      final n = net.requests.length;
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(net.requests.length, n); // inside 12 h
      now = now.add(const Duration(hours: 13));
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(net.requests.length, n * 2);
      c.dispose();
    });
  });

  group('fail-open', () {
    test('everything down: no prompt, no throw', () async {
      final net =
          FakeNet()
            ..policyDown = true
            ..lookupDown = true;
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
      expect(c.showBanner, isFalse);
    });

    test('a fetcher that throws is fail-open', () async {
      final c = UpdateController(
        config: const UpdateConfig(policyUrl: policyUrl, appStoreId: '1'),
        installed: () async => iosApp,
        fetcher: (_) async => throw StateError('boom'),
        store: MemoryStore(),
        opener: FakeOpener(),
      );
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('a broken policy document never blocks', () async {
      final net =
          FakeNet()
            ..policy = {'minSupportedBuild': 'banana', 'latestBuild': []}
            ..lookup = storeAnswer('1.0.5');
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.isRequired, isFalse);
    });

    test('a build the platform cannot read is never blocked', () async {
      final net = FakeNet()..policy = {'minSupportedBuild': 999};
      final c = makeController(
        app: const InstalledApp(
          version: '1.0.5',
          build: null,
          target: UpdateTarget.ios,
        ),
        net: net,
      );
      await c.check(force: true);
      expect(c.isRequired, isFalse);
    });

    test('never blocked by default (minSupportedBuild absent or 0)', () async {
      final net =
          FakeNet()
            ..policy = {'latestVersion': '1.0.9', 'latestBuild': 99}
            ..lookup = storeAnswer('1.0.9');
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.isRequired, isFalse);
      expect(c.status.kind, UpdateKind.available);
    });

    test('unsupported platform (web/desktop): no network at all', () async {
      final net = FakeNet();
      final c = makeController(
        app: const InstalledApp(
          version: '1.0.5',
          build: 1,
          target: UpdateTarget.unsupported,
        ),
        net: net,
      );
      await c.start();
      expect(net.requests, isEmpty);
      c.dispose();
    });
  });

  group('minSupportedBuild', () {
    test('a build below the minimum is required', () async {
      final net =
          FakeNet()
            ..policy = {'minSupportedBuild': 20, 'message_en': 'Fix inside.'}
            ..lookup = storeAnswer('1.0.6');
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.isRequired, isTrue);
      expect(c.status.policy.messageEn, 'Fix inside.');
    });

    test('equal to the minimum is fine (strictly below blocks)', () async {
      final net = FakeNet()..policy = {'minSupportedBuild': 19};
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      expect(c.isRequired, isFalse);
    });

    test('iOS and Android builds are separate numbers', () async {
      final net =
          FakeNet()
            ..policy = {
              'minSupportedBuild': 600,
              'ios': {'minSupportedBuild': 12},
            };
      final ios = makeController(app: iosApp, net: net);
      await ios.check(force: true);
      expect(ios.isRequired, isFalse); // 19 >= 12
      final droid = makeController(app: playApp, net: net, play: FakePlay());
      await droid.check(force: true);
      expect(droid.isRequired, isTrue); // 504 < 600
    });

    test('stays blocked offline from the cached policy, at launch', () async {
      final store = MemoryStore();
      final net = FakeNet()..policy = {'minSupportedBuild': 20};
      await makeController(
        app: iosApp,
        net: net,
        store: store,
      ).check(force: true);
      final offline =
          FakeNet()
            ..policyDown = true
            ..lookupDown = true;
      final c = makeController(app: iosApp, net: offline, store: store);
      await c.start();
      expect(c.isRequired, isTrue);
      c.dispose();
    });

    test(
      'relaxing the minimum unblocks on the next resume, throttle or not',
      () async {
        final now = DateTime(2026, 11, 19, 8);
        final net = FakeNet()..policy = {'minSupportedBuild': 20};
        final c = makeController(app: iosApp, net: net, clock: () => now);
        await c.check();
        expect(c.isRequired, isTrue);
        net.policy = {'minSupportedBuild': 0};
        await c.check(); // same instant, inside the throttle
        expect(c.isRequired, isFalse);
      },
    );

    test('Android build reads with the ABI offset stripped by the loader', () {
      expect(normalizeAndroidBuild(2504) < 600, isTrue);
    });
  });

  group('dismissal', () {
    test('Later hides the banner for that version, then it returns', () async {
      var now = DateTime(2026, 11, 19, 8);
      final net = FakeNet()..lookup = storeAnswer('1.0.6');
      final store = MemoryStore();
      final c = makeController(
        app: iosApp,
        net: net,
        store: store,
        clock: () => now,
      );
      await c.check(force: true);
      expect(c.showBanner, isTrue);
      await c.dismiss();
      expect(c.showBanner, isFalse);
      // survives a restart
      final c2 = makeController(
        app: iosApp,
        net: net,
        store: store,
        clock: () => now,
      );
      await c2.start();
      expect(c2.showBanner, isFalse);
      c2.dispose();
      // after 3 days it asks again
      now = now.add(const Duration(days: 3, minutes: 1));
      await c.check(force: true);
      expect(c.showBanner, isTrue);
    });

    test('a newer store version shows again at once', () async {
      final net = FakeNet()..lookup = storeAnswer('1.0.6');
      final c = makeController(app: iosApp, net: net);
      await c.check(force: true);
      await c.dismiss();
      net.lookup = storeAnswer('1.0.7');
      await c.check(force: true);
      expect(c.showBanner, isTrue);
    });
  });

  group('Android: Play', () {
    test(
      'flexible update starts on its own and the snackbar state follows',
      () async {
        final play =
            FakePlay()
              ..info = const PlayUpdateInfo(
                availability: PlayAvailability.available,
                flexibleAllowed: true,
                immediateAllowed: true,
              );
        final net = FakeNet()..policy = {'latestVersion': '1.0.6'};
        final c = makeController(
          app: playApp,
          net: net,
          play: play,
          config: const UpdateConfig(
            policyUrl: policyUrl,
            androidPackage: 'p.k',
          ),
        );
        await c.start();
        expect(play.flexibleCalls, 1);
        expect(play.immediateCalls, 0);
        expect(c.status.stage, UpdateStage.downloading);
        play.events$.add(PlayInstallEvent.downloaded);
        await Future<void>.delayed(Duration.zero);
        expect(c.readyToRestart, isTrue);
        await c.restartToUpdate();
        expect(play.completeCalls, 1);
        c.dispose();
      },
    );

    test('Kids apps: no auto start, the parent starts it', () async {
      final play =
          FakePlay()
            ..info = const PlayUpdateInfo(
              availability: PlayAvailability.available,
              flexibleAllowed: true,
            );
      final c = makeController(
        app: playApp,
        net: FakeNet(),
        play: play,
        config: const UpdateConfig(
          policyUrl: policyUrl,
          autoStartFlexible: false,
        ),
      );
      await c.check(force: true);
      expect(play.flexibleCalls, 0);
      expect(c.showBanner, isTrue);
      expect(await c.performUpdate(), isTrue);
      expect(play.flexibleCalls, 1);
    });

    test('declining the Play dialog dismisses the banner', () async {
      final play =
          FakePlay()
            ..flexible = PlayStartResult.declined
            ..info = const PlayUpdateInfo(
              availability: PlayAvailability.available,
              flexibleAllowed: true,
            );
      final c = makeController(app: playApp, net: FakeNet(), play: play);
      await c.check(force: true);
      expect(c.showBanner, isFalse);
    });

    test('no update on Play: nothing shown', () async {
      final play =
          FakePlay()
            ..info = const PlayUpdateInfo(availability: PlayAvailability.none);
      final c = makeController(app: playApp, net: FakeNet(), play: play);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('Play cannot answer: fail-open', () async {
      final c = makeController(app: playApp, net: FakeNet(), play: FakePlay());
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('below minSupportedBuild: immediate update', () async {
      final play =
          FakePlay()
            ..info = const PlayUpdateInfo(
              availability: PlayAvailability.available,
              flexibleAllowed: true,
              immediateAllowed: true,
            );
      final net = FakeNet()..policy = {'minSupportedBuild': 600};
      final c = makeController(app: playApp, net: net, play: play);
      await c.check(force: true);
      expect(c.isRequired, isTrue);
      expect(play.flexibleCalls, 0, reason: 'no flexible start while blocked');
      expect(await c.performUpdate(), isTrue);
      expect(play.immediateCalls, 1);
    });

    test(
      'blocked but Play has nothing: falls back to the Play listing',
      () async {
        final play =
            FakePlay()
              ..info = const PlayUpdateInfo(
                availability: PlayAvailability.none,
              );
        final opener = FakeOpener();
        final net = FakeNet()..policy = {'minSupportedBuild': 600};
        final c = makeController(
          app: playApp,
          net: net,
          play: play,
          opener: opener,
          config: const UpdateConfig(
            policyUrl: policyUrl,
            androidPackage: 'p.k',
          ),
        );
        await c.check(force: true);
        expect(await c.performUpdate(), isTrue);
        expect(opener.opened.single.toString(), 'market://details?id=p.k');
      },
    );
  });

  group('Android: direct APK', () {
    test('newer build in the policy shows the downloads link', () async {
      final opener = FakeOpener();
      final net =
          FakeNet()
            ..policy = {
              'latestVersion': '1.0.5',
              'latestBuild': 505,
              'downloadUrl':
                  'https://github.com/airdropfi/app-downloads/releases/tag/x',
            };
      final c = makeController(app: directApp, net: net, opener: opener);
      await c.check(force: true);
      expect(c.showBanner, isTrue);
      await c.performUpdate();
      expect(opener.opened.single.host, 'github.com');
    });

    test('same build: nothing', () async {
      final net =
          FakeNet()
            ..policy = {
              'latestVersion': '1.0.5',
              'latestBuild': 504,
              'downloadUrl': 'https://x.test',
            };
      final c = makeController(app: directApp, net: net);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('no download link published: nothing to offer', () async {
      final net =
          FakeNet()..policy = {'latestVersion': '1.0.9', 'latestBuild': 900};
      final c = makeController(app: directApp, net: net);
      await c.check(force: true);
      expect(c.status.kind, UpdateKind.none);
    });

    test('other Android stores are never prompted', () async {
      final net = FakeNet()..policy = {'minSupportedBuild': 9999};
      final c = makeController(
        app: const InstalledApp(
          version: '1.0.5',
          build: 5,
          target: UpdateTarget.androidOther,
        ),
        net: net,
      );
      await c.check(force: true);
      expect(net.requests, isEmpty);
    });
  });

  group('detectTarget', () {
    UpdateTarget d(TargetPlatform p, {String? installer, bool web = false}) =>
        detectTarget(isWeb: web, platform: p, installerStore: installer);
    test('platforms and installers', () {
      expect(d(TargetPlatform.iOS), UpdateTarget.ios);
      expect(d(TargetPlatform.macOS), UpdateTarget.macos);
      expect(
        d(TargetPlatform.android, installer: 'com.android.vending'),
        UpdateTarget.androidPlay,
      );
      expect(d(TargetPlatform.android), UpdateTarget.androidDirect);
      expect(
        d(
          TargetPlatform.android,
          installer: 'com.google.android.packageinstaller',
        ),
        UpdateTarget.androidDirect,
      );
      expect(
        d(TargetPlatform.android, installer: 'com.sec.android.app.samsungapps'),
        UpdateTarget.androidOther,
      );
      expect(d(TargetPlatform.windows), UpdateTarget.unsupported);
      expect(d(TargetPlatform.iOS, web: true), UpdateTarget.unsupported);
    });
  });

  group('review fixes', () {
    test('macOS without an App Store id opens nothing', () async {
      final opener = FakeOpener();
      final c = makeController(
        app: const InstalledApp(
          version: '1.0.5',
          build: 5,
          target: UpdateTarget.macos,
        ),
        net: FakeNet(),
        opener: opener,
        config: const UpdateConfig(policyUrl: policyUrl),
      );
      expect(await c.performUpdate(), isFalse);
      expect(opener.opened, isEmpty);
    });

    test(
      'an ios section that only sets the minimum is not a published latest',
      () {
        final p = UpdatePolicy.fromJson({
          'latestVersion': '1.0.6',
          'ios': {'minSupportedBuild': 0},
        }, 'ios');
        expect(p.hasPlatformSection, isFalse);
        final q = UpdatePolicy.fromJson({
          'ios': {'latestBuild': 20},
        }, 'ios');
        expect(q.hasPlatformSection, isTrue);
      },
    );

    test(
      'a block with nowhere to send the user is not shown (no store id)',
      () async {
        final net = FakeNet()..policy = {'minSupportedBuild': 20};
        final c = makeController(
          app: iosApp,
          net: net,
          config: const UpdateConfig(policyUrl: policyUrl),
        );
        await c.check(force: true);
        expect(c.isRequired, isFalse);
      },
    );
  });
}
