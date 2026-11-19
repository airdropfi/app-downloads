# AirdropFi app downloads

Direct-download builds of our apps. Each app is a GitHub Release in this repo; `<app>/latest.json` carries the current version and checksum for update checks.

## Android (APK, direct)

Install steps: download the APK for your phone (arm64-v8a for almost every phone made since 2017; `universal` works everywhere), open it, and allow "Install unknown apps" for your browser when Android asks. Verify the download with the SHA-256 in `latest.json` or the release notes:

    shasum -a 256 <file>.apk

Update checks: fetch `https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/latest.json`.

## Update prompt for the apps (`<app>/min.json`)

Every app carries the shared update prompt (`packages/app_update_prompt`). It reads one tiny public file per app, `https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/min.json`:

    {
      "latestVersion": "1.0.6", "latestBuild": 505,          // Android (universal versionCode)
      "minSupportedBuild": 0,                                // builds BELOW this are blocked; 0 = nobody
      "message_en": "...", "message_vi": "...",              // optional text on the blocking screen
      "downloadUrl": "https://github.com/airdropfi/app-downloads/releases/tag/...",  // direct-APK installs
      "ios":   { "latestVersion": "1.0.6", "latestBuild": 20, "minSupportedBuild": 0 },
      "macos": { ... }
    }

Release agents write it with `scripts/publish-version-json.sh` when a version goes live (see REPORT in `/tmp/quality/update-prompt/REPORT.md`):

    scripts/publish-version-json.sh <app> --version 1.0.6 --android-build 505 --ios-build 20 --push
    scripts/publish-version-json.sh <app> --min-ios 19 --min-android 504 --message-en "..." --message-vi "..." --push   # mark builds below as broken
    scripts/publish-version-json.sh <app> --clear-min --push                                                          # unblock

The apps never block by default and fail open when the file cannot be fetched. `scripts/vendor-update-prompt.sh <flutter_app_dir>` copies the package into an app.

Apps: storyshort, betterkids, billsai, sportmo, bugsly. Mac: see each product's Mac App Store listing.

## Signing

APKs are signed with the product's own upload key. A build from Google Play later will use a different signature; Android will ask you to uninstall the direct build first.
