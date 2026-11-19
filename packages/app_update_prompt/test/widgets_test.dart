import 'package:app_update_prompt/app_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<UpdateController> availableIos(
  FakeOpener opener, {
  FakePlay? play,
}) async {
  final net = FakeNet()..lookup = storeAnswer('1.0.6');
  final c = makeController(app: iosApp, net: net, opener: opener);
  await c.check(force: true);
  return c;
}

Widget host(
  Widget body, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [
    Locale('en'),
    Locale('vi'),
    Locale('zh'),
    Locale('ko'),
    Locale('ja'),
  ],
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

void main() {
  group('UpdateBanner', () {
    testWidgets('shows nothing when there is nothing to show', (t) async {
      final c = makeController(app: iosApp, net: FakeNet());
      await t.pumpWidget(host(UpdateBanner(controller: c)));
      expect(find.byKey(const Key('update_banner')), findsNothing);
    });

    testWidgets('Update opens the store; Later hides it', (t) async {
      final opener = FakeOpener();
      final c = await availableIos(opener);
      await t.pumpWidget(host(UpdateBanner(controller: c)));
      expect(find.text('A new version is ready'), findsOneWidget);
      await t.tap(find.byKey(const Key('update_banner_action')));
      await t.pump();
      expect(opener.opened, hasLength(1));
      await t.tap(find.byKey(const Key('update_banner_later')));
      await t.pump();
      expect(find.byKey(const Key('update_banner')), findsNothing);
    });

    testWidgets('the gate runs first; a failed gate opens nothing', (t) async {
      final opener = FakeOpener();
      final c = await availableIos(opener);
      var asked = 0;
      var pass = false;
      await t.pumpWidget(
        host(
          UpdateBanner(
            controller: c,
            beforeUpdate: (_) async {
              asked++;
              return pass;
            },
          ),
        ),
      );
      await t.tap(find.byKey(const Key('update_banner_action')));
      await t.pump();
      expect(asked, 1);
      expect(opener.opened, isEmpty);
      pass = true;
      await t.tap(find.byKey(const Key('update_banner_action')));
      await t.pump();
      expect(opener.opened, hasLength(1));
    });

    testWidgets('buttons are at least 56 dp tall and wide', (t) async {
      final c = await availableIos(FakeOpener());
      await t.pumpWidget(host(UpdateBanner(controller: c)));
      for (final k in ['update_banner_action', 'update_banner_later']) {
        final size = t.getSize(find.byKey(Key(k)));
        expect(size.height, greaterThanOrEqualTo(56), reason: k);
        expect(size.width, greaterThanOrEqualTo(56), reason: k);
      }
    });

    testWidgets('banner copy is at most 12 words in every language', (t) async {
      final c = await availableIos(FakeOpener());
      for (final l in UpdateCopy.languages) {
        await t.pumpWidget(
          host(UpdateBanner(controller: c), locale: Locale(l)),
        );
        final texts = t.widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('update_banner')),
            matching: find.byType(Text),
          ),
        );
        final words = texts
            .map((w) => (w.data ?? '').split(RegExp(r'\s+')).length)
            .fold<int>(0, (a, b) => a + b);
        expect(words, lessThanOrEqualTo(12), reason: l);
        expect(find.text(UpdateCopy.forLanguage(l).title), findsOneWidget);
      }
    });

    testWidgets('survives 2x text and a narrow phone without overflow', (
      t,
    ) async {
      final c = await availableIos(FakeOpener());
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        host(
          UpdateBanner(controller: c),
          locale: const Locale('vi'),
          textScale: 2,
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('announces itself and labels Later for screen readers', (
      t,
    ) async {
      final c = await availableIos(FakeOpener());
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(UpdateBanner(controller: c)));
      expect(
        t.getSemantics(find.byKey(const Key('update_banner_action'))),
        matchesSemantics(
          label: 'Update',
          isButton: true,
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Dismiss update notice'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a downloaded Play update offers Restart', (t) async {
      final play = FakePlay()
        ..info = const PlayUpdateInfo(
          availability: PlayAvailability.available,
          flexibleAllowed: true,
          downloaded: true,
        );
      final c = makeController(app: playApp, net: FakeNet(), play: play);
      await c.check(force: true);
      await t.pumpWidget(host(UpdateBanner(controller: c)));
      expect(find.text('Update downloaded'), findsOneWidget);
      await t.tap(find.text('Restart'));
      expect(play.completeCalls, 1);
    });
  });

  group('UpdatePromptHost', () {
    Widget app(
      UpdateController c,
      GlobalKey<NavigatorState> nav, {
      BeforeUpdate? gate,
    }) => MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => UpdatePromptHost(
        controller: c,
        navigatorKey: nav,
        beforeUpdate: gate,
        child: child!,
      ),
      home: const Scaffold(body: Text('app home')),
    );

    testWidgets(
      'a blocked build gets the Please update screen, not a way out',
      (t) async {
        final net = FakeNet()
          ..policy = {'minSupportedBuild': 20, 'message_en': 'Fix inside.'};
        final opener = FakeOpener();
        final c = makeController(app: iosApp, net: net, opener: opener);
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(app(c, nav));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('update_required')), findsOneWidget);
        expect(find.text('Please update'), findsOneWidget);
        expect(find.text('Fix inside.'), findsOneWidget);
        // Back does not close it.
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('update_required')), findsOneWidget);
        // One button, 56 dp.
        final size = t.getSize(find.byKey(const Key('update_required_action')));
        expect(size.height, greaterThanOrEqualTo(56));
        await t.tap(find.byKey(const Key('update_required_action')));
        await t.pump();
        expect(opener.opened, hasLength(1));
      },
    );

    testWidgets('the gate guards the blocking screen too', (t) async {
      final net = FakeNet()..policy = {'minSupportedBuild': 20};
      final opener = FakeOpener();
      final c = makeController(
        app: iosApp,
        net: net,
        opener: opener,
        config: const UpdateConfig(
          policyUrl: policyUrl,
          appStoreId: '1',
          forParents: true,
        ),
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(c, nav, gate: (_) async => false));
      await t.pumpAndSettle();
      expect(
        find.text(UpdateCopy.forLanguage('en').requiredBodyForParents),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('update_required_action')));
      await t.pump();
      expect(opener.opened, isEmpty);
    });

    testWidgets('lifting the block removes the screen', (t) async {
      final net = FakeNet()..policy = {'minSupportedBuild': 20};
      final c = makeController(app: iosApp, net: net);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(c, nav));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update_required')), findsOneWidget);
      net.policy = {'minSupportedBuild': 0};
      await c.check(force: true);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update_required')), findsNothing);
      expect(find.text('app home'), findsOneWidget);
    });

    testWidgets('a healthy build is untouched', (t) async {
      final c = makeController(
        app: iosApp,
        net: FakeNet()..lookup = storeAnswer('1.0.5'),
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(c, nav));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update_required')), findsNothing);
      expect(find.text('app home'), findsOneWidget);
    });

    testWidgets('Vietnamese server message wins in Vietnamese', (t) async {
      final net = FakeNet()
        ..policy = {
          'minSupportedBuild': 20,
          'message_en': 'EN',
          'message_vi': 'VI',
        };
      final c = makeController(app: iosApp, net: net);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          locale: const Locale('vi'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('vi')],
          builder: (context, child) =>
              UpdatePromptHost(controller: c, navigatorKey: nav, child: child!),
          home: const Scaffold(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('VI'), findsOneWidget);
      expect(find.text('Vui lòng cập nhật'), findsOneWidget);
    });

    testWidgets('Play flexible download shows a Restart snackbar', (t) async {
      final play = FakePlay()
        ..info = const PlayUpdateInfo(
          availability: PlayAvailability.available,
          flexibleAllowed: true,
        );
      final c = makeController(app: playApp, net: FakeNet(), play: play);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(c, nav));
      await t.pumpAndSettle();
      play.events$.add(PlayInstallEvent.downloaded);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update_restart_snack')), findsOneWidget);
      await t.tap(find.text('Restart'));
      expect(play.completeCalls, 1);
    });
  });
}
