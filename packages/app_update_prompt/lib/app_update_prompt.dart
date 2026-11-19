/// Shared update prompt for AirdropFi Flutter apps.
///
/// ```dart
/// final updates = createUpdateController(UpdateConfig(
///   policyUrl: 'https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/min.json',
///   appStoreId: '6797240519',
///   androidPackage: 'com.kienphan.betterkids',
/// ));
/// // MaterialApp(navigatorKey: nav, builder: (c, child) =>
/// //   UpdatePromptHost(controller: updates, navigatorKey: nav, child: child!))
/// // and put UpdateBanner(controller: updates) on a home/settings screen.
/// ```
library;

export 'src/adapters.dart'
    show
        createUpdateController,
        detectTarget,
        httpJsonFetcher,
        loadInstalledApp;
export 'src/config.dart';
export 'src/controller.dart';
export 'src/demo.dart';
export 'src/copy.dart';
export 'src/policy.dart';
export 'src/ports.dart';
export 'src/status.dart';
export 'src/version.dart';
export 'src/widgets.dart';
