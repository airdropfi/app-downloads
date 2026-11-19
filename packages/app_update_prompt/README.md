# app_update_prompt

Shared update prompt for the AirdropFi Flutter apps. Canonical source; apps carry a vendored copy in `third_party/app_update_prompt` (`scripts/vendor-update-prompt.sh <flutter_app_dir>`), same API and tests everywhere.

- **Apple (iOS, macOS):** on launch and on resume (at most once per 12 h) asks `https://itunes.apple.com/lookup?id=<id>&country=<cc>` (public, no key, nothing about the user is sent) and offers the App Store page only when the store version is newer than the installed one (so the lookup lag never produces a prompt for a version nobody can install yet).
- **Android from Google Play:** Play In-App Updates: flexible by default (background download, "Restart" snackbar), immediate for builds below `minSupportedBuild`.
- **Android from an APK:** a link to the release page (`downloadUrl` in `min.json`).
- **Server minimum (`<app>/min.json`):** builds below `minSupportedBuild` get a blocking but friendly "Please update" screen. Never blocks by default; fails open when the file cannot be fetched.
- **Kids apps:** `UpdateBanner(beforeUpdate: showParentalGate)` and `UpdatePromptHost(beforeUpdate: ...)` run the parental gate before any link or store opens; `UpdateConfig(forParents: true, autoStartFlexible: false)`.

Wire-up:

```dart
final updates = createUpdateController(const UpdateConfig(
  policyUrl: 'https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/min.json',
  appStoreId: '<numeric id or null>', androidPackage: 'com.kienphan.<app>'));
// MaterialApp(navigatorKey: nav, builder: (c, child) =>
//   UpdatePromptHost(controller: updates, navigatorKey: nav, child: child!));
// ... UpdateBanner(controller: updates) at the top of a home/settings screen.
```

Tests: `flutter test` in this directory (version compare incl. Android ABI offsets, throttle, fail-open, lookup lag, Play flows, gate, a11y, 56 dp, 12 words, five languages).
