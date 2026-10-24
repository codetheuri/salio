#!/usr/bin/env bash
# Checks every APK in a folder before it can reach a phone:
#
# 1. Its version code is the build number in pubspec.yaml (after the +),
#    whatever its processor type (docs/10, D19). The updater compares plain
#    build numbers; Flutter's --split-per-abi adds ABI x 1000 unless
#    android/app/build.gradle.kts takes it off again.
# 2. It carries the native libraries Dart packages build, today SQLite
#    (package:sqlite3). An incremental build made after adding such a
#    package once produced APKs without libsqlite3.so: they install, and
#    crash on the first database query. A clean build includes it.
#
#   mobile-v2/scripts/check-apks.sh [apk folder]
#
# CI runs it, and so will release.sh before publishing.
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

NATIVE_LIBS=(libsqlite3.so)

failed=0
for apk in "${apks[@]}"; do
  name="$(basename "$apk")"
  got="$("$AAPT2" dump badging "$apk" | sed -n "s/^package: .* versionCode='\([0-9]*\)'.*/\1/p")"
  if [[ "$got" != "$WANT" ]]; then
    echo "WRONG $name: version code $got, expected $WANT" >&2
    failed=1
    continue
  fi
  # Every processor type packed in this APK must have each library.
  listing="$(unzip -Z1 "$apk")"
  abis="$(echo "$listing" | sed -n 's#^lib/\([^/]*\)/libflutter.so$#\1#p')"
  missing=""
  for abi in $abis; do
    for lib in "${NATIVE_LIBS[@]}"; do
      echo "$listing" | grep -qx "lib/$abi/$lib" || missing+=" $abi/$lib"
    done
  done
  if [[ -n "$missing" ]]; then
    echo "WRONG $name: missing$missing (run flutter clean, then build again)" >&2
    failed=1
  else
    echo "ok    $name: version code $got, $(echo $abis | wc -w) ABI(s) with ${NATIVE_LIBS[*]}"
  fi
done
exit "$failed"
