#!/usr/bin/env bash
# Builds a signed release of Salio and publishes it for the in-app updater
# and the download page (https://apis.salio.urizon.co.ke/app). Adapted from
# DairyGo's; docs/10 §6.4 is the procedure.
#
#   mobile-v2/scripts/release.sh --notes-en "What changed" [--notes-sw "Kilichobadilika"]
#                                [--rollout 10] [--required]
#
#   --rollout N   offer it to N% of phones first (default 100). Widen later
#                 with scripts/set-rollout.sh once nothing has gone wrong.
#   --required    phones below this build stop syncing until they update
#                 (they keep working offline). For a release whose server
#                 change older apps cannot sync with.
#
# Raise `version:` in pubspec.yaml first (e.g. 2.0.3+15), and deploy any
# server change it needs BEFORE releasing: a newer app on an older server
# fails its syncs (docs/10, §6.4 and B14). The script:
#   1. refuses a dirty tree, then runs the analyzer and the tests;
#   2. builds the prod APKs, one per phone type;
#   3. checks each: version code, native libraries, and the Salio key;
#   4. writes server-v2/releases/ (APKs + latest.json) and tags app-v<version>;
#   5. with SALIO_RELEASE_TARGET=user@host:/path/server-v2/releases set,
#      uploads the APKs first and latest.json last, so no phone ever sees a
#      release whose files are still arriving; with SALIO_RELEASE_URL set
#      (https://apis.salio.urizon.co.ke), checks the live server serves it.
set -euo pipefail

cd "$(dirname "$0")/.."
MOBILE="$(pwd)"
ROOT="$(dirname "$MOBILE")"
RELEASES="$ROOT/server-v2/releases"
FLUTTER="${FLUTTER:-$(command -v flutter || echo /home/joseph/flutter/bin/flutter)}"

NOTES_EN=""
NOTES_SW=""
ROLLOUT=100
REQUIRED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes-en) NOTES_EN="$2"; shift 2 ;;
    --notes-sw) NOTES_SW="$2"; shift 2 ;;
    --rollout) ROLLOUT="$2"; shift 2 ;;
    --required) REQUIRED=1; shift ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
done
[[ -n "$NOTES_EN" ]] || { echo 'Give --notes-en "what changed" (shown to users).' >&2; exit 2; }
[[ "$ROLLOUT" =~ ^[0-9]+$ ]] && (( ROLLOUT >= 1 && ROLLOUT <= 100 )) || {
  echo "--rollout must be 1 to 100." >&2; exit 2; }
[[ -f android/key.properties ]] || {
  echo "No release key (android/key.properties). Run scripts/create-release-key.sh, or restore it from backup." >&2; exit 1; }
EXPECTED="$(tr -d '[:space:]' < android/release-cert.sha256 2>/dev/null || true)"
[[ -n "$EXPECTED" ]] || { echo "android/release-cert.sha256 is missing." >&2; exit 1; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || {
  echo "The working tree has uncommitted changes: release only what is committed." >&2; exit 1; }

FULL="$(sed -n 's/^version: //p' pubspec.yaml)"
VERSION="${FULL%%+*}"
BUILD="${FULL##*+}"
[[ "$VERSION" != "$FULL" && "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "pubspec.yaml version must look like 2.0.3+15" >&2; exit 1; }

PREVIOUS_BUILD=0
PREVIOUS_MIN=0
if [[ -f "$RELEASES/latest.json" ]]; then
  read -r PREVIOUS_BUILD PREVIOUS_MIN < <(python3 -c '
import json,sys; m=json.load(open(sys.argv[1])); print(m["build"], m["min_build"])' "$RELEASES/latest.json")
fi
# Android installs an update only with a higher version code, and every APK
# carries the plain build number (docs/10, D19).
(( BUILD > PREVIOUS_BUILD )) || {
  echo "Build $BUILD is not newer than the published $PREVIOUS_BUILD: raise version in pubspec.yaml." >&2; exit 1; }
if (( REQUIRED )); then MIN_BUILD=$BUILD; else MIN_BUILD=$PREVIOUS_MIN; fi

echo "== Checks"
"$FLUTTER" analyze --fatal-infos
"$FLUTTER" test

echo "== Build $VERSION ($BUILD)"
"$FLUTTER" build apk --release --flavor prod --split-per-abi
OUT="$MOBILE/build/app/outputs/flutter-apk"
scripts/check-apks.sh "$OUT"

# Only an APK signed with the Salio key is published: phones refuse any
# other as an update. The fingerprint is public (android/release-cert.sha256).
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$(sed -n 's/^sdk\.dir=//p' android/local.properties 2>/dev/null)}}"
APKSIGNER="$(ls -d "${SDK:-$HOME/Android/Sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
[[ -x "$APKSIGNER" ]] || { echo "apksigner not found (Android SDK build-tools)." >&2; exit 1; }
declare -A ABI_FILE=([arm64]=app-arm64-v8a-prod-release.apk [armv7]=app-armeabi-v7a-prod-release.apk)

mkdir -p "$RELEASES"
for abi in arm64 armv7; do
  src="$OUT/${ABI_FILE[$abi]}"
  signer="$("$APKSIGNER" verify --print-certs "$src" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  if [[ "$signer" != "$EXPECTED" ]]; then
    echo "$src is not signed with the Salio key (got ${signer:-none}); refusing to publish it." >&2; exit 1
  fi
  cp "$src" "$RELEASES/Salio-$VERSION-$abi.apk"
done
# Older APKs are no longer offered.
find "$RELEASES" -maxdepth 1 -name 'Salio-*.apk' ! -name "Salio-$VERSION-*.apk" -delete

python3 - "$RELEASES" "$VERSION" "$BUILD" "$MIN_BUILD" "$ROLLOUT" "$NOTES_EN" "$NOTES_SW" <<'PY'
import datetime, hashlib, json, os, sys
releases, version, build, min_build, rollout, notes_en, notes_sw = sys.argv[1:]
files = {}
for abi in ("arm64", "armv7"):
    name = f"Salio-{version}-{abi}.apk"
    data = open(os.path.join(releases, name), "rb").read()
    files[abi] = {"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
notes = {"en": notes_en}
if notes_sw:
    notes["sw"] = notes_sw
manifest = {
    "version": version, "build": int(build), "min_build": int(min_build),
    "rollout_percent": int(rollout), "notes": notes,
    "published_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "files": files,
}
tmp = os.path.join(releases, "latest.json.tmp")
with open(tmp, "w") as f:
    json.dump(manifest, f, indent=2)
os.replace(tmp, os.path.join(releases, "latest.json"))
PY

TAG="app-v$VERSION+$BUILD"
git -C "$ROOT" tag -a "$TAG" -m "Salio app $VERSION (build $BUILD), rollout $ROLLOUT%" 2>/dev/null \
  || echo "Tag $TAG already exists; left as it is."

echo
echo "Release $VERSION (build $BUILD) ready in $RELEASES, offered to $ROLLOUT% of phones."
(( REQUIRED )) && echo "Required: apps below build $MIN_BUILD stop syncing until they update."
if [[ -n "${SALIO_RELEASE_TARGET:-}" ]]; then
  # APKs first, the manifest last, then remove what is no longer listed.
  rsync -av --exclude latest.json "$RELEASES/" "$SALIO_RELEASE_TARGET/"
  rsync -av "$RELEASES/latest.json" "$SALIO_RELEASE_TARGET/"
  rsync -av --delete --exclude latest.json "$RELEASES/" "$SALIO_RELEASE_TARGET/"
  echo "Uploaded."
else
  echo "Upload: copy the APKs to the server's server-v2/releases/, then latest.json last."
fi
if [[ -n "${SALIO_RELEASE_URL:-}" ]]; then
  live="$(curl -sf "$SALIO_RELEASE_URL/api/v1/app/version" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["build"])' || true)"
  if [[ "$live" == "$BUILD" ]]; then
    echo "The live server offers build $BUILD."
  else
    echo "The live server offers build ${live:-nothing}, not $BUILD: check the upload." >&2; exit 1
  fi
fi
echo "Push the tag when ready: git push origin $TAG"
