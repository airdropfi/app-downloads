# AirdropFi app downloads

Direct-download builds of our apps. Each app is a GitHub Release in this repo; `<app>/latest.json` carries the current version and checksum for update checks.

## Android (APK, direct)

Install steps: download the APK for your phone (arm64-v8a for almost every phone made since 2017; `universal` works everywhere), open it, and allow "Install unknown apps" for your browser when Android asks. Verify the download with the SHA-256 in `latest.json` or the release notes:

    shasum -a 256 <file>.apk

Update checks: fetch `https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/latest.json`.

Apps: storyshort, betterkids, billsai, sportmo. Mac: see each product's Mac App Store listing.

## Signing

APKs are signed with the product's own upload key. A build from Google Play later will use a different signature; Android will ask you to uninstall the direct build first.
