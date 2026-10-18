#!/usr/bin/env bash
# Checks that every APK in a folder has the version code in pubspec.yaml
# (the number after the +), whatever its processor type (docs/10, D19).
#
#   mobile-v2/scripts/check-version-codes.sh [apk folder]
#
# The updater compares plain build numbers. Flutter's --split-per-abi adds
# ABI x 1000 to each APK's code unless android/app/build.gradle.kts takes it
# off again; this is the check that it did. CI runs it, and so will
# release.sh before publishing.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="${1:-build/app/outputs/flutter-apk}"
WANT="$(sed -n 's/^version: .*+\([0-9]*\)$/\1/p' pubspec.yaml)"
[[ -n "$WANT" ]] || { echo "No build number in pubspec.yaml's version." >&2; exit 1; }

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
AAPT2="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)aapt2"
[[ -x "$AAPT2" ]] || { echo "aapt2 not found under $SDK/build-tools." >&2; exit 1; }

shopt -s nullglob
apks=("$DIR"/*.apk)
[[ ${#apks[@]} -gt 0 ]] || { echo "No APKs in $DIR." >&2; exit 1; }

failed=0
for apk in "${apks[@]}"; do
  got="$("$AAPT2" dump badging "$apk" | sed -n "s/^package: .* versionCode='\([0-9]*\)'.*/\1/p")"
  if [[ "$got" == "$WANT" ]]; then
    echo "ok    $got  $(basename "$apk")"
  else
    echo "WRONG $got  $(basename "$apk") (expected $WANT)" >&2
    failed=1
  fi
done
exit "$failed"
