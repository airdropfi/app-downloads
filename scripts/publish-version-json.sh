#!/usr/bin/env bash
# Publishes <app>/min.json: the tiny, public, server-controlled file the apps'
# update prompt reads (raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/min.json).
#
# Run it when a version goes LIVE on the store (not before): iOS apps compare
# against the App Store listing first and fall back to this file only when
# Apple cannot be reached; direct-APK Android users compare against it.
#
#   scripts/publish-version-json.sh betterkids --version 1.0.6 --android-build 505 --ios-build 20 --push
#   scripts/publish-version-json.sh betterkids --min-ios 19 --min-android 504 \
#       --message-en "This version has a problem. Please update." \
#       --message-vi "Phiên bản này đang gặp lỗi. Vui lòng cập nhật." --push     # block builds < 19 / < 504
#   scripts/publish-version-json.sh betterkids --clear-min --push                  # unblock everyone
#
# Rules (the apps never block by default):
#   * minSupportedBuild stays what it was unless you pass --min-* or --clear-min.
#   * A minimum above the latest build is refused (it would block the newest app).
#   * Builds are plain integers: Android = universal versionCode (< 1000, no ABI
#     offset), iOS = CFBundleVersion, macOS = CFBundleVersion.
set -euo pipefail

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }
die() { echo "publish-version-json: $*" >&2; exit 1; }

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage 0;; esac
app="$1"; shift
[[ "$app" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "bad app slug '$app'"

version=""; android=""; ios=""; macos=""; ios_version=""; macos_version=""
min_android=""; min_ios=""; min_macos=""; clear_min=0
msg_en=""; msg_vi=""; download_url=""; push=0; dry=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2;;
    --ios-version) ios_version="$2"; shift 2;;
    --macos-version) macos_version="$2"; shift 2;;
    --android-build) android="$2"; shift 2;;
    --ios-build) ios="$2"; shift 2;;
    --macos-build) macos="$2"; shift 2;;
    --min-android) min_android="$2"; shift 2;;
    --min-ios) min_ios="$2"; shift 2;;
    --min-macos) min_macos="$2"; shift 2;;
    --clear-min) clear_min=1; shift;;
    --message-en) msg_en="$2"; shift 2;;
    --message-vi) msg_vi="$2"; shift 2;;
    --download-url) download_url="$2"; shift 2;;
    --push) push=1; shift;;
    --dry-run) dry=1; shift;;
    -h|--help) usage 0;;
    *) die "unknown option $1";;
  esac
done

num() { [[ "$2" =~ ^[0-9]+$ ]] || die "$1 must be a whole number, got '$2'"; }
for pair in "android-build:$android" "ios-build:$ios" "macos-build:$macos" \
            "min-android:$min_android" "min-ios:$min_ios" "min-macos:$min_macos"; do
  [ -z "${pair#*:}" ] || num "--${pair%%:*}" "${pair#*:}"
done
for v in "$version" "$ios_version" "$macos_version"; do
  [ -z "$v" ] || [[ "$v" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || die "version must look like 1.0.6, got '$v'"
done
[ -z "$android" ] || [ "$android" -lt 1000 ] || die "--android-build must be the universal versionCode (< 1000), not an ABI-offset one like 2504"
[ -z "$min_android" ] || [ "$min_android" -lt 1000 ] || die "--min-android must be < 1000 (no ABI offset)"
[ "$clear_min" = 0 ] || [ -z "$min_android$min_ios$min_macos" ] || die "--clear-min and --min-* are exclusive"

cd "$(dirname "$0")/.."
dir="$app"; file="$dir/min.json"
mkdir -p "$dir"

if [ "$push" = 1 ] && [ "$dry" = 0 ]; then
  git pull --rebase --quiet origin "$(git rev-parse --abbrev-ref HEAD)"
fi

old='{}'; [ -f "$file" ] && old="$(cat "$file")"
echo "$old" | jq -e 'type=="object"' >/dev/null || die "$file is not a JSON object"

# Direct-APK landing page: default to what latest.json says is current.
if [ -z "$download_url" ] && [ -f "$dir/latest.json" ]; then
  download_url="$(jq -r '.releaseUrl // empty' "$dir/latest.json")"
fi

today="$(date -u +%Y-%m-%d)"
new="$(jq -n --argjson old "$old" \
  --arg app "$app" --arg version "$version" --arg iosv "$ios_version" --arg macv "$macos_version" \
  --arg android "$android" --arg ios "$ios" --arg macos "$macos" \
  --arg minA "$min_android" --arg minI "$min_ios" --arg minM "$min_macos" --argjson clear "$clear_min" \
  --arg en "$msg_en" --arg vi "$msg_vi" --arg url "$download_url" --arg today "$today" '
  def n(s): if s == "" then null else (s | tonumber) end;
  def keep(v; o): if v == "" then o else v end;
  def sect(o; ver; build; min):
    (o // {}) as $o
    | ( { latestVersion: ($o.latestVersion), latestBuild: ($o.latestBuild), minSupportedBuild: ($o.minSupportedBuild // 0) } ) as $b
    | $b
    | (if ver != "" then .latestVersion = ver else . end)
    | (if build != "" then .latestBuild = n(build) else . end)
    | (if $clear == 1 then .minSupportedBuild = 0 elif min != "" then .minSupportedBuild = n(min) else . end)
    | with_entries(select(.value != null));
  ($old
    | .app = $app
    | .latestVersion = keep($version; .latestVersion)
    | .latestBuild = (if $android != "" then n($android) else .latestBuild end)
    | .minSupportedBuild = (if $clear == 1 then 0 elif $minA != "" then n($minA) else (.minSupportedBuild // 0) end)
    | .message_en = keep($en; .message_en)
    | .message_vi = keep($vi; .message_vi)
    | .downloadUrl = keep($url; .downloadUrl)
    | if ($ios != "" or $minI != "" or $iosv != "" or .ios != null)
      then .ios = sect(.ios; keep($iosv; $version); $ios; $minI) else . end
    | if ($macos != "" or $minM != "" or $macv != "" or .macos != null)
      then .macos = sect(.macos; keep($macv; $version); $macos; $minM) else . end
    | if $clear == 1 then del(.message_en, .message_vi) else . end
    | .updated = $today
    | with_entries(select(.value != null))
  )')"

# Never publish a minimum above the latest build.
echo "$new" | jq -e '
  def bad(o): (o.minSupportedBuild // 0) > 0 and o.latestBuild != null and o.minSupportedBuild > o.latestBuild;
  (bad(.) or bad(.ios // {}) or bad(.macos // {})) | not' >/dev/null \
  || die "minSupportedBuild is above latestBuild: that would block the newest app"

if [ "$dry" = 1 ]; then echo "$new" | jq .; exit 0; fi

echo "$new" | jq . > "$file.tmp" && mv "$file.tmp" "$file"
jq -e . "$file" >/dev/null
echo "wrote $file"; jq -c '{latestVersion,latestBuild,minSupportedBuild,ios,macos}' "$file"

if [ "$push" = 1 ]; then
  git add "$file"
  if git diff --cached --quiet; then echo "min.json unchanged, nothing to push"; exit 0; fi
  label="${version:-$(jq -r '.latestVersion // ""' "$file")}"
  if [ -n "$min_android$min_ios$min_macos" ]; then
    git commit -q -m "chore($app): đặt minSupportedBuild trong min.json"
  elif [ "$clear_min" = 1 ]; then
    git commit -q -m "chore($app): gỡ chặn bản cũ trong min.json"
  else
    git commit -q -m "chore($app): đăng min.json $label"
  fi
  git push --quiet origin "$(git rev-parse --abbrev-ref HEAD)"
  echo "pushed"
fi
