#!/usr/bin/env bash
# Copies the canonical update-prompt package (packages/app_update_prompt) into
# a Flutter app as <app>/third_party/app_update_prompt, so every app ships the
# same vetted code and tests. Re-run after a change here, then commit the diff
# in the app repo.
#
#   scripts/vendor-update-prompt.sh /path/to/flutter_app_dir
#   scripts/vendor-update-prompt.sh --check /path/to/flutter_app_dir   # exit 1 if the copy drifted
set -euo pipefail
check=0; [ "${1:-}" = "--check" ] && { check=1; shift; }
dest="${1:?usage: vendor-update-prompt.sh [--check] <flutter_app_dir>}"
src="$(cd "$(dirname "$0")/.." && pwd)/packages/app_update_prompt"
target="$dest/third_party/app_update_prompt"
[ -f "$dest/pubspec.yaml" ] || { echo "no pubspec.yaml in $dest" >&2; exit 1; }
excl=(--exclude .dart_tool --exclude pubspec.lock --exclude build --exclude .packages --exclude .flutter-plugins-dependencies --exclude .flutter-plugins)
if [ "$check" = 1 ]; then
  diff -rq -x .dart_tool -x pubspec.lock -x build -x .packages -x .flutter-plugins-dependencies -x .flutter-plugins "$src" "$target" && exit 0
  exit 1
fi
mkdir -p "$target"
rsync -rc --delete "${excl[@]}" "$src/" "$target/"
echo "vendored into $target"
